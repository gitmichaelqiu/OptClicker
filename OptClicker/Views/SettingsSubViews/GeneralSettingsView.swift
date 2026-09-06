import SwiftUI
import Combine
import Sparkle

struct GeneralSettingsView: View {
    @ObservedObject var inputManager: InputManager
    @ObservedObject private var permissionManager = PermissionManager.shared
    
    @State private var launchAtLogin = LaunchManager.isEnabled
    @State private var selectedLaunchBehavior: LaunchBehavior = {
        let raw = UserDefaults.standard.string(forKey: InputManager.launchBehaviorKey) ?? LaunchBehavior.lastState.rawValue
        return LaunchBehavior(rawValue: raw) ?? .lastState
    }()
    
    @State private var showStatusReason = UserDefaults.standard.bool(forKey: InputManager.showStatusReasonKey)
    @State private var showFrontmostProc = UserDefaults.standard.bool(forKey: InputManager.showFrontmostProcKey)

    @State private var autoCheckUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates
    @State private var autoDownloadUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                ModularSettingsSection("General") {
                    ModularSettingsRow(
                        "Enable option → right click",
                        warningText: permissionManager.isAccessibilityGranted && permissionManager.isPostEventGranted
                            ? nil : "Requires Accessibility and input event permissions."
                    ) {
                        Toggle("", isOn: $inputManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                ModularSettingsSection("Launch") {
                    ModularSettingsRow("Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _ in
                                LaunchManager.setEnabled(launchAtLogin)
                            }
                    }
                    
                    Divider()
                    
                    ModularSettingsRow("Launch behavior") {
                        Picker("", selection: $selectedLaunchBehavior) {
                            ForEach(LaunchBehavior.allCases, id: \.self) { behavior in
                                Text(behavior.localizedDescription).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: selectedLaunchBehavior) { _ in
                            UserDefaults.standard.set(selectedLaunchBehavior.rawValue, forKey: InputManager.launchBehaviorKey)
                        }
                    }
                }
                
                ModularSettingsSection("Menubar") {
                    ModularSettingsRow("Show status reason") {
                        Toggle("", isOn: $showStatusReason)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showStatusReason) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showStatusReasonKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                    
                    Divider()
                    
                    ModularSettingsRow("Show frontmost process") {
                        Toggle("", isOn: $showFrontmostProc)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showFrontmostProc) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showFrontmostProcKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                }

                ModularSettingsSection("Update") {
                    ModularSettingsRow("Check for updates automatically") {
                        Toggle("", isOn: $autoCheckUpdate).labelsHidden().toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates = value
                            }
                    }
                    Divider()

                    if autoCheckUpdate {
                        ModularSettingsRow("Automatically download updates") {
                            Toggle("", isOn: $autoDownloadUpdate).labelsHidden().toggleStyle(.switch)
                                .onChange(of: autoDownloadUpdate) { value in
                                    UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates = value
                                }
                        }
                        Divider()
                    }

                    ModularSettingsRow("Check for updates") {
                        Button(NSLocalizedString("Check Now", comment: "")) {
                            UpdateManager.shared.updaterController.checkForUpdates(nil)
                        }
                    }
                }

                Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: autoCheckUpdate)
    }
}
