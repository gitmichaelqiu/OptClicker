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

    private init() {
        let savedKnown = UserDefaults.standard.dictionary(forKey: knownBrowsersKey) as? [String: String] ?? [:]
        self.knownBrowsers = savedKnown
        
        let savedAuthorized = UserDefaults.standard.stringArray(forKey: authorizedBrowsersKey) ?? []
        self.authorizedBrowsers = Set(savedAuthorized)
        
        print("OptClicker: PermissionManager init. Known: \(savedKnown.count), Authorized: \(savedAuthorized.count)")
        
        checkPermissions()
        // Re-verify permissions when the application returns to the foreground.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkPermissions()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func checkPermissions() {
        // Accessibility check.
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        self.isAccessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)

        // Automation checks.
        var statuses: [String: Bool] = [:]
        for bundleId in knownBrowsers.keys {
            let isGranted = isAutomationGranted(for: bundleId)
            statuses[bundleId] = isGranted
            if isGranted {
                authorizedBrowsers.insert(bundleId)
            }
        }
        
        // Persist authorized browsers
        UserDefaults.standard.set(Array(authorizedBrowsers), forKey: authorizedBrowsersKey)
        self.automationPermissions = statuses
    }
    
    func addBrowser(bundleId: String, name: String) {
        knownBrowsers[bundleId] = name
        UserDefaults.standard.set(knownBrowsers, forKey: knownBrowsersKey)
        checkPermissions()
    }
    
    func removeBrowser(bundleId: String) {
        knownBrowsers.removeValue(forKey: bundleId)
        authorizedBrowsers.remove(bundleId)
        
        UserDefaults.standard.set(knownBrowsers, forKey: knownBrowsersKey)
        UserDefaults.standard.set(Array(authorizedBrowsers), forKey: authorizedBrowsersKey)
        
        checkPermissions()
    }

    func isAutomationGranted(for bundleId: String) -> Bool {
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        guard let aeDesc = targetDesc.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(aeDesc, typeWildCard, typeWildCard, false)
        return status == noErr
    }

    func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(axOptions)
        openSystemSettings(type: "Privacy_Accessibility")
    }

    func requestAutomationPermission(for bundleId: String, appName: String) {
        // Attempt to trigger the prompt via a simple AppleScript execution.
        let scriptSource: String
        if bundleId == "com.apple.Safari" {
            scriptSource = "tell application \"Safari\" to return name of front document"
        } else {
            scriptSource = "tell application \"\(appName)\" to return URL of active tab of front window"
        }
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }

        // Check again after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkPermissions()
        }
        
        // Fallback to opening system settings if still not granted
        if !isAutomationGranted(for: bundleId) {
            openSystemSettings(type: "Privacy_Automation")
        }
    }

    func openSystemSettings(type: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(type)") {
            NSWorkspace.shared.open(url)
        }
    }
}
