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
    private static let legacyBundleIdentifier = "michaelqiu.OptClicker"
    private static let defaultsMigrationKey = "OptClicker.DidMigrateLegacyDefaults"

    // Auto toggle properties
    static let autoToggleEnabledKey = "isAutoToggleEnabled"
    static let showStatusReasonKey = "showStatusReason"
    static let showFrontmostProcKey = "showFrontmostProcessName"
    static let menuBarIconVisibleKey = "isMenuBarIconVisible"
    static let hudToastModeEnabledKey = "isHUDToastModeEnabled"

    @Published var isMenuBarIconVisible: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarIconVisible, forKey: Self.menuBarIconVisibleKey)
        }
    }

    @Published var isHUDToastModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHUDToastModeEnabled, forKey: Self.hudToastModeEnabledKey)
        }
    }

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
    var statusToastReason: String = ""
    
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
                if isEnabled {
                    statusReason = NSLocalizedString(
                        "Enabled manually",
                        comment: "Reason shown when the user manually enables OptClicker"
                    )
                    statusToastReason = statusReason
                } else {
                    statusReason = NSLocalizedString(
                        "Disabled manually",
                        comment: "Reason shown when the user manually disables OptClicker"
                    )
                    statusToastReason = statusReason
                }
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
        Self.migrateLegacyDefaultsIfNeeded()

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
        
        isMenuBarIconVisible = UserDefaults.standard.object(forKey: Self.menuBarIconVisibleKey) as? Bool ?? true
        isHUDToastModeEnabled = UserDefaults.standard.bool(forKey: Self.hudToastModeEnabledKey)
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

    private static func migrateLegacyDefaultsIfNeeded() {
        let currentDefaults = UserDefaults.standard
        guard !currentDefaults.bool(forKey: defaultsMigrationKey) else { return }

        let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier)
        let keys = [
            menuBarIconVisibleKey,
            hudToastModeEnabledKey,
            autoToggleEnabledKey,
            showStatusReasonKey,
            showFrontmostProcKey,
            isBasedOnAppsKey,
            isBasedOnSpacesKey,
            matchConditionKey,
            launchBehaviorKey,
            lastStateKey,
            "AutoToggleAppBundleIds",
            "AutoToggleBehavior",
            "autoToggleSpaces",
            "HotkeyManager.Shortcut.ToggleApp",
            "HotkeyManager.Shortcut.ToggleAutoToggle",
            "AutoToggle.isExpanded",
            "AutoToggle.Spaces.isExpanded"
        ]

        for key in keys where currentDefaults.object(forKey: key) == nil {
            if let value = legacyDefaults?.object(forKey: key) {
                currentDefaults.set(value, forKey: key)
            }
        }

        currentDefaults.set(true, forKey: defaultsMigrationKey)
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
    private var inputPermissionCancellable: AnyCancellable?
    private func startPermissionMonitor() {
        permissionCancellable = PermissionManager.shared.$authorizedBrowsers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateRefreshTimerState()
            }

        inputPermissionCancellable = Publishers.CombineLatest(
            PermissionManager.shared.$isAccessibilityGranted,
            PermissionManager.shared.$isPostEventGranted
        )
            .removeDuplicates { lhs, rhs in lhs == rhs }
            .receive(on: RunLoop.main)
            .sink { [weak self] accessibilityGranted, postEventGranted in
                guard let self, self.isEnabled else { return }

                if accessibilityGranted && postEventGranted {
                    self.startMonitoring()
                } else {
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
    
    private func matchingAppNames() -> [String] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        if app.bundleIdentifier == selfBundleID { return [] }
        
        let rules = autoToggleAppBundleIds
        if rules.isEmpty { return [] }
        
        let procName = getFrontmostProcessName()
        lazy var currentURL: String? = getFrontmostBrowserURL()
        var matchedNames: [String] = []

        func appendMatch(_ name: String?) {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  !matchedNames.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return }
            matchedNames.append(name)
        }

        if let bundleId = app.bundleIdentifier, rules.contains(bundleId) {
            appendMatch(app.localizedName ?? procName ?? bundleId)
        }
        
        for rule in rules {
            if rule.hasPrefix("proc:") {
                let expected = String(rule.dropFirst(5))
                if let procName = procName, !expected.isEmpty && procName.lowercased() == expected.lowercased() {
                    appendMatch(expected)
                }
            } else if rule.hasPrefix("proc~") {
                let substring = String(rule.dropFirst(5))
                if let procName = procName, !substring.isEmpty && procName.lowercased().contains(substring.lowercased()) {
                    appendMatch(substring)
                }
            } else if rule.hasPrefix("web:") {
                let pattern = String(rule.dropFirst(4))
                if let url = currentURL?.lowercased(), !pattern.isEmpty && url.contains(pattern.lowercased()) {
                    appendMatch(pattern)
                }
            }
        }
        return matchedNames
    }

    private func matchingSpaceNames() -> [String]? {
        let rules = UserDefaults.standard.stringArray(forKey: "autoToggleSpaces") ?? []
        if rules.isEmpty {
            let currentName = SpaceManager.shared.currentSpaceName
            let name = currentName == "Unknown" || currentName == "Disconnected"
                ? NSLocalizedString("All spaces", comment: "")
                : currentName
            return [name]
        }
        
        guard SpaceManager.shared.isAPIEnabled, let currentSpaceID = SpaceManager.shared.currentSpaceID else {
            // If we don't know the space or API is off, we assume it's NOT a match unless rules are empty
            return nil
        }
        
        if rules.contains(currentSpaceID) {
            let name = SpaceManager.shared.availableSpaces.first { $0.id == currentSpaceID }?.name
                ?? SpaceManager.shared.currentSpaceName
            return [name == "Unknown" ? currentSpaceID : name]
        }
        
        // Check Fullscreen
        if rules.contains("fullscreen") {
            // Fullscreen apps are in their own Space.
            // If currentSpaceID is NOT in availableSpaces, it's likely a fullscreen app space.
            let isKnownDesktop = SpaceManager.shared.availableSpaces.contains { $0.id == currentSpaceID }
            if !isKnownDesktop {
                return [NSLocalizedString("Fullscreen", comment: "")]
            }
        }
        
        return nil
    }

    func getIsMatch() -> (Bool, String) {
        let appMatches = isBasedOnApps ? matchingAppNames() : nil
        let spaceMatches = isBasedOnSpaces ? matchingSpaceNames() : nil
        let appMatch = appMatches.map { !$0.isEmpty }
        let spaceMatch: Bool? = isBasedOnSpaces ? (spaceMatches != nil) : nil
        
        if let am = appMatch, let sm = spaceMatch {
            let isMatch = matchCondition == .and ? am && sm : am || sm
            if isMatch {
                let matchedNames = (am ? appMatches ?? [] : []) + (sm ? spaceMatches ?? [] : [])
                return (true, enabledReason(for: matchedNames))
            }

            let reason: String
            switch (am, sm) {
            case (true, true):
                reason = enabledReason(for: (appMatches ?? []) + (spaceMatches ?? []))
            case (true, false):
                reason = NSLocalizedString("Disabled (app rule matched, space rule did not)", comment: "")
            case (false, true):
                reason = NSLocalizedString("Disabled (space rule matched, app rule did not)", comment: "")
            case (false, false):
                reason = NSLocalizedString("Disabled (neither app nor space rule matched)", comment: "")
            }

            return (isMatch, reason)
        } else if let am = appMatch {
            let reason = am
                ? enabledReason(for: appMatches ?? [])
                : NSLocalizedString("Disabled by app mismatch", comment: "")
            return (am, reason)
        } else if let sm = spaceMatch {
            let reason = sm
                ? enabledReason(for: spaceMatches ?? [])
                : NSLocalizedString("Disabled by space mismatch", comment: "")
            return (sm, reason)
        }
        
        return (false, NSLocalizedString("Disabled (no auto-toggle conditions enabled)", comment: ""))
    }

    private func enabledReason(for matchedNames: [String]) -> String {
        let uniqueNames = matchedNames.reduce(into: [String]()) { names, name in
            if !name.isEmpty,
               !names.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        let targets = uniqueNames.isEmpty
            ? NSLocalizedString("All spaces", comment: "")
            : uniqueNames.joined(separator: ", ")
        return String(
            format: NSLocalizedString("Enabled (%@)", comment: "Enabled because these app, website, or space targets matched"),
            locale: Locale.current,
            arguments: [targets]
        )
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

        isAutoToggling = true
        defer { isAutoToggling = false }

        if isMatch {
            statusReason = reason
            statusToastReason = reason
            if !isEnabled { isEnabled = true }
        } else {
            switch autoToggleBehavior {
            case .disable:
                statusReason = reason
                statusToastReason = NSLocalizedString("OptClicker disabled", comment: "")
                if isEnabled { isEnabled = false }
            case .followLast:
                if lastManualState {
                    statusReason = NSLocalizedString(
                        "Following last setting (enabled)",
                        comment: "Reason shown when auto toggle restores the last enabled state"
                    )
                    statusToastReason = statusReason
                } else {
                    statusReason = NSLocalizedString(
                        "Following last setting (disabled)",
                        comment: "Reason shown when auto toggle restores the last disabled state"
                    )
                    statusToastReason = NSLocalizedString("OptClicker disabled", comment: "")
                }
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
        let loc = NSEvent.mouseLocation
        // Core Graphics uses the primary display's top-left origin. `main`
        // follows the focused window and may be an external display, so use
        // the first screen, which is the display containing the menu bar.
        let primaryDisplayHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: loc.x, y: primaryDisplayHeight - loc.y)
    }

    // Monitor Keyboard
    private func startMonitoring() {
        stopMonitoring() // ensure no duplicate monitors
        guard PermissionManager.shared.isAccessibilityGranted,
              PermissionManager.shared.isPostEventGranted else { return }

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
        isOptionDown = false
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
        guard PermissionManager.shared.isPostEventGranted else {
            return
        }

        let location = getCGMouseLocation()
        let event = CGEvent(mouseEventSource: nil,
                            mouseType: .rightMouseDown,
                            mouseCursorPosition: location,
                            mouseButton: .right)
        event?.post(tap: .cghidEventTap)
    }

    private func simulateRightMouseUp() {
        guard PermissionManager.shared.isPostEventGranted else {
            return
        }

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
