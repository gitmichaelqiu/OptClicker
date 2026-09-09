import AppKit
import CryptoKit
import Darwin
import Foundation
import ServiceManagement

@discardableResult
private func runOptClickerMigrationTool(_ path: String, arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    } catch {
        print("OptClicker IdentityMigration: failed to run \(path): \(error)")
        return false
    }
}

final class OptClickerBridgeMigrationManager: NSObject {
    static let shared = OptClickerBridgeMigrationManager()

    private var hasPresentedPrompt = false
    private var completion: (() -> Void)?
    private var stageMonitor: Timer?
    private var stageMonitorDeadline: Date?
    private var installerWasObserved = false
    private var installerLaunchDeadline: Date?
    private var stageLaunchStarted = false
    private var downloadTask: URLSessionDownloadTask?
    private var manifestURL: URL?

    private override init() {}

    /// Pauses normal startup only for a configured legacy bridge build.
    func beginIfNeeded(completion: @escaping () -> Void) -> Bool {
        guard OptClickerIdentity.isLegacyBridge,
              OptClickerMigrationConfiguration.isConfigured else { return false }

        self.completion = completion
        OptClickerIdentityMigration.prepareLegacyBridgeLaunch()
        guard !hasPresentedPrompt else { return true }
        hasPresentedPrompt = true

        if resumePendingMigrationIfNeeded() { return true }
        DispatchQueue.main.async { [weak self] in self?.presentMigrationPrompt() }
        return true
    }

