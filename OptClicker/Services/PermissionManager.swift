import ApplicationServices
import AppKit
import Foundation
import Combine

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var isAccessibilityGranted: Bool = false
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
        
        print("OptClicker: PermissionManager init. Known: \(savedKnown.count), Authorized: \(savedAuthorized.count)")

        // Match the mature manager's startup behavior. Accessibility is a
        // local check and should be available as soon as the manager exists.
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
        // Keep this method consistent with DesktopRenamer: it performs the
        // immediate Accessibility check only. Browser Automation checks can
        // contact another process and are refreshed separately off the main
        // thread.
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        self.isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
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
        AXIsProcessTrustedWithOptions(axOptions)
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func requestAutomationPermission(for bundleId: String) {
        // Ask macOS directly instead of executing a potentially blocking
        // AppleScript on the main thread. The target must be running for this
        // API to identify it; otherwise send the user to Automation settings.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = Self.automationPermissionStatus(for: bundleId, askUserIfNeeded: true)

            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshAutomationPermissions()

                if status != noErr {
                    self.openSystemSettings(type: "Privacy_Automation")
                }
            }
        }
    }

    func openSystemSettings(type: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)") {
            NSWorkspace.shared.open(url)
        }
    }
}
