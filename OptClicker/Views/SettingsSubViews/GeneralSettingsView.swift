import SwiftUI
import Combine

struct GeneralSettingsView: View {
    @AppStorage("AutoToggle.isExpanded") private var isAutoToggleExpanded = false
    @AppStorage("AutoToggle.Spaces.isExpanded") private var isAutoToggleSpacesExpanded = false
    
    @ObservedObject var inputManager: InputManager
    
    @State private var autoCheckForUpdates = UpdateManager.isAutoCheckEnabled
    @State private var launchAtLogin = LaunchManager.isEnabled
    @State private var selectedLaunchBehavior: LaunchBehavior = {
        let raw = UserDefaults.standard.string(forKey: InputManager.launchBehaviorKey) ?? LaunchBehavior.lastState.rawValue
        return LaunchBehavior(rawValue: raw) ?? .lastState
    }()
    @State private var autoToggleRules: [String] = UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
    @State private var autoToggleSpaces: [String] = UserDefaults.standard.stringArray(forKey: "autoToggleSpaces") ?? []
    
    @State private var autoToggleBehavior: AutoToggleBehavior = {
        let raw = UserDefaults.standard.string(forKey: "AutoToggleBehavior") ?? AutoToggleBehavior.disable.rawValue
        return AutoToggleBehavior(rawValue: raw) ?? .disable
    }()
    @State private var showStatusReason = UserDefaults.standard.bool(forKey: InputManager.showStatusReasonKey)
    @State private var showFrontmostProc = UserDefaults.standard.bool(forKey: InputManager.showFrontmostProcKey)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.General.OptClicker") {
                    SettingsRow("Settings.General.OptClicker.EnableOptClicker") {
                        Toggle("", isOn: $inputManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow("Settings.General.OptClicker.EnableAutoToggle") {
                        Toggle("", isOn: $inputManager.isAutoToggleEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: inputManager.isAutoToggleEnabled) { _ in
                                if inputManager.isAutoToggleEnabled {
                                    inputManager.refreshAutoToggleState()
                                }
                            }
                    }
                }

                if inputManager.isAutoToggleEnabled {
                    SettingsSection("Settings.General.AutoToggle") {
                        // Toggle logic selection
                        SettingsRow("Settings.General.AutoToggle.BasedOnApps") {
                            Toggle("", isOn: $inputManager.isBasedOnApps)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        Divider()
                        
                        SettingsRow("Settings.General.AutoToggle.BasedOnSpaces") {
                            Toggle("", isOn: $inputManager.isBasedOnSpaces)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        if inputManager.isBasedOnApps && inputManager.isBasedOnSpaces {
                            Divider()
                            SettingsRow("Settings.General.AutoToggle.MatchCondition") {
                                Picker("", selection: $inputManager.matchCondition) {
                                    ForEach(MatchCondition.allCases, id: \.self) { condition in
                                        Text(condition.localizedDescription).tag(condition)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                        
                        Divider()
                        
                        if inputManager.isBasedOnApps {
                            AutoToggleView(
                                rules: $autoToggleRules, isExpanded: $isAutoToggleExpanded,
                                onRuleChange: saveAndRefresh
                            )
                            Divider()
                        }
                        
                        if inputManager.isBasedOnSpaces {
                            AutoToggleSpacesView(
                                rules: $autoToggleSpaces, isExpanded: $isAutoToggleSpacesExpanded,
                                onRuleChange: saveAndRefresh
                            )
                            Divider()
                        }
                        
                        SettingsRow("Settings.General.AutoToggle.NotFrontmost") {
                            Picker("", selection: $autoToggleBehavior) {
                                ForEach(AutoToggleBehavior.allCases, id: \.self) { behavior in
                                    Text(behavior.localizedDescription).tag(behavior)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .onChange(of: autoToggleBehavior) { _ in
                                saveAndRefresh()
                            }
                        }
                    }
                }

                SettingsSection("Settings.General.Launch") {
                    SettingsRow("Settings.General.Launch.AtLogin") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _ in
                                LaunchManager.setEnabled(launchAtLogin)
                            }
                    }
                    if !inputManager.isAutoToggleEnabled {
                        Divider()
                        
                        SettingsRow("Settings.General.LaunchBehavior") {
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
                }
                
                SettingsSection("Settings.General.Menubar") {
                    SettingsRow("Settings.General.Menubar.ShowReason") {
                        Toggle("", isOn: $showStatusReason)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showStatusReason) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showStatusReasonKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.General.Menubar.ShowFrontmostProc") {
                        Toggle("", isOn: $showFrontmostProc)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showFrontmostProc) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showFrontmostProcKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                }

                SettingsSection("Settings.General.Update") {
                    SettingsRow("Settings.General.Update.AutoCheck") {
                        Toggle("", isOn: $autoCheckForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckForUpdates) { _ in
                                UpdateManager.isAutoCheckEnabled = autoCheckForUpdates
                            }
                    }
                    Divider()
                    SettingsRow("Settings.General.Update.ManualCheck") {
                        Button(NSLocalizedString("Settings.General.Update.ManualCheck", comment: "")) {
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
        .animation(.easeInOut(duration: 0.2), value: inputManager.isAutoToggleEnabled)
        .animation(.easeInOut(duration: 0.2), value: inputManager.isBasedOnApps)
        .animation(.easeInOut(duration: 0.2), value: inputManager.isBasedOnSpaces)
    }

    private func saveAndRefresh() {
        UserDefaults.standard.set(autoToggleRules, forKey: "AutoToggleAppBundleIds")
        UserDefaults.standard.set(autoToggleSpaces, forKey: "autoToggleSpaces")
        UserDefaults.standard.set(autoToggleBehavior.rawValue, forKey: "AutoToggleBehavior")
        inputManager.refreshAutoToggleState()
    }
}
