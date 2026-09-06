import ApplicationServices
import AppKit
import Foundation
import Combine

final class OptClickerDiagnosticLog {
    static let shared = OptClickerDiagnosticLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "dev.mqiu.OptClicker.diagnostics")

    private init() {
        let logsDirectory = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        fileURL = logsDirectory.appendingPathComponent("OptClicker.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        log("=== OptClicker diagnostic session started ===")
        log("bundle=\(Bundle.main.bundleIdentifier ?? "<nil>") pid=\(ProcessInfo.processInfo.processIdentifier)")
        log("executable=\(Bundle.main.executablePath ?? "<nil>")")
    }

    func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        print("OptClicker: \(message)")
        queue.async { [fileURL] in
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isPostEventGranted: Bool = false
    @Published var automationPermissions: [String: Bool] = [:] // bundleId: isGranted
    
    private let knownBrowsersKey = "PermissionManager.KnownBrowsers"
    private let authorizedBrowsersKey = "PermissionManager.AuthorizedBrowsers"
    @Published var knownBrowsers: [String: String] = [:] // bundleId: appName
    @Published var authorizedBrowsers: Set<String> = []

    // Token for the block-based observer — required for proper cleanup.
    private var becomeActiveObserver: NSObjectProtocol?
    private var automationRefreshGeneration = 0

    private init() {
        let savedKnown = UserDefaults.standard.dictionary(forKey: knownBrowsersKey) as? [String: String] ?? [:]
        self.knownBrowsers = savedKnown
        
        let savedAuthorized = UserDefaults.standard.stringArray(forKey: authorizedBrowsersKey) ?? []
        self.authorizedBrowsers = Set(savedAuthorized)
        
        OptClickerDiagnosticLog.shared.log(
            "PermissionManager init. Known: \(savedKnown.count), Authorized: \(savedAuthorized.count)"
        )

        // Both checks are local and should be available as soon as the manager
        // exists. Accessibility trust alone is not sufficient for OptClicker:
        // synthetic mouse events use the separate Post Event TCC permission.
        checkPermissions()
        refreshAutomationPermissions()

        // Re-verify permissions when the application returns to the foreground.
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkPermissions()
            self?.refreshAutomationPermissions()
        }
    }

    deinit {
        if let observer = becomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func checkPermissions() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        self.isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        self.isPostEventGranted = CGPreflightPostEventAccess()
        OptClickerDiagnosticLog.shared.log(
            "Permission check: accessibility=\(self.isAccessibilityGranted) postEvent=\(self.isPostEventGranted)"
        )
    }

    func refreshAutomationPermissions() {
        automationRefreshGeneration += 1
        let generation = automationRefreshGeneration
        let knownBrowsers = self.knownBrowsers
        let previouslyAuthorized = self.authorizedBrowsers

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var statuses: [String: Bool] = [:]
            var updatedAuthorized = previouslyAuthorized.intersection(Set(knownBrowsers.keys))

            for bundleId in knownBrowsers.keys {
                // A closed app cannot be checked without producing procNotFound.
                // Preserve its remembered status until it is running again.
                let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
                if isRunning {
                    let isGranted = Self.automationPermissionStatus(
                        for: bundleId,
                        askUserIfNeeded: false
                    ) == noErr
                    statuses[bundleId] = isGranted
                    if isGranted {
                        updatedAuthorized.insert(bundleId)
                    } else {
                        // Remove permissions revoked in System Settings instead
                        // of trusting the persisted authorization cache.
                        updatedAuthorized.remove(bundleId)
                    }
                } else {
                    statuses[bundleId] = updatedAuthorized.contains(bundleId)
                }
            }

            DispatchQueue.main.async {
                guard let self,
                      self.automationRefreshGeneration == generation else { return }

                self.authorizedBrowsers = updatedAuthorized

                UserDefaults.standard.set(
                    Array(updatedAuthorized),
                    forKey: self.authorizedBrowsersKey
                )
                self.automationPermissions = statuses
            }
        }
    }
    
    func addBrowser(bundleId: String, name: String) {
        knownBrowsers[bundleId] = name
        UserDefaults.standard.set(knownBrowsers, forKey: knownBrowsersKey)
        refreshAutomationPermissions()
    }
    
    func removeBrowser(bundleId: String) {
        knownBrowsers.removeValue(forKey: bundleId)
        authorizedBrowsers.remove(bundleId)
        
        UserDefaults.standard.set(knownBrowsers, forKey: knownBrowsersKey)
        UserDefaults.standard.set(Array(authorizedBrowsers), forKey: authorizedBrowsersKey)
        
        refreshAutomationPermissions()
    }

    func markAutomationPermissionRevoked(for bundleId: String) {
        guard knownBrowsers[bundleId] != nil else { return }

        let authorizationChanged = authorizedBrowsers.remove(bundleId) != nil
        let statusChanged = automationPermissions[bundleId] != false

        if authorizationChanged {
            UserDefaults.standard.set(Array(authorizedBrowsers), forKey: authorizedBrowsersKey)
        }
        if statusChanged {
            automationPermissions[bundleId] = false
        }
    }

    func isAutomationGranted(for bundleId: String) -> Bool {
        Self.automationPermissionStatus(for: bundleId, askUserIfNeeded: false) == noErr
    }

    private static func automationPermissionStatus(
        for bundleId: String,
        askUserIfNeeded: Bool
    ) -> OSStatus? {
        // AEDeterminePermissionToAutomateTarget requires a live target process.
        // Calling it for an installed-but-closed browser makes macOS emit a
        // procNotFound diagnostic during app launch. A closed browser cannot
        // be authorized or queried yet, so report it as unavailable instead.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else {
            return nil
        }

        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let aeDesc = targetDesc.aeDesc else { return nil }
        return AEDeterminePermissionToAutomateTarget(
            aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
    }

    func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        isPostEventGranted = CGRequestPostEventAccess()
        OptClickerDiagnosticLog.shared.log(
            "Input permissions requested. accessibility=\(isAccessibilityGranted) postEvent=\(isPostEventGranted)"
        )
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func requestAutomationPermission(for bundleId: String) {
        // Execute a harmless AppleScript command to trigger macOS's actual
        // Automation consent flow. Use the bundle identifier so Launch
        // Services never needs to resolve the target by display name.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scriptSource = "tell application id \"\(bundleId)\" to return name"
            var error: NSDictionary?
            let requestSucceeded: Bool
            if let script = NSAppleScript(source: scriptSource) {
                _ = script.executeAndReturnError(&error)
                requestSucceeded = error == nil
            } else {
                requestSucceeded = false
            }

            if let error {
                print("OptClicker: Automation request failed for \(bundleId): \(error)")
            }

            DispatchQueue.main.async {
                guard let self else { return }

                if requestSucceeded {
                    self.authorizedBrowsers.insert(bundleId)
                    self.automationPermissions[bundleId] = true
                    UserDefaults.standard.set(
                        Array(self.authorizedBrowsers),
                        forKey: self.authorizedBrowsersKey
                    )
                } else {
                    self.openSystemSettings(type: "Privacy_Automation")
                }

                self.refreshAutomationPermissions()
            }
        }
    }

    func openSystemSettings(type: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)") {
            NSWorkspace.shared.open(url)
        }
    }
}
