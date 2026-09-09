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
        NSApp.setActivationPolicy(.accessory)
        OptClickerIdentityMigration.prepareNormalLaunch()

        inputManager = InputManager()
        hotkeyManager = HotkeyManager()
        
        // Status bar
        statusBarManager = StatusBarManager(inputManager: inputManager) {
            self.inputManager.isEnabled.toggle()
        }
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
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
