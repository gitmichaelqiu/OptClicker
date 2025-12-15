import SwiftUI
import UserNotifications
import Combine
import AppKit

let defaultSettingsWindowWidth = 450
let defaultSettingsWindowHeight = 480

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var inputManagerCancellable: AnyCancellable?
    
    let inputManager = InputManager()
    let hotkeyManager = HotkeyManager()
    var statusBarManager: StatusBarManager?

    @objc func quitApp() {
        NSApp.terminate(self)
    }

    @objc func openSettingsWindow() {
        SettingsWindowController.shared.open(
            inputManager: inputManager,
            hotkeyManager: hotkeyManager
        )
        
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Auto update
        UNUserNotificationCenter.current().delegate = self
        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
                }
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
        defer { completionHandler() }
        if response.actionIdentifier == "openRelease",
           let url = URL(string: UpdateManager.shared.latestReleaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            NSWorkspace.shared.open(url)
            NSApp.perform(#selector(NSApp.terminate), with: nil, afterDelay: 0.5)
        }
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
struct OptClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("Menu.About", comment: "")) {
                    UserDefaults.standard.set(SettingsTab.about.rawValue, forKey: "selectedSettingsTab")
                }
            }
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
