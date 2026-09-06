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
            return NSLocalizedString("Disable OptClicker", comment: "")
        case .followLast:
            return NSLocalizedString("Follow last setting", comment: "")
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
            return NSLocalizedString("Enable OptClicker", comment: "")
        case .disabled:
            return NSLocalizedString("Disable OptClicker", comment: "")
        case .lastState:
            return NSLocalizedString("Follow last setting", comment: "")
        }
    }
}

enum MatchCondition: String, CaseIterable {
    case and = "and"
    case or = "or"

    var localizedDescription: String {
        switch self {
        case .and: return NSLocalizedString("And", comment: "")
        case .or: return NSLocalizedString("Or", comment: "")
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
                updateRefreshTimerState()
            } else {
                stopRefreshTimer()
            }
        }
    }
    
    static let isBasedOnAppsKey = "isBasedOnApps"
    static let isBasedOnSpacesKey = "isBasedOnSpaces"
    static let matchConditionKey = "autoToggleMatchCondition"
    
    @Published var isBasedOnApps: Bool {
        didSet {
            UserDefaults.standard.set(isBasedOnApps, forKey: Self.isBasedOnAppsKey)
            refreshAutoToggleState()
        }
    }
    
    @Published var isBasedOnSpaces: Bool {
        didSet {
            UserDefaults.standard.set(isBasedOnSpaces, forKey: Self.isBasedOnSpacesKey)
            refreshAutoToggleState()
        }
    }
    
    @Published var matchCondition: MatchCondition {
        didSet {
            UserDefaults.standard.set(matchCondition.rawValue, forKey: Self.matchConditionKey)
            refreshAutoToggleState()
        }
    }
    
    @Published var statusReason: String = ""
    
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
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
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
        isBasedOnApps = UserDefaults.standard.object(forKey: Self.isBasedOnAppsKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.isBasedOnAppsKey)
        isBasedOnSpaces = UserDefaults.standard.bool(forKey: Self.isBasedOnSpacesKey)
        
        let matchRaw = UserDefaults.standard.string(forKey: Self.matchConditionKey) ?? MatchCondition.or.rawValue
        matchCondition = MatchCondition(rawValue: matchRaw) ?? .or
        
        lastManualState = isEnabled

        if isEnabled {
            startMonitoring()
        }

        startFrontmostAppMonitor()
        startSpaceMonitor()
        startPermissionMonitor()
        
        if isAutoToggleEnabled {
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

        NotificationCenter.default.addObserver(
            forName: .autoToggleHotkeyTriggered,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggleAutoToggle()
        }
    }

    func toggleAutoToggle() {
        isAutoToggleEnabled.toggle()
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
    
    private var spaceCancellable: AnyCancellable?
    private func startSpaceMonitor() {
        spaceCancellable = SpaceManager.shared.$currentSpaceID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAutoToggleState()
            }
    }

    private var permissionCancellable: AnyCancellable?
    private var accessibilityPermissionCancellable: AnyCancellable?
    private func startPermissionMonitor() {
        permissionCancellable = PermissionManager.shared.$authorizedBrowsers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateRefreshTimerState()
            }

        accessibilityPermissionCancellable = PermissionManager.shared.$isAccessibilityGranted
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isGranted in
                guard let self, self.isEnabled else { return }

                if isGranted {
                    self.startMonitoring()
                } else {
                    self.isOptionDown = false
                    self.stopMonitoring()
                }
            }
    }

    private func updateRefreshTimerState() {
        guard isAutoToggleEnabled else {
            stopRefreshTimer()
            return
        }

        // We only need the refresh timer if:
        // 1. Based on Apps is enabled
        // 2. There is at least one website rule (web:...)
        // 3. The frontmost application is a supported browser
        let hasWebsiteRule = autoToggleAppBundleIds.contains { $0.hasPrefix("web:") }

        if isBasedOnApps,
           hasWebsiteRule,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmost.bundleIdentifier,
           PermissionManager.shared.authorizedBrowsers.contains(bundleId) {
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

        // Only send Apple Events to browsers the user has explicitly added
        // and authorized. Sending a `tell application` command to any
        // frontmost app makes macOS try to resolve that app as an AppleScript
        // target, which can open the "Choose Application" panel when its
        // display name is not a registered script target.
        guard PermissionManager.shared.knownBrowsers[bundleId] != nil else {
            return nil
        }

        // PermissionManager refreshes this status asynchronously so the TCC
        // query never blocks the main thread. Do not send an Apple Event until
        // that latest check confirms access.
        guard PermissionManager.shared.authorizedBrowsers.contains(bundleId),
              PermissionManager.shared.automationPermissions[bundleId] == true else {
            return nil
        }

        let scriptSource: String
        if bundleId == "com.apple.Safari" {
            scriptSource = "tell application id \"\(bundleId)\" to return URL of front document"
        } else {
            scriptSource = "tell application id \"\(bundleId)\" to return URL of active tab of front window"
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
    
    func getIsAppMatch() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if app.bundleIdentifier == selfBundleID { return false }
        
        let rules = autoToggleAppBundleIds
        if rules.isEmpty { return false }
        
        if let bundleId = app.bundleIdentifier, rules.contains(bundleId) {
            return true
        }
        
        let procName = getFrontmostProcessName()
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

    func getIsSpaceMatch() -> Bool {
        let rules = UserDefaults.standard.stringArray(forKey: "autoToggleSpaces") ?? []
        if rules.isEmpty { return true } // Default to all spaces if list is empty
        
        guard SpaceManager.shared.isAPIEnabled, let currentSpaceID = SpaceManager.shared.currentSpaceID else {
            // If we don't know the space or API is off, we assume it's NOT a match unless rules are empty
            return false
        }
        
        if rules.contains(currentSpaceID) { return true }
        
        // Check Fullscreen
        if rules.contains("fullscreen") {
            // Fullscreen apps are in their own Space.
            // If currentSpaceID is NOT in availableSpaces, it's likely a fullscreen app space.
            let isKnownDesktop = SpaceManager.shared.availableSpaces.contains { $0.id == currentSpaceID }
            if !isKnownDesktop {
                return true
            }
        }
        
        return false
    }

    func getIsMatch() -> (Bool, String) {
        let appMatch = isBasedOnApps ? getIsAppMatch() : nil
        let spaceMatch = isBasedOnSpaces ? getIsSpaceMatch() : nil
        
        if let am = appMatch, let sm = spaceMatch {
            if matchCondition == .and {
                let result = am && sm
                let reason = result ? NSLocalizedString("Enabled by both apps and spaces", comment: "") : NSLocalizedString("Disabled (does not match both conditions)", comment: "")
                return (result, reason)
            } else {
                let result = am || sm
                let reason = result ? NSLocalizedString("Enabled by app or space match", comment: "") : NSLocalizedString("Disabled (no app or space match)", comment: "")
                return (result, reason)
            }
        } else if let am = appMatch {
            let reason = am ? NSLocalizedString("Enabled by app match", comment: "") : NSLocalizedString("Disabled by app mismatch", comment: "")
            return (am, reason)
        } else if let sm = spaceMatch {
            let reason = sm ? NSLocalizedString("Enabled by space match", comment: "") : NSLocalizedString("Disabled by space mismatch", comment: "")
            return (sm, reason)
        }
        
        return (false, NSLocalizedString("Disabled (no auto-toggle conditions enabled)", comment: ""))
    }

    private func handleFrontmostAppChange(notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier != selfBundleID,
           let proc = getFrontmostProcessName() {
            lastNonSelfProcessName = proc
        }

        objectWillChange.send()

        guard isAutoToggleEnabled else {
            self.statusReason = NSLocalizedString("Auto-toggle is disabled", comment: "")
            return
        }

        let (isMatch, reason) = getIsMatch()
        self.statusReason = reason

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
        updateRefreshTimerState()
    }
    
    private func getCGMouseLocation() -> CGPoint {
        // CGEvent already reports the cursor in the coordinate system needed
        // for posting HID events. Using NSEvent.mouseLocation plus the main
        // display height breaks when the pointer is on another display.
        return CGEvent(source: nil)?.location ?? .zero
    }

    // Monitor Keyboard
    private func startMonitoring() {
        stopMonitoring() // ensure no duplicate monitors
        PermissionManager.shared.checkPermissions()

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let inputManager = Unmanaged<InputManager>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = inputManager.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                } else if type == .flagsChanged {
                    inputManager.handleFlagsChanged(event: event)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )

        if let eventTap {
            eventTapRunLoopSource = CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault,
                eventTap,
                0
            )
            if let eventTapRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }

        // Keep the AppKit path as a fallback for environments where a session
        // event tap cannot be created even though the app is foregrounded.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
            return event
        }

        print("OptClicker: Unable to install the session event tap; using AppKit modifier monitors.")
    }

    private func stopMonitoring() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        isOptionDown = false
    }

    private var isOptionDown = false

    private func handleFlagsChanged(event: NSEvent) {
        handleOptionState(isPressed: event.modifierFlags.contains(.option))
    }

    private func handleFlagsChanged(event: CGEvent) {
        handleOptionState(isPressed: event.flags.contains(.maskAlternate))
    }

    private func handleOptionState(isPressed optionPressed: Bool) {

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
