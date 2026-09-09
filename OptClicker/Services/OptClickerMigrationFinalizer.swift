import AppKit
import Darwin
import Foundation

final class OptClickerMigrationFinalizer {
    static let shared = OptClickerMigrationFinalizer()

    private var manifest: OptClickerMigrationManifest?
    private var backupURL: URL?
    private var temporaryTargetURL: URL?
    private var launchAttempts = 0

    private init() {}

    static var isRequested: Bool {
        if CommandLine.arguments.contains("--optclicker-migration") { return true }
        guard OptClickerIdentity.isCurrentApplication,
              Bundle.main.bundleURL.standardizedFileURL == OptClickerMigrationConfiguration.stagingApplicationURL,
              FileManager.default.fileExists(atPath: OptClickerMigrationStorage.manifestURL.path) else { return false }
        return true
    }

    func startIfRequested() -> Bool {
        guard Self.isRequested else { return false }
        DispatchQueue.main.async { [weak self] in self?.start() }
        return true
    }

    private func start() {
        NSApp.setActivationPolicy(.accessory)
        do {
            guard OptClickerIdentity.isCurrentApplication else { throw OptClickerMigrationError.stagingApplicationInvalid }
            let manifest = try readManifestFromArguments()
            guard manifest.schemaVersion == OptClickerMigrationManifest.currentSchemaVersion,
                  manifest.targetBundleIdentifier == OptClickerIdentity.currentBundleIdentifier,
                  manifest.stagingApplicationPath == Bundle.main.bundleURL.standardizedFileURL.path,
                  let stagedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  OptClickerMigrationVersion.isAtLeast(stagedVersion, manifest.expectedVersion) else {
                throw OptClickerMigrationError.manifestInvalid
            }
            self.manifest = manifest
            OptClickerIdentityMigration.migrateLegacyDefaults(launchAtLoginEnabled: manifest.launchAtLoginEnabled)
            terminateLegacyApplicationIfNeeded()
        } catch {
            failMigration(error)
        }
    }

    private func readManifestFromArguments() throws -> OptClickerMigrationManifest {
        guard let index = CommandLine.arguments.firstIndex(of: "--optclicker-migration-manifest"),
              index + 1 < CommandLine.arguments.count else { return try OptClickerMigrationStorage.readManifest() }
        let path = CommandLine.arguments[index + 1]
        guard path.hasPrefix("/") else { throw OptClickerMigrationError.manifestInvalid }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        guard candidate == OptClickerMigrationStorage.manifestURL.standardizedFileURL else { throw OptClickerMigrationError.manifestInvalid }
        return try OptClickerMigrationStorage.readManifest()
    }

    private func terminateLegacyApplicationIfNeeded() {
        guard let manifest else {
            failMigration(OptClickerMigrationError.manifestInvalid)
            return
        }
        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true).standardizedFileURL
        let applications = NSWorkspace.shared.runningApplications.filter { application in
            guard application.bundleIdentifier == OptClickerIdentity.legacyBundleIdentifier else { return false }
            return application.bundleURL?.standardizedFileURL == sourceURL
                || application.processIdentifier == manifest.sourceProcessIdentifier
        }.filter(isRunning)

