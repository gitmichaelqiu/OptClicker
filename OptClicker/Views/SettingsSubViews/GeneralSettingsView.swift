import SwiftUI
import Combine

struct GeneralSettingsView: View {
    @ObservedObject var inputManager: InputManager
    
    @State private var autoCheckForUpdates = UpdateManager.isAutoCheckEnabled
    @State private var launchAtLogin = LaunchManager.isEnabled
    @State private var selectedLaunchBehavior: LaunchBehavior = {
        let raw = UserDefaults.standard.string(forKey: InputManager.launchBehaviorKey) ?? LaunchBehavior.lastState.rawValue
        return LaunchBehavior(rawValue: raw) ?? .lastState
    }()
    
    @State private var showStatusReason = UserDefaults.standard.bool(forKey: InputManager.showStatusReasonKey)
    @State private var showFrontmostProc = UserDefaults.standard.bool(forKey: InputManager.showFrontmostProcKey)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("OptClicker") {
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
                        Toggle("", isOn: $autoCheckForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckForUpdates) { _ in
                                UpdateManager.isAutoCheckEnabled = autoCheckForUpdates
                            }
                    }
                    Divider()
                    SettingsRow("Check for updates") {
                        Button("Check Now") {
                            Task {
                                await UpdateManager.shared.checkForUpdate(from: NSApp.keyWindow)
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
}
