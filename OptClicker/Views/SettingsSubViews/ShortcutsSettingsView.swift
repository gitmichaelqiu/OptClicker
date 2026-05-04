import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Keyboard Shortcuts") {
                    SettingsRow("Toggle OptClicker") {
                        HStack {
                            Text(hotkeyManager.shortcutDescription(for: .toggleApp))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .toggleApp)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .toggleApp)
                            }
                            .disabled(hotkeyManager.isListening)
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Toggle Auto Toggle") {
                        HStack {
                            Text(hotkeyManager.shortcutDescription(for: .toggleAutoToggle))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .toggleAutoToggle)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .toggleAutoToggle)
                            }
                            .disabled(hotkeyManager.isListening)
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
