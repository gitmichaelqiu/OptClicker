import ApplicationServices
import AppKit
import Foundation
import Combine

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
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func requestAutomationPermission(for bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            openSystemSettings(type: "Privacy_Automation")
            return
        }

        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
                guard error == nil else {
                    DispatchQueue.main.async {
                        self?.openSystemSettings(type: "Privacy_Automation")
                    }
                    return
                }

                self?.requestAutomationPermission(for: bundleId)
            }
            return
        }

        // The consent prompt must be triggered with a real Apple Event target.
        // Run this off the main thread because macOS blocks the calling thread
        // while the user responds to the prompt.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = Self.automationPermissionStatus(for: bundleId, askUserIfNeeded: true)

            DispatchQueue.main.async {
                guard let self else { return }

                if status == noErr {
                    self.authorizedBrowsers.insert(bundleId)
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