        guard !applications.isEmpty else {
            performApplicationSwap()
            return
        }
        applications.forEach { $0.terminate() }
        waitForLegacyApplicationsToTerminate(applications, sourceURL: sourceURL, attemptsRemaining: 20, didForceTerminate: false)
    }

    private func waitForLegacyApplicationsToTerminate(_ applications: [NSRunningApplication], sourceURL: URL, attemptsRemaining: Int, didForceTerminate: Bool) {
        let runningApplications = applications.filter(isRunning)
        guard !runningApplications.isEmpty else {
            performApplicationSwap()
            return
        }
        guard attemptsRemaining > 0 else {
            guard !didForceTerminate else {
                failMigration(OptClickerMigrationError.legacyApplicationDidNotTerminate)
                return
            }
            let terminated = runningApplications.allSatisfy { application in
                if application.forceTerminate() { return true }
                let pid = application.processIdentifier
                guard isVerifiedLegacyApplication(application, sourceURL: sourceURL) else { return false }
                return Darwin.kill(pid, SIGKILL) == 0 || errno == ESRCH
            }
            guard terminated else {
                failMigration(OptClickerMigrationError.legacyApplicationDidNotTerminate)
                return
            }
            waitForLegacyApplicationsToTerminate(applications, sourceURL: sourceURL, attemptsRemaining: 20, didForceTerminate: true)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForLegacyApplicationsToTerminate(applications, sourceURL: sourceURL, attemptsRemaining: attemptsRemaining - 1, didForceTerminate: didForceTerminate)
        }
    }

    private func performApplicationSwap() {
        guard let manifest else {
            failMigration(OptClickerMigrationError.manifestInvalid)
            return
        }
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: manifest.sourceApplicationPath, isDirectory: true).standardizedFileURL
        let stagingURL = Bundle.main.bundleURL.standardizedFileURL
        let parentURL = sourceURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appendingPathComponent(".OptClicker-new-\(UUID().uuidString).app")
        let backupURL = parentURL.appendingPathComponent(".OptClicker-legacy-\(UUID().uuidString).app")

        do {
            guard sourceURL.pathExtension == "app", sourceURL != stagingURL else { throw OptClickerMigrationError.targetApplicationInvalid }
            if fileManager.fileExists(atPath: sourceURL.path), bundleIdentifier(at: sourceURL) != OptClickerIdentity.legacyBundleIdentifier {
                throw OptClickerMigrationError.targetApplicationInvalid
            }

            try fileManager.copyItem(at: stagingURL, to: temporaryURL)
            guard bundleIdentifier(at: temporaryURL) == OptClickerIdentity.currentBundleIdentifier else {
                throw OptClickerMigrationError.stagingApplicationInvalid
            }
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: sourceURL, to: backupURL)
                self.backupURL = backupURL
            }
            try fileManager.moveItem(at: temporaryURL, to: sourceURL)
            temporaryTargetURL = temporaryURL
            guard bundleIdentifier(at: sourceURL) == OptClickerIdentity.currentBundleIdentifier else {
                throw OptClickerMigrationError.applicationSwapFailed
            }
        } catch {
            restoreAfterFailedSwap(targetURL: sourceURL, temporaryURL: temporaryURL, backupURL: backupURL)
            failMigration(error)
            return
        }

        UserDefaults.standard.set(stagingURL.path, forKey: OptClickerIdentity.migrationCleanupStagedPathKey)
        if let backupURL = self.backupURL {
            UserDefaults.standard.set(backupURL.path, forKey: OptClickerIdentity.migrationCleanupBackupPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: OptClickerIdentity.migrationCleanupBackupPathKey)
        }
        UserDefaults.standard.synchronize()
        launchAttempts = 0
        launchCanonicalApplication(at: sourceURL)
    }

    private func launchCanonicalApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        UserDefaults.standard.removeObject(forKey: OptClickerIdentity.migrationLaunchAcknowledgedKey)
        UserDefaults.standard.synchronize()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.failMigration(error) } }
            else { DispatchQueue.main.async { self?.waitForCanonicalApplication(at: url) } }
        }
    }

    private func waitForCanonicalApplication(at url: URL) {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == OptClickerIdentity.currentBundleIdentifier
                && $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }
        if isRunning && UserDefaults.standard.bool(forKey: OptClickerIdentity.migrationLaunchAcknowledgedKey) {
            completeMigration()
            return
        }
        guard launchAttempts < 40 else {
            failMigration(OptClickerMigrationError.applicationLaunchFailed)
            return
        }
        launchAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.waitForCanonicalApplication(at: url) }
    }

    private func completeMigration() {
        print("OptClicker IdentityMigration: migration completed")
        NSApp.terminate(nil)
    }

    private func failMigration(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OptClicker migration failed"
        alert.informativeText = "\(error.localizedDescription) The legacy application was left available."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func restoreAfterFailedSwap(targetURL: URL, temporaryURL: URL, backupURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path), bundleIdentifier(at: targetURL) == OptClickerIdentity.currentBundleIdentifier {
            try? fileManager.removeItem(at: targetURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) { try? fileManager.moveItem(at: backupURL, to: targetURL) }
        if fileManager.fileExists(atPath: temporaryURL.path) { try? fileManager.removeItem(at: temporaryURL) }
    }

    private func bundleIdentifier(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    private func isRunning(_ application: NSRunningApplication) -> Bool {
        let pid = application.processIdentifier
        return pid > 0 && (Darwin.kill(pid, 0) == 0 || errno == EPERM)
    }

    private func isVerifiedLegacyApplication(_ application: NSRunningApplication, sourceURL: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains { runningApplication in
            guard runningApplication.processIdentifier == application.processIdentifier,
                  runningApplication.bundleIdentifier == OptClickerIdentity.legacyBundleIdentifier else { return false }
            return runningApplication.bundleURL?.standardizedFileURL == sourceURL || runningApplication.bundleURL == nil
        }
    }
}
