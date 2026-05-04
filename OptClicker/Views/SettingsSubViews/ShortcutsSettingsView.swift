import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Keyboard Shortcuts") {
                    SettingsRow("Toggle OptClicker") {
                        HStack {
                            Text(hotkeyManager.shortcutDescription)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListeningForNewShortcut()
                            }
                            .disabled(hotkeyManager.isListeningForShortcut)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault()
                            }
                            .disabled(hotkeyManager.isListeningForShortcut)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
