import SwiftUI
import Combine
import Sparkle

struct GeneralSettingsView: View {
    @ObservedObject var inputManager: InputManager
    
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("General") {
                    SettingsRow("Enable option → right click") {
                        Toggle("", isOn: $inputManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SettingsSection("Launch") {
                    SettingsRow("Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _ in
                                LaunchManager.setEnabled(launchAtLogin)
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Launch behavior") {
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
                
                SettingsSection("Menubar") {
                    SettingsRow("Show status reason") {
                        Toggle("", isOn: $showStatusReason)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showStatusReason) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showStatusReasonKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Show frontmost process") {
                        Toggle("", isOn: $showFrontmostProc)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showFrontmostProc) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showFrontmostProcKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                }

                SettingsSection("Update") {
                    SettingsRow("Check for updates automatically") {
                        Toggle("", isOn: $autoCheckUpdate).labelsHidden().toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates = value
                            }
                    }
                    Divider()

                    if autoCheckUpdate {
                        SettingsRow("Automatically download updates") {
                            Toggle("", isOn: $autoDownloadUpdate).labelsHidden().toggleStyle(.switch)
                                .onChange(of: autoDownloadUpdate) { value in
                                    UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates = value
                                }
                        }
                        Divider()
                    }

                    SettingsRow("Check for updates") {
                        Button(NSLocalizedString("Check Now", comment: "")) {
                            UpdateManager.shared.updaterController.checkForUpdates(nil)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.2), value: autoCheckUpdate)
    }
}
