import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                ModularSettingsSection("Keyboard Shortcuts") {
                    ModularSettingsRow("Toggle option → right click") {
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
                    
                    ModularSettingsRow("Toggle Auto Toggle") {
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
