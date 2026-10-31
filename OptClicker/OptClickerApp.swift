import SwiftUI
import UserNotifications
import Combine
import AppKit


class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var inputManagerCancellable: AnyCancellable?
    
    private(set) var inputManager: InputManager!
    private(set) var hotkeyManager: HotkeyManager!
    var statusBarManager: StatusBarManager?

    @objc func quitApp() {
        NSApp.terminate(self)
    }

    @objc func openSettingsWindow() {
        SettingsWindowController.shared.open(
            inputManager: inputManager,
            hotkeyManager: hotkeyManager
        )
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if OptClickerMigrationFinalizer.shared.startIfRequested() {
            return
        }

        if OptClickerBridgeMigrationManager.shared.beginIfNeeded(completion: { [weak self] in
            self?.startNormalApplication()
        }) {
            return
        }

        startNormalApplication()
    }

    private func startNormalApplication() {
        guard inputManager == nil else { return }
        OptClickerIdentityMigration.prepareNormalLaunch()

        inputManager = InputManager()
        hotkeyManager = HotkeyManager()
        
        // Status bar
        statusBarManager = StatusBarManager(
            inputManager: inputManager,
            onToggle: { [weak self] in
                self?.inputManager.isEnabled.toggle()
            },
            onMenuBarIconVisibilityChanged: { [weak self] isVisible in
                self?.updateActivationPolicy(showMenuBarIcon: isVisible)
            }
        )
        statusBarManager?.install()

        // Observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyTriggered),
            name: .hotkeyTriggered,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: .openSettingsWindow,
            object: nil
        )

        // Sparkle handles auto updates automatically.
    }

    private func updateActivationPolicy(showMenuBarIcon: Bool) {
        // Keep Settings frontmost; its close handler applies the saved policy.
        guard !SettingsWindowController.shared.isSettingsWindowVisible else { return }

        // Apply after launch or the current event has finished so AppKit can
        // update the Dock tile without racing window creation or dismissal.
        DispatchQueue.main.async {
            guard !SettingsWindowController.shared.isSettingsWindowVisible else { return }

            let policy: NSApplication.ActivationPolicy = showMenuBarIcon ? .accessory : .regular
            guard NSApp.activationPolicy() == policy || NSApp.setActivationPolicy(policy) else {
                NSLog("OptClicker: Could not apply activation policy %@ from menu bar preference", String(describing: policy))
                return
            }
        }
    }

    @objc private func handleHotkeyTriggered() {
        inputManager.isEnabled.toggle()
    }

    @objc private func frontmostAppDidChange() {
        let autoToggleEnabled = UserDefaults.standard.bool(forKey: InputManager.autoToggleEnabledKey)
        let rules = UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
        if autoToggleEnabled && !rules.isEmpty {
            DispatchQueue.main.async {
                self.inputManager.refreshAutoToggleState()
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    deinit {
        statusBarManager?.uninstall()
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
}

@main
struct OptClickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About OptClicker") {
                    UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "selectedSettingsTab")
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
