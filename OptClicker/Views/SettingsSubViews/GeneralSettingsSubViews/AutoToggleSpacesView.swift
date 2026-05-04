import SwiftUI

struct AutoToggleSpacesView: View {
    @Binding var rules: [String]
    @Binding var isExpanded: Bool
    let onRuleChange: () -> Void

    @State private var selection: String? = nil
    @StateObject private var spaceManager = SpaceManager.shared
    
    var body: some View {
        SettingsRow("Settings.General.AutoToggle.TargetSpaces") {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 20, height: 16)
                }
            }
        }

        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                let displayRules: [(id: String, name: String, icon: String)] = rules.map { rule in
                    if rule == "fullscreen" {
                        return (rule, NSLocalizedString("Settings.General.AutoToggle.Space.Fullscreen", comment: ""), "rectangle.expand.vertical")
                    } else if let space = spaceManager.availableSpaces.first(where: { $0.id == rule }) {
                        return (rule, space.name, "square.grid.2x2")
                    } else {
                        return (rule, rule, "questionmark.square")
                    }
                }

                List(selection: $selection) {
                    ForEach(displayRules, id: \.id) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .frame(width: 16, height: 16)
                            Text(item.name)
                            Spacer()
                        }
                        .tag(item.id)
                    }
                }
                .frame(height: min(120, CGFloat(displayRules.count) * 28 + 28))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                HStack {
                    Menu {
                        Button(NSLocalizedString("Settings.General.AutoToggle.Space.Fullscreen", comment: "")) {
                            addRule("fullscreen")
                        }
                        
                        Divider()
                        
                        if spaceManager.availableSpaces.isEmpty {
                            Text(NSLocalizedString("Settings.General.AutoToggle.Space.NoAPI", comment: ""))
                                .disabled(true)
                        } else {
                            ForEach(spaceManager.availableSpaces) { space in
                                Button(space.name) {
                                    addRule(space.id)
                                }
                                .disabled(rules.contains(space.id))
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 14)
                    }
                    .buttonStyle(.plain)

                    Divider().frame(height: 16)

                    Button(action: removeSelectedRule) {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(selection == nil)
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
        }
    }

    private func addRule(_ rule: String) {
        if !rules.contains(rule) {
            withAnimation(.easeInOut(duration: 0.2)) {
                rules.append(rule)
                onRuleChange()
            }
        }
    }

    private func removeSelectedRule() {
        if let selected = selection,
           let idx = rules.firstIndex(of: selected) {
            withAnimation(.easeInOut(duration: 0.2)) {
                rules.remove(at: idx)
                selection = nil
                onRuleChange()
            }
        }
    }
}
