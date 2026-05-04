import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection("Settings.Shortcuts.General") {
                    SettingsRow("Settings.Shortcuts.Hotkey") {
                        Text(hotkeyManager.shortcutDescription)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    Divider()

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
                }
                
                SettingsSection("Settings.Advanced.Permissions") {
                    VStack(alignment: .leading, spacing: 0) {
                        // Accessibility
                        SettingsRow("Settings.Advanced.Permissions.Accessibility", helperText: "Settings.Advanced.Permissions.Accessibility.Description") {
                            HStack(spacing: 12) {
                                PermissionStatusIcon(isGranted: permissionManager.isAccessibilityGranted)
                                
                                Button(permissionManager.isAccessibilityGranted ? NSLocalizedString("Settings.Advanced.Permissions.Settings", comment: "") : NSLocalizedString("Settings.Advanced.Permissions.Grant", comment: "")) {
                                    permissionManager.requestAccessibilityPermission()
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Automation
                        VStack(alignment: .leading, spacing: 0) {
                            SettingsRow("Settings.Advanced.Permissions.Automation", helperText: "Settings.Advanced.Permissions.Automation.Description") {
                                HStack(spacing: 12) {
                                    let anyGranted = permissionManager.automationPermissions.values.contains(true)
                                    PermissionStatusIcon(isGranted: anyGranted)
                                    
                                    Button(NSLocalizedString("Settings.Advanced.Permissions.Grant", comment: "")) {
                                        selectBrowserFromApplications()
                                    }
                                }
                            }
                            
                            let grantedBrowsers = permissionManager.knownBrowsers.filter { permissionManager.automationPermissions[$0.key] == true }
                            
                            if !grantedBrowsers.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("Settings.Advanced.Permissions.Automation.GrantedList", comment: "Granted browsers:"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 10)
                                    
                                    ForEach(grantedBrowsers.sorted(by: { $0.value < $1.value }), id: \.key) { bundleId, name in
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            Text(name)
                                                .font(.caption)
                                            Spacer()
                                            
                                            Button {
                                                permissionManager.removeBrowser(bundleId: bundleId)
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        }
                    }
                }
                
                if let helpText = NSLocalizedString("Settings.Advanced.Permissions.Description", comment: "") as String?, !helpText.isEmpty {
                    Text(helpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    private func selectBrowserFromApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = NSLocalizedString("Settings.Advanced.Permissions.SelectBrowser", comment: "Select Browser")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        let hostWindow = NSApp.suitableSheetWindow(nil)!
        panel.beginSheetModal(for: hostWindow) { response in
            if response == .OK, let url = panel.url {
                if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                    permissionManager.addBrowser(bundleId: bundleId, name: name)
                    permissionManager.requestAutomationPermission(for: bundleId, appName: name)
                }
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
