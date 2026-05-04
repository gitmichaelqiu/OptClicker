import SwiftUI
import AppKit

class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var inputManager: InputManager?
    private var hotkeyManager: HotkeyManager?

    private override init() {
        super.init()
        NSSplitViewItem.swizzle()
    }

    func open(inputManager: InputManager, hotkeyManager: HotkeyManager) {
        self.inputManager = inputManager
        self.hotkeyManager = hotkeyManager

        if window == nil {
            createWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func createWindow() {
        let size = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.setFrameAutosaveName("Settings")
        win.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        win.isReleasedWhenClosed = false
        win.minSize = size
        win.maxSize = size
        win.level = .normal
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.participatesInCycle]

        // Inject dependencies
        guard let inputManager = self.inputManager,
              let hotkeyManager = self.hotkeyManager else {
            fatalError("SettingsWindowController: dependencies not set")
        }

        let rootView = SettingsView(inputManager: inputManager)
            .environmentObject(hotkeyManager)
        win.contentView = NSHostingView(rootView: rootView)

        // Observe close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: win
        )

        self.window = win
    }
}
