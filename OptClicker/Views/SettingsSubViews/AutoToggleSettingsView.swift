import SwiftUI

struct AutoToggleSettingsView: View {
    @AppStorage("AutoToggle.isExpanded") private var isAutoToggleExpanded = false
    @AppStorage("AutoToggle.Spaces.isExpanded") private var isAutoToggleSpacesExpanded = false
    
    @ObservedObject var inputManager: InputManager
    
    @State private var autoToggleRules: [String] = UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
    @State private var autoToggleSpaces: [String] = UserDefaults.standard.stringArray(forKey: "autoToggleSpaces") ?? []
    
    @State private var autoToggleBehavior: AutoToggleBehavior = {
        let raw = UserDefaults.standard.string(forKey: "AutoToggleBehavior") ?? AutoToggleBehavior.disable.rawValue
        return AutoToggleBehavior(rawValue: raw) ?? .disable
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Auto Toggle") {
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
                SettingsSection("Rules") {
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
                    }
                    
                    SettingsSection(nil) {
                        if inputManager.isBasedOnApps {
                            AutoToggleView(
                                rules: $autoToggleRules, isExpanded: $isAutoToggleExpanded,
                                onRuleChange: saveAndRefresh
                            )
                        }

                        if inputManager.isBasedOnApps && inputManager.isBasedOnSpaces {
                            Divider()
                        }
                        
                        if inputManager.isBasedOnSpaces {
                            AutoToggleSpacesView(
                                rules: $autoToggleSpaces, isExpanded: $isAutoToggleSpacesExpanded,
                                onRuleChange: saveAndRefresh
                            )
                        }
                    }
                    
                    SettingsSection("Behavior") {
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

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.2), value: inputManager.isAutoToggleEnabled)
        .animation(.easeInOut(duration: 0.2), value: inputManager.isBasedOnApps)
        .animation(.easeInOut(duration: 0.2), value: inputManager.isBasedOnSpaces)
        .animation(.easeInOut(duration: 0.2), value: isAutoToggleExpanded)
        .animation(.easeInOut(duration: 0.2), value: isAutoToggleSpacesExpanded)
    }

    private func saveAndRefresh() {
        UserDefaults.standard.set(autoToggleRules, forKey: "AutoToggleAppBundleIds")
        UserDefaults.standard.set(autoToggleSpaces, forKey: "autoToggleSpaces")
        UserDefaults.standard.set(autoToggleBehavior.rawValue, forKey: "AutoToggleBehavior")
        inputManager.refreshAutoToggleState()
    }
}
