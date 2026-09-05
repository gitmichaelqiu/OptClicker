import SwiftUI

struct AutoToggleSettingsView: View {
    @AppStorage("AutoToggle.isExpanded") private var isAutoToggleExpanded = false
    @AppStorage("AutoToggle.Spaces.isExpanded") private var isAutoToggleSpacesExpanded = false
    
    @ObservedObject var inputManager: InputManager
    @ObservedObject private var spaceManager = SpaceManager.shared
    
    @State private var autoToggleRules: [String] = UserDefaults.standard.stringArray(forKey: "AutoToggleAppBundleIds") ?? []
    @State private var autoToggleSpaces: [String] = UserDefaults.standard.stringArray(forKey: "autoToggleSpaces") ?? []
    
    @State private var autoToggleBehavior: AutoToggleBehavior = {
        let raw = UserDefaults.standard.string(forKey: "AutoToggleBehavior") ?? AutoToggleBehavior.disable.rawValue
        return AutoToggleBehavior(rawValue: raw) ?? .disable
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                ModularSettingsSection("Auto Toggle") {
                    ModularSettingsRow("Enable auto toggle") {
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
                ModularSettingsSection("Rules") {
                        // Toggle logic selection
                        ModularSettingsRow("Based on apps") {
                            Toggle("", isOn: $inputManager.isBasedOnApps)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        Divider()
                        
                        ModularSettingsRow(
                            "Based on spaces",
                            warningText: spaceManager.apiAvailability == .available
                                ? nil : "Requires DesktopRenamer SpaceAPI."
                        ) {
                            Toggle("", isOn: $inputManager.isBasedOnSpaces)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        
                        if inputManager.isBasedOnApps && inputManager.isBasedOnSpaces {
                            Divider()
                            ModularSettingsRow("Match condition") {
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
                    
                    ModularSettingsSection(nil) {
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
                    
                    ModularSettingsSection("Behavior") {
                        ModularSettingsRow("When not frontmost") {
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
