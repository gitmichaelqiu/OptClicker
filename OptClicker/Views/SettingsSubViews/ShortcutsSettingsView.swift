import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Keyboard Shortcuts") {
                    SettingsRow("Toggle OptClicker") {
                        Text(hotkeyManager.shortcutDescription)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(minHeight: 36)
                    
                    Divider()

                    SettingsRow("") {
                        HStack(spacing: 8) {
                            Button("Change…") {
                                hotkeyManager.startListeningForNewShortcut()
                            }
                            Button("Reset") {
                                hotkeyManager.resetToDefault()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minHeight: 36)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
