import Foundation
import AppKit
import Combine
import ApplicationServices
import Darwin

enum AutoToggleBehavior: String, CaseIterable {
    case disable = "disable"
    case followLast = "followLast"

    var localizedDescription: String {
        switch self {
        case .disable:
            return NSLocalizedString("Settings.General.AutoToggle.NotFrontmost.Disable", comment: "Disable")
        case .followLast:
            return NSLocalizedString("Settings.General.AutoToggle.NotFrontmost.FollowLast", comment: "Follow last setting")
        }
    }
}

enum LaunchBehavior: String, CaseIterable {
    case enabled = "enabled"
    case disabled = "disabled"
    case lastState = "lastState"

    var localizedDescription: String {
        switch self {
        case .enabled:
            return NSLocalizedString("Settings.General.LaunchBehavior.Enabled", comment: "Enabled")
        case .disabled:
            return NSLocalizedString("Settings.General.LaunchBehavior.Disabled", comment: "Disabled")
        case .lastState:
            return NSLocalizedString("Settings.General.LaunchBehavior.LastState", comment: "Last State")
        }
    }
}

class InputManager: ObservableObject {
    // Auto toggle properties
    static let autoToggleEnabledKey = "isAutoToggleEnabled"
    static let showStatusReasonKey = "showStatusReason"
    static let showFrontmostProcKey = "showFrontmostProcessName"
    @Published var isAutoToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoToggleEnabled, forKey: Self.autoToggleEnabledKey)
            if isAutoToggleEnabled {
                // Re-evaluate current frontmost app
                refreshAutoToggleState()
                startRefreshTimer()
            } else {
                stopRefreshTimer()
            }
        }
    }
    
    private var refreshTimer: Timer?
    private var frontmostAppMonitor: Any?
    private var lastManualState: Bool = false
    private var autoToggleAppBundleIds: [String] {
        UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
    }
    private var autoToggleBehavior: AutoToggleBehavior {
        let raw = UserDefaults.standard.string(forKey: "AutoToggleBehavior") ?? AutoToggleBehavior.disable.rawValue
        return AutoToggleBehavior(rawValue: raw) ?? .disable
    }
    @Published var isEnabled: Bool = false {
        didSet {
            if !isAutoToggling {
                lastManualState = isEnabled
            }
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
            UserDefaults.standard.set(isEnabled, forKey: Self.lastStateKey)
        }
    }

    public var isAutoToggling = false
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    static let launchBehaviorKey = "LaunchBehavior"
    static let lastStateKey = "LastState"
    
    private var lastNonSelfProcessName: String? = nil
    private let selfBundleID = Bundle.main.bundleIdentifier ?? "michaelqiu.OptClicker"
    
    init() {
        let behaviorString = UserDefaults.standard.string(forKey: Self.launchBehaviorKey) ?? LaunchBehavior.lastState.rawValue
        let launchBehavior = LaunchBehavior(rawValue: behaviorString) ?? .lastState

        switch launchBehavior {
        case .enabled:
            isEnabled = true
        case .disabled:
            isEnabled = false
        case .lastState:
            isEnabled = UserDefaults.standard.bool(forKey: Self.lastStateKey)
        }
        
        isAutoToggleEnabled = UserDefaults.standard.bool(forKey: Self.autoToggleEnabledKey)
        lastManualState = isEnabled

        if isEnabled {
            startMonitoring()
        }

        startFrontmostAppMonitor()
        
        if isAutoToggleEnabled && !autoToggleAppBundleIds.isEmpty {
            refreshAutoToggleState()
        }
        
        // Pre-fill lastNonSelfProcessName at launch
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != selfBundleID,
           let proc = getFrontmostProcessName() {
            lastNonSelfProcessName = proc
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private func startFrontmostAppMonitor() {
        // Auto-toggle
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleFrontmostAppChange(notification: notification)
        }

        // Frontmost proc
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != self?.selfBundleID,
               let procName = self?.getFrontmostProcessName() {
                self?.lastNonSelfProcessName = procName
            }
            
            // Start/Stop timer based on frontmost app
            self?.updateRefreshTimerState()
        }
    }

    private func updateRefreshTimerState() {
        guard isAutoToggleEnabled else {
            stopRefreshTimer()
            return
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmost.bundleIdentifier,
           bundleId != selfBundleID {
            // We'll try to start the timer for any app that isn't ourselves, 
            // and let getFrontmostBrowserURL handle the actual check.
            // This is more generic.
            startRefreshTimer()
        } else {
            stopRefreshTimer()
        }
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAutoToggleState()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func getFrontmostProcessName() -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmost.processIdentifier
        guard pid != 0 else { return nil }

        var nameBuf = [Int8](repeating: 0, count: Int(MAXPATHLEN))
        if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) != -1 {
            return String(cString: nameBuf)
        }
        return nil
    }
    
    func getFrontmostProcessNameExcludingSelf() -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return lastNonSelfProcessName }
        
        if frontmost.bundleIdentifier == selfBundleID {
            return lastNonSelfProcessName
        }

        if let proc = getFrontmostProcessName() {
            lastNonSelfProcessName = proc
            return proc
        }
        return lastNonSelfProcessName
    }

    func getFrontmostBrowserURL() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return nil }

        let scriptSource: String
        if bundleId == "com.apple.Safari" {
            scriptSource = "tell application \"Safari\" to return URL of front document"
        } else {
            let appName = app.localizedName ?? "Google Chrome"
            scriptSource = "tell application \"\(appName)\" to return URL of active tab of front window"
        }

        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            let result = script.executeAndReturnError(&error)
            if let err = error {
                print("OptClicker: AppleScript Error: \(err)")
            }
            if error == nil {
                return result.stringValue
            }
        } else {
            print("OptClicker: Failed to initialize AppleScript with source: \(scriptSource)")
        }
        return nil
    }
    
    func getIsMatch() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        // Skip self
        if app.bundleIdentifier == selfBundleID { return false }
        
        let rules = autoToggleAppBundleIds
        guard !rules.isEmpty else { return false }
        
        // Bundle ID match
        if let bundleId = app.bundleIdentifier, rules.contains(bundleId) {
            return true
        }
        
        // Process name match (exact & partial)
        let procName = getFrontmostProcessName()
        
        // Website match
        lazy var currentURL: String? = getFrontmostBrowserURL()
        
        for rule in rules {
            if rule.hasPrefix("proc:") {
                let expected = String(rule.dropFirst(5))
                if let procName = procName, !expected.isEmpty && procName.lowercased() == expected.lowercased() {
                    return true
                }
            } else if rule.hasPrefix("proc~") {
                let substring = String(rule.dropFirst(5))
                if let procName = procName, !substring.isEmpty && procName.lowercased().contains(substring.lowercased()) {
                    return true
                }
            } else if rule.hasPrefix("web:") {
                let pattern = String(rule.dropFirst(4)).lowercased()
                if let url = currentURL?.lowercased(), !pattern.isEmpty && url.contains(pattern) {
                    return true
                }
            }
        }
        
        return false
    }

    private func handleFrontmostAppChange(notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier != selfBundleID,
           let proc = getFrontmostProcessName() {
            lastNonSelfProcessName = proc
        }

        objectWillChange.send()

        guard isAutoToggleEnabled else { return }

        let isMatch = getIsMatch()

        isAutoToggling = true
        defer { isAutoToggling = false }

        if isMatch {
            if !isEnabled { isEnabled = true }
        } else {
            switch autoToggleBehavior {
            case .disable:
                if isEnabled { isEnabled = false }
            case .followLast:
                if isEnabled != lastManualState {
                    isEnabled = lastManualState
                }
            }
        }
    }
    
    func refreshAutoToggleState() {
        guard self.isAutoToggleEnabled else { return }
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let _ = frontmostApp.bundleIdentifier else { return }
        
        let notification = Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: frontmostApp]
        )
        
        handleFrontmostAppChange(notification: notification)
    }
    
    private func getCGMouseLocation() -> CGPoint {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        return CGPoint(x: loc.x, y: screenHeight - loc.y)
    }

    // Monitor Keyboard
    private func startMonitoring() {
        stopMonitoring() // ensure no duplicate monitors

        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
    }

    private var isOptionDown = false

    private func handleFlagsChanged(event: NSEvent) {
        let optionPressed = event.modifierFlags.contains(.option)

        if optionPressed && !isOptionDown {
            // Key just pressed
            isOptionDown = true
            simulateRightMouseDown()
        } else if !optionPressed && isOptionDown {
            // Key just released
            isOptionDown = false
            simulateRightMouseUp()
        }
    }

    // Mouse Simulation
    private func simulateRightMouseDown() {
        let location = getCGMouseLocation()
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: .rightMouseDown,
                            mouseCursorPosition: location,
                            mouseButton: .right)
        event?.post(tap: .cghidEventTap)
    }

    private func simulateRightMouseUp() {
        let location = getCGMouseLocation()
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: .rightMouseUp,
                            mouseCursorPosition: location,
                            mouseButton: .right)
        event?.post(tap: .cghidEventTap)
    }
    
    static func isRuleDuplicated(newRule: String) -> Bool {
        let rules = UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
        
        let newKey: String
        if newRule.hasPrefix("proc:") || newRule.hasPrefix("proc~") {
            newKey = String(newRule.dropFirst(5)).lowercased()
        } else if newRule.hasPrefix("web:") {
            newKey = String(newRule.dropFirst(4)).lowercased()
        } else {
            newKey = newRule.lowercased()
        }
        
        let isDuplicate = rules.contains { rule in
            let existingKey: String
            if rule.hasPrefix("proc:") || rule.hasPrefix("proc~") {
                existingKey = String(rule.dropFirst(5)).lowercased()
            } else if rule.hasPrefix("web:") {
                existingKey = String(rule.dropFirst(4)).lowercased()
            } else {
                existingKey = rule.lowercased()
            }
            return existingKey == newKey
        }
        return isDuplicate
    }
}
