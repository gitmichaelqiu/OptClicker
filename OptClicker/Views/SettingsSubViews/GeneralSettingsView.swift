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
                SettingsSection("OptClicker") {
                    SettingsRow("Enable option → right click") {
                        Toggle("", isOn: $inputManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow("Enable auto toggle") {
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
                    SettingsSection("Auto Toggle") {
                        // Toggle logic selection
                        SettingsRow("Based on apps") {
                            Toggle("", isOn: $inputManager.isBasedOnApps)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        Divider()
                        
                        SettingsRow("Based on spaces") {
                            Toggle("", isOn: $inputManager.isBasedOnSpaces)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        if inputManager.isBasedOnApps && inputManager.isBasedOnSpaces {
                            Divider()
                            SettingsRow("Match condition") {
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
                        
                        SettingsRow("When not frontmost") {
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

                SettingsSection("Launch") {
                    SettingsRow("Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _ in
                                LaunchManager.setEnabled(launchAtLogin)
                            }
                    }
                    if !inputManager.isAutoToggleEnabled {
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
                }
                
                SettingsSection("Menubar") {
                    SettingsRow("Show OptClicker status reason") {
                        Toggle("", isOn: $showStatusReason)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: showStatusReason) { newValue in
                                UserDefaults.standard.set(newValue, forKey: InputManager.showStatusReasonKey)
                                inputManager.objectWillChange.send()
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Show frontmost process name") {
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
                    SettingsRow("Automatically check for updates") {
                        Toggle("", isOn: $autoCheckForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckForUpdates) { _ in
                                UpdateManager.isAutoCheckEnabled = autoCheckForUpdates
                            }
                    }
                    Divider()
                    SettingsRow("Check for updates") {
                        Button("Check for updates") {
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
