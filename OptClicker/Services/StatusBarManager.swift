import AppKit
import Combine

class StatusBarManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    private let inputManager: InputManager
    private let toggleHandler: () -> Void
    
    private var statusItem: NSStatusItem?
    private var cachedEnabledIcon: NSImage?
    private var cachedDisabledIcon: NSImage?
    private let iconSize = NSSize(width: 15, height: 15)
    
    init(inputManager: InputManager, onToggle: @escaping () -> Void) {
        self.inputManager = inputManager
        self.toggleHandler = onToggle
        
        // Observe InputManager to auto-refresh
        inputManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }
    
    func install() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = makeOptionIcon()
            button.target = self
            button.action = #selector(handleStatusItemClick)
        }
        
        refresh()
    }
    
    func uninstall() {
        statusItem = nil
    }
    
    func refresh() {
        updateIcon()
        updateMenu()
    }
    
    @objc private func handleStatusItemClick() {
        toggleHandler()
    }
    
    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let icon: NSImage
        if inputManager.isEnabled {
            icon = cachedEnabledIcon ?? makeOptionIcon()
            cachedEnabledIcon = icon
        } else {
            icon = cachedDisabledIcon ?? makeOptionWithSlashIcon()
            cachedDisabledIcon = icon
        }
        button.image = icon
    }
    
    private func updateMenu() {
        statusItem?.menu = buildMenu()
    }
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Toggle item
        let toggleItem = NSMenuItem(
            title: NSLocalizedString("Menu.Toggle", comment: "Option → Right Click"),
            action: #selector(handleToggleItemClick),
            keyEquivalent: ""
        )
        toggleItem.image = NSImage(systemSymbolName: "pointer.arrow.rays", accessibilityDescription: nil)
        toggleItem.target = self
        toggleItem.state = inputManager.isEnabled ? .on : .off
        menu.addItem(toggleItem)

        // Status reason (non-clickable)
        if let statusReason = getStatusReason() {
            let item = NSMenuItem(title: statusReason, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        
        let showProc = UserDefaults.standard.bool(forKey: InputManager.showFrontmostProcKey)
        if showProc {
            if let procName = inputManager.getFrontmostProcessNameExcludingSelf() {
                let title = String(
                    format: NSLocalizedString("Menu.Proc", comment: ""),
                    procName
                )
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        
        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("Menu.Settings", comment: "Settings"),
            action: #selector(handleSettingsItemClick),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: NSLocalizedString("Menu.Quit", comment: "Quit"),
            action: #selector(handleQuitItemClick),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func handleToggleItemClick() {
        toggleHandler()
    }
    
    @objc private func handleSettingsItemClick() {
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
    }
    
    @objc private func handleQuitItemClick() {
        NSApp.terminate(self)
    }
    
    private func makeOptionIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "option", accessibilityDescription: "Option")!
        let resized = resizeImage(image, to: iconSize)
        resized.isTemplate = true
        return resized
    }

    private func makeOptionWithSlashIcon() -> NSImage {
        let padding: CGFloat = 3
        let combinedImage = NSImage(size: iconSize)
        combinedImage.lockFocus()

        if let optionImage = NSImage(systemSymbolName: "option", accessibilityDescription: "option") {
            let resizedOption = resizeImage(optionImage, to: iconSize)
            resizedOption.draw(in: NSRect(origin: .zero, size: iconSize))
        }
        
        // Erase path
        let erasePath = NSBezierPath()
        erasePath.move(to: NSPoint(x: padding, y: padding))
        erasePath.line(to: NSPoint(x: iconSize.width - padding, y: iconSize.height - padding))
        erasePath.lineWidth = 4.0
        erasePath.lineCapStyle = .round
        
        if let context = NSGraphicsContext.current {
            let originalOp = context.compositingOperation
            context.compositingOperation = .destinationOut
            NSColor.white.set()
            erasePath.stroke()
            context.compositingOperation = originalOp
        }
        
        // Draw slash
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 2, y: 1))
        path.line(to: NSPoint(x: iconSize.width - 2, y: iconSize.height - 1))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.stroke()

        combinedImage.unlockFocus()
        combinedImage.isTemplate = true
        return combinedImage
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        scaled.unlockFocus()
        return scaled
    }
    
    private func getStatusReason() -> String? {
        let show = UserDefaults.standard.bool(forKey: InputManager.showStatusReasonKey)
        guard show else { return nil }
        
        let state = inputManager.isEnabled
        let stateStr = state
            ? NSLocalizedString("Menu.Reason.StateStr.Enabled", comment: "Enabled")
            : NSLocalizedString("Menu.Reason.StateStr.Disabled", comment: "Disabled")
        
        let autoToggleAppBundleIds = UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
        if autoToggleAppBundleIds.isEmpty {
            return String(format: NSLocalizedString("Menu.Reason.Manual", comment: "Manual setting"), stateStr)
        }
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return String(format: NSLocalizedString("Menu.Reason.Unknown", comment: ""), stateStr)
        }
        
        let appName = frontmostApp.localizedName ?? bundleId
        
        let isMatch = inputManager.getIsMatch()
        let matchedProcName: String? = {
            guard let procName = inputManager.getFrontmostProcessName() else { return nil }
            for rule in autoToggleAppBundleIds {
                if rule.hasPrefix("proc:") || rule.hasPrefix("proc~") {
                    let kw = String(rule.dropFirst(5))
                    if !kw.isEmpty && procName.lowercased().contains(kw.lowercased()) {
                        var ret = kw
                        if rule.hasPrefix("proc~") {
                            ret = procName + " (\(kw))"
                        }
                        return ret
                    }
                }
            }
            return nil
        }()
        
        let autoToggleEnabled = inputManager.isAutoToggleEnabled
        if autoToggleEnabled {
            let behavior = AutoToggleBehavior(
                rawValue: UserDefaults.standard.string(forKey: "AutoToggleBehavior") ?? "disable"
            ) ?? .disable
            let lastState = UserDefaults.standard.bool(forKey: InputManager.lastStateKey)
            
            if isMatch {
                let displayName = matchedProcName.map {
                        String(format: NSLocalizedString("Menu.Reason.Process", comment: ""), $0)
                    } ?? appName
                
                if state {
                    return String(format: NSLocalizedString("Menu.Reason.IsFrontmost", comment: ""), stateStr, displayName)
                } else {
                    return String(format: NSLocalizedString("Menu.Reason.TmpManual", comment: ""), stateStr)
                }
            } else {
                if state {
                    if behavior == .followLast {
                        if state == lastState {
                            return String(format: NSLocalizedString("Menu.Reason.FollowLast", comment: ""), stateStr)
                        } else {
                            return String(format: NSLocalizedString("Menu.Reason.TmpManual", comment: ""), stateStr)
                        }
                    } else if behavior == .disable {
                        return String(format: NSLocalizedString("Menu.Reason.TmpManual", comment: ""), stateStr)
                    }
                } else {
                    if behavior == .followLast {
                        if state == lastState {
                            return String(format: NSLocalizedString("Menu.Reason.FollowLast", comment: ""), stateStr)
                        } else {
                            return String(format: NSLocalizedString("Menu.Reason.TmpManual", comment: ""), stateStr)
                        }
                    } else if behavior == .disable {
                        return String(format: NSLocalizedString("Menu.Reason.NoFrontmost", comment: ""), stateStr)
                    }
                }
            }
        }
        
        return String(format: NSLocalizedString("Menu.Reason.Manual", comment: ""), stateStr)
    }
}

extension Notification.Name {
    static let openSettingsWindow = Notification.Name("OpenSettingsWindow")
}
