import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.Shortcuts.General") {
                    // Row: label + current shortcut
                    SettingsRow("Settings.Shortcuts.Hotkey") {
                        Text(hotkeyManager.shortcutDescription)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(minHeight: 36)

                    Divider()

                    // Row: buttons aligned right
                    SettingsRow("") {
                        HStack(spacing: 8) {
                            Button(NSLocalizedString("Settings.Shortcuts.Hotkey.Change", comment: "Change")) {
                                hotkeyManager.startListeningForNewShortcut()
                            }
                            Button(NSLocalizedString("Settings.Shortcuts.Hotkey.Reset", comment: "Reset")) {
                                hotkeyManager.resetToDefault()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minHeight: 36)
                }
                
                SettingsSection("Settings.Advanced.Permissions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("Settings.Advanced.Permissions.Description", comment: "Description"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Spacer()
                            Button(NSLocalizedString("Settings.Advanced.Permissions.Grant", comment: "Grant")) {
                                requestAutomationPermission()
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    private func requestAutomationPermission() {
        let scriptSource = "tell application \"Safari\" to return name of front document"
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
        }
    }
}