    private func presentMigrationPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "OptClicker needs a one-time update"
        alert.informativeText = "This update changes OptClicker’s application identity so future updates and permissions continue to work. Your settings will be preserved, and the previous application will be removed only after the new one starts successfully."
        alert.addButton(withTitle: "Migrate Now")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            startMigration()
        } else {
            continueNormalApplication()
        }
    }

    private func resumePendingMigrationIfNeeded() -> Bool {
        guard FileManager.default.fileExists(atPath: OptClickerMigrationStorage.manifestURL.path),
              let manifest = try? OptClickerMigrationStorage.readManifest(),
              let expectedVersion = OptClickerMigrationConfiguration.packageVersion else { return false }

        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let stagingURL = OptClickerMigrationConfiguration.stagingApplicationURL
        guard manifest.schemaVersion == OptClickerMigrationManifest.currentSchemaVersion,
              manifest.sourceApplicationPath == sourceURL.path,
              manifest.targetBundleIdentifier == OptClickerIdentity.currentBundleIdentifier,
              manifest.stagingApplicationPath == stagingURL.path,
              OptClickerMigrationVersion.isAtLeast(expectedVersion, manifest.expectedVersion),
              let stagedBundle = Bundle(url: stagingURL),
              stagedBundle.bundleIdentifier == OptClickerIdentity.currentBundleIdentifier,
              let stagedVersion = stagedBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return false
        }

        manifestURL = OptClickerMigrationStorage.manifestURL
        if stagedVersion == expectedVersion {
            DispatchQueue.main.async { [weak self] in self?.launchInstalledStagingApplication() }
        } else if OptClickerMigrationVersion.isAtLeast(expectedVersion, stagedVersion) {
            DispatchQueue.main.async { [weak self] in
                self?.startMigration(launchAtLoginEnabled: manifest.launchAtLoginEnabled)
            }
        } else {
            return false
        }
        return true
    }

    private func startMigration(launchAtLoginEnabled: Bool? = nil) {
        guard let packageURL = OptClickerMigrationConfiguration.packageURL,
              let expectedHash = OptClickerMigrationConfiguration.packageSHA256,
              let expectedVersion = OptClickerMigrationConfiguration.packageVersion else {
            showFailure(OptClickerMigrationError.invalidConfiguration)
            return
        }

        stageLaunchStarted = false
        guard terminateRunningStagingApplicationsIfNeeded() else {
            showFailure(OptClickerMigrationError.stagingApplicationDidNotTerminate)
            return
        }

        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let manifest = OptClickerMigrationManifest(
            schemaVersion: OptClickerMigrationManifest.currentSchemaVersion,
            sourceApplicationPath: sourceURL.path,
            sourceProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            targetBundleIdentifier: OptClickerIdentity.currentBundleIdentifier,
            stagingApplicationPath: OptClickerMigrationConfiguration.stagingApplicationURL.path,
            launchAtLoginEnabled: launchAtLoginEnabled
                ?? (SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval),
            expectedVersion: expectedVersion,
            createdAt: Date()
        )

        do {
            try OptClickerMigrationStorage.writeManifest(manifest)
            manifestURL = OptClickerMigrationStorage.manifestURL
        } catch {
            showFailure(error)
            return
        }

        downloadMigrationPackage(at: packageURL, expectedSHA256: expectedHash)
    }

    private func downloadMigrationPackage(at packageURL: URL, expectedSHA256: String) {
        downloadTask = URLSession.shared.downloadTask(with: packageURL) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            if let error {
                self.finishDownload(.failure(error))
                return
            }
            guard let temporaryURL,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                self.finishDownload(.failure(OptClickerMigrationError.invalidDownloadResponse))
                return
            }

            do {
                let packageURL = try self.cacheDownloadedPackage(at: temporaryURL)
                try self.validatePackage(at: packageURL, expectedSHA256: expectedSHA256)
                self.finishDownload(.success(packageURL))
            } catch {
                self.finishDownload(.failure(error))
            }
        }
        downloadTask?.resume()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Preparing OptClicker migration"
        alert.informativeText = "The verified migration package will open in Installer when it is ready."
        alert.addButton(withTitle: "Continue")
        DispatchQueue.main.async { alert.runModal() }
    }

    private func finishDownload(_ result: Result<URL, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadTask = nil
            switch result {
            case .success(let packageURL): self.installPackage(at: packageURL)
            case .failure(let error): self.showFailure(error)
            }
        }
    }

    private func cacheDownloadedPackage(at temporaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = OptClickerMigrationStorage.cacheDirectoryURL
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let packageURL = directoryURL.appendingPathComponent("OptClicker-Migration.pkg")
        if fileManager.fileExists(atPath: packageURL.path) { try fileManager.removeItem(at: packageURL) }
        try fileManager.moveItem(at: temporaryURL, to: packageURL)
        return packageURL
    }

    private func validatePackage(at packageURL: URL, expectedSHA256: String) throws {
        let actualHash = SHA256.hash(data: try Data(contentsOf: packageURL)).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedSHA256 else { throw OptClickerMigrationError.invalidPackageHash }

        if !OptClickerMigrationConfiguration.allowsManualApproval {
            guard runOptClickerMigrationTool("/usr/sbin/pkgutil", arguments: ["--check-signature", packageURL.path]),
                  runOptClickerMigrationTool("/usr/sbin/spctl", arguments: ["--assess", "--type", "install", packageURL.path]) else {
                throw OptClickerMigrationError.packageVerificationFailed
            }
        }
    }

    private func installPackage(at packageURL: URL) {
        guard NSWorkspace.shared.open(packageURL) else {
            showFailure(OptClickerMigrationError.packageVerificationFailed)
            return
        }
        installerWasObserved = false
        installerLaunchDeadline = Date().addingTimeInterval(20)
        stageMonitorDeadline = Date().addingTimeInterval(10 * 60)
        stageMonitor?.invalidate()
        stageMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkForInstalledStagingApplication()
        }
    }

    private func checkForInstalledStagingApplication() {
        guard !stageLaunchStarted else { return }
        if let deadline = stageMonitorDeadline, Date() > deadline {
            stopStageMonitoring()
            showFailure(OptClickerMigrationError.stagingApplicationNotFound)
            return
        }

        let stagingURL = OptClickerMigrationConfiguration.stagingApplicationURL
        guard let bundle = Bundle(url: stagingURL),
              bundle.bundleIdentifier == OptClickerIdentity.currentBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == OptClickerMigrationConfiguration.packageVersion else {
            let installerIsRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == "com.apple.installer" && !$0.isTerminated
            }
            if installerIsRunning { installerWasObserved = true }
            else if installerWasObserved {
                stopStageMonitoring()
                showFailure(OptClickerMigrationError.installerClosed)
            } else if let installerLaunchDeadline, Date() > installerLaunchDeadline {
                stopStageMonitoring()
                showFailure(OptClickerMigrationError.stagingApplicationNotFound)
            }
            return
        }

        launchInstalledStagingApplication()
    }

    private func launchInstalledStagingApplication() {
        guard !stageLaunchStarted else { return }
        stageLaunchStarted = true
        stopStageMonitoring()
        guard let manifestURL else {
            showFailure(OptClickerMigrationError.manifestInvalid)
            return
        }
        waitForStagingApplicationsToTerminate(
            at: OptClickerMigrationConfiguration.stagingApplicationURL,
            manifestURL: manifestURL,
            attemptsRemaining: 20,
            didForceTerminate: false
        )
    }

    private func waitForStagingApplicationsToTerminate(at stagingURL: URL, manifestURL: URL, attemptsRemaining: Int, didForceTerminate: Bool) {
        let runningApplications = runningStagingApplications(at: stagingURL)
        guard !runningApplications.isEmpty else {
            openStagingApplication(at: stagingURL, manifestURL: manifestURL)
            return
        }
        guard attemptsRemaining > 0 else {
            guard !didForceTerminate else {
                showFailure(OptClickerMigrationError.stagingApplicationDidNotTerminate)
                return
            }
            let success = runningApplications.allSatisfy { $0.forceTerminate() || !isRunning($0) }
            guard success else {
                showFailure(OptClickerMigrationError.stagingApplicationDidNotTerminate)
                return
            }
            waitForStagingApplicationsToTerminate(at: stagingURL, manifestURL: manifestURL, attemptsRemaining: 20, didForceTerminate: true)
            return
        }
        runningApplications.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForStagingApplicationsToTerminate(at: stagingURL, manifestURL: manifestURL, attemptsRemaining: attemptsRemaining - 1, didForceTerminate: didForceTerminate)
        }
    }

    private func openStagingApplication(at stagingURL: URL, manifestURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--optclicker-migration", "--optclicker-migration-manifest", manifestURL.path]
        NSWorkspace.shared.openApplication(at: stagingURL, configuration: configuration) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.showFailure(error) } }
        }
    }

    private func terminateRunningStagingApplicationsIfNeeded() -> Bool {
        let applications = runningStagingApplications(at: OptClickerMigrationConfiguration.stagingApplicationURL)
        guard !applications.isEmpty else { return true }
        applications.forEach { $0.terminate() }
        return applications.allSatisfy { $0.forceTerminate() || !isRunning($0) }
    }

    private func runningStagingApplications(at stagingURL: URL) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard application.bundleIdentifier == OptClickerIdentity.currentBundleIdentifier,
                  application.bundleURL?.standardizedFileURL == stagingURL.standardizedFileURL else { return false }
            return isRunning(application)
        }
    }

    private func isRunning(_ application: NSRunningApplication) -> Bool {
        let pid = application.processIdentifier
        return pid > 0 && (Darwin.kill(pid, 0) == 0 || errno == EPERM)
    }

    private func stopStageMonitoring() {
        stageMonitor?.invalidate()
        stageMonitor = nil
        stageMonitorDeadline = nil
        installerWasObserved = false
        installerLaunchDeadline = nil
    }

    private func continueNormalApplication() {
        stopStageMonitoring()
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    private func showFailure(_ error: Error) {
        stopStageMonitoring()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OptClicker migration was not completed"
        alert.informativeText = "\(error.localizedDescription) The current application was left available so you can retry the migration later."
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            stageLaunchStarted = false
            startMigration()
        } else {
            continueNormalApplication()
        }
    }
}
