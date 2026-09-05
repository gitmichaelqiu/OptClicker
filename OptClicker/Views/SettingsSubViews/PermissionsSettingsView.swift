import SwiftUI
import UniformTypeIdentifiers

struct PermissionsSettingsView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var spaceManager = SpaceManager.shared
    @State private var selection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                ModularSettingsSection("Permissions", helperText: "If the Settings show that the permission is granted but the app still does not have it, remove the app row in Settings and re-grant.") {
                    VStack(alignment: .leading, spacing: 0) {
                        // Accessibility
                        ModularSettingsRow("Accessibility", helperText: "Required for reading window information.") {
                            HStack(spacing: 12) {
                                PermissionStatusIcon(isGranted: permissionManager.isAccessibilityGranted)
                                
                                Button(permissionManager.isAccessibilityGranted ? "Settings" : "Grant") {
                                    permissionManager.requestAccessibilityPermission()
                                }
                            }
                        }

                        Divider()

                        // DesktopRenamer SpaceAPI
                        ModularSettingsRow("DesktopRenamer SpaceAPI", helperText: "Required for reading desktop spaces and using space-based auto toggle.") {
                            SpaceAPIStatusView(spaceManager: spaceManager)
                        }
                        
                        Divider()
                        
                        // Automation
                        VStack(alignment: .leading, spacing: 0) {
                            ModularSettingsRow("Browser automation", helperText: "Click Grant, then select a browser app (such as Safari, Chrome, or Edge). Firefox-based browsers are not supported.") {
                                HStack(spacing: 12) {
                                    let anyGranted = !permissionManager.authorizedBrowsers.isEmpty || permissionManager.automationPermissions.values.contains(true)
                                    PermissionStatusIcon(isGranted: anyGranted)
                                    
                                    Button("Grant") {
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
                                VStack(alignment: .leading, spacing: 0) {
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
                                                
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                            .tag(browser.bundleId)
                                        }
                                    }
                                    .frame(height: min(120, CGFloat(authorizedList.count) * 28 + 28))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 10)
                                    
                                    HStack(spacing: 12) {
                                        Button(action: {
                                            if let sel = selection {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    permissionManager.removeBrowser(bundleId: sel)
                                                    selection = nil
                                                }
                                            }
                                        }) {
                                            Image(systemName: "minus")
                                                .frame(width: 24, height: 14)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(selection == nil)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: permissionManager.authorizedBrowsers)
                        .animation(.easeInOut(duration: 0.2), value: permissionManager.automationPermissions)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            permissionManager.checkPermissions()
            permissionManager.refreshAutomationPermissions()
            spaceManager.refreshSpaceList()
        }
    }
    
    private func selectBrowserFromApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select Browser from Applications"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if let hostWindow = NSApp.suitableSheetWindow(nil) {
            panel.beginSheetModal(for: hostWindow) { response in
                self.handleOpenPanelResponse(response, panel: panel)
            }
        } else {
            let response = panel.runModal()
            handleOpenPanelResponse(response, panel: panel)
        }
    }
    
    private func handleOpenPanelResponse(_ response: NSApplication.ModalResponse, panel: NSOpenPanel) {
        if response == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        permissionManager.addBrowser(bundleId: bundleId, name: name)
                        permissionManager.requestAutomationPermission(for: bundleId)
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

private struct SpaceAPIStatusView: View {
    @ObservedObject var spaceManager: SpaceManager

    var body: some View {
        HStack(spacing: 8) {
            PermissionStatusIcon(isGranted: spaceManager.apiAvailability == .available)

            switch spaceManager.apiAvailability {
            case .available:
                EmptyView()
            case .disabled:
                Button("Open DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
            case .unavailable:
                Button("Launch DesktopRenamer") {
                    spaceManager.openDesktopRenamer()
                }
                .disabled(spaceManager.desktopRenamerApplicationURL == nil)

                Button("Install DesktopRenamer") {
                    spaceManager.openDesktopRenamerDownloadPage()
                }
            }
        }
        .frame(minHeight: 28)
    }
}
