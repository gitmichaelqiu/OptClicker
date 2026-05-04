import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager.shared

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
                    VStack(alignment: .leading, spacing: 0) {
                        // Accessibility
                        SettingsRow("Settings.Advanced.Permissions.Accessibility", helperText: "Settings.Advanced.Permissions.Accessibility.Description") {
                            HStack {
                                PermissionStatusIcon(isGranted: permissionManager.isAccessibilityGranted)
                                
                                Button(permissionManager.isAccessibilityGranted ? NSLocalizedString("Settings.Advanced.Permissions.Settings", comment: "") : NSLocalizedString("Settings.Advanced.Permissions.Grant", comment: "")) {
                                    permissionManager.requestAccessibilityPermission()
                                }
                            }
                        }
                        
                        Divider().padding(.vertical, 8)
                        
                        // Automation
                        SettingsRow("Settings.Advanced.Permissions.Automation", helperText: "Settings.Advanced.Permissions.Automation.Description") {
                            HStack {
                                let anyGranted = permissionManager.isAutomationGrantedSafari || 
                                                 permissionManager.isAutomationGrantedChrome || 
                                                 permissionManager.isAutomationGrantedEdge || 
                                                 permissionManager.isAutomationGrantedArc
                                
                                PermissionStatusIcon(isGranted: anyGranted)
                                
                                Menu {
                                    browserButton(name: "Safari", bundleId: "com.apple.Safari", isGranted: permissionManager.isAutomationGrantedSafari)
                                    browserButton(name: "Google Chrome", bundleId: "com.google.Chrome", isGranted: permissionManager.isAutomationGrantedChrome)
                                    browserButton(name: "Microsoft Edge", bundleId: "com.microsoft.edgemac", isGranted: permissionManager.isAutomationGrantedEdge)
                                    browserButton(name: "Arc", bundleId: "company.thebrowser.Browser", isGranted: permissionManager.isAutomationGrantedArc)
                                } label: {
                                    Text(NSLocalizedString("Settings.Advanced.Permissions.Grant", comment: ""))
                                }
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
    
    @ViewBuilder
    private func browserButton(name: String, bundleId: String, isGranted: Bool) -> some View {
        Button {
            permissionManager.requestAutomationPermission(for: bundleId, appName: name)
        } label: {
            HStack {
                if isGranted {
                    Image(systemName: "checkmark")
                }
                Text(name)
            }
        }
    }
}

struct PermissionStatusIcon: View {
    let isGranted: Bool
    
    var body: some View {
        Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(isGranted ? .green : .red)
    }
}
