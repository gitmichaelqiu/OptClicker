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
    @Published var isAutoToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoToggleEnabled, forKey: Self.autoToggleEnabledKey)
            if isAutoToggleEnabled {
                // Re-evaluate current frontmost app
                refreshAutoToggleState()
            }
        }
    }
    
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
    }

    private func startFrontmostAppMonitor() {
        // Use NSWorkspace notification for frontmost app change
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleFrontmostAppChange(notification: notification)
        }
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

    private func handleFrontmostAppChange(notification: Notification) {
        guard self.isAutoToggleEnabled else { return }
        
        let rules = autoToggleAppBundleIds
        guard !rules.isEmpty else { return }

        var isMatch = false

        // 1. Bundle ID
        if let userInfo = notification.userInfo,
           let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bundleId = app.bundleIdentifier,
           rules.contains(bundleId) {
            isMatch = true
        }

        // 2. Process name
        if !isMatch {
            if let procName = getFrontmostProcessName() {
                for rule in rules {
                    if rule.hasPrefix("proc:") {
                        let expected = String(rule.dropFirst(5))
                        if procName.lowercased() == expected.lowercased() {
                            isMatch = true
                            break
                        }
                    }
                }
            }
        }

        if isMatch {
            isAutoToggling = true
            if !isEnabled { isEnabled = true }
            isAutoToggling = false
        } else {
            isAutoToggling = true
            switch autoToggleBehavior {
            case .disable:
                if isEnabled { isEnabled = false }
            case .followLast:
                if isEnabled != lastManualState {
                    isEnabled = lastManualState
                }
            }
            isAutoToggling = false
        }
        
        objectWillChange.send()
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
        let isDuplicate = rules.contains { rule in
            rule.hasPrefix("proc:") && rule.lowercased() == newRule.lowercased()
        }
        return isDuplicate
    }
}
