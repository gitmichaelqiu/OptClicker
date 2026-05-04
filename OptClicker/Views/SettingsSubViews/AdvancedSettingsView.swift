import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var selection: String? = nil

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
                                    let anyGranted = !permissionManager.authorizedBrowsers.isEmpty || permissionManager.automationPermissions.values.contains(true)
                                    PermissionStatusIcon(isGranted: anyGranted)
                                    
                                    Button(NSLocalizedString("Settings.Advanced.Permissions.Grant", comment: "")) {
                                        selectBrowserFromApplications()
                                    }
                                }
                            }
                            
                            // Show authorized browsers (even if closed)
                            let authorizedList = permissionManager.knownBrowsers
                                .filter { permissionManager.authorizedBrowsers.contains($0.key) || permissionManager.automationPermissions[$0.key] == true }
                                .map { (bundleId: $0.key, name: $0.value) }
                                .sorted(by: { $0.name < $1.name })
                            
                            if !authorizedList.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    List(selection: $selection) {
                                        ForEach(authorizedList, id: \.bundleId) { browser in
                                            HStack {
                                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId) {
                                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                                        .resizable()
                                                        .frame(width: 16, height: 16)
                                                        .cornerRadius(3)
                                                } else {
                                                    Image(systemName: "network")
                                                        .resizable()
                                                        .frame(width: 16, height: 16)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Text(browser.name)
                                                    .font(.body)
                                                
                                                Spacer()
                                                
                                                // Show as granted if it's in our authorized list
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                            .tag(browser.bundleId)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selection = browser.bundleId
                                            }
                                        }
                                    }
                                    .frame(height: min(120, CGFloat(authorizedList.count) * 28 + 8))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 10)
                                    
                                    HStack {
                                        Spacer()
                                        Button {
                                            if let sel = selection {
                                                permissionManager.removeBrowser(bundleId: sel)
                                                selection = nil
                                            }
                                        } label: {
                                            Image(systemName: "minus")
                                                .frame(width: 20, height: 14)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(selection == nil)
                                        .padding(.trailing, 14)
                                    }
                                    .padding(.top, 4)
                                }
                                .padding(.bottom, 12)
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
        .onAppear {
            permissionManager.checkPermissions()
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
                    
                    // Refresh selection to help user
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        permissionManager.checkPermissions()
                    }
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
