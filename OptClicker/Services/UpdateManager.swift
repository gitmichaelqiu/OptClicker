import Foundation
import AppKit
import Sparkle

extension NSApplication {
    // Resolves the most appropriate window for presenting sheet-modal interfaces.
    var suitableSheetWindow: NSWindow? {
        suitableSheetWindow(nil)
    }

    func suitableSheetWindow(_ preferred: NSWindow?) -> NSWindow? {
        if let w = preferred, w.isVisible { return w }

        return keyWindow
            ?? mainWindow
            ?? windows.first { $0.isVisible && $0.isKeyWindow }
            ?? windows.first { $0.isVisible }
            ?? windows.first
    }
}

class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()
    
    // Using an implicitly unwrapped optional allows us to initialize the controller 
    // after super.init, which is required to pass 'self' as the delegate.
    var updaterController: SPUStandardUpdaterController!
    
    override private init() {
        super.init()
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }
    
    // Programmatic feed URL to ensure Sparkle always knows where to look.
    func feedURLString(for updater: SPUUpdater) -> String? {
        return "https://raw.githubusercontent.com/gitmichaelqiu/OptClicker/main/appcast.xml"
    }
}
