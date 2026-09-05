import SwiftUI

struct AutoToggleSpacesView: View {
    @Binding var rules: [String]
    @Binding var isExpanded: Bool
    let onRuleChange: () -> Void

    @State private var selection: String? = nil
    @ObservedObject private var spaceManager = SpaceManager.shared
    @State var isExpandedLocal: Bool = false
    
    init(
        rules: Binding<[String]>,
        isExpanded: Binding<Bool>,
        onRuleChange: @escaping () -> Void
    ) {
        self._rules = rules
        self._isExpanded = isExpanded
        self.onRuleChange = onRuleChange
        self._isExpandedLocal = State(initialValue: isExpanded.wrappedValue)
    }
    
    var body: some View {
        ModularSettingsRow(
            "Targeted spaces",
            warningText: spaceManager.isAPIEnabled
                ? nil : "Requires DesktopRenamer SpaceAPI."
        ) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpandedLocal.toggle()
                        isExpanded = isExpandedLocal
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpandedLocal ? 90 : 0))
                        .frame(width: 20, height: 16)
                }
            }
        }
        .onChange(of: isExpanded) { newExternalValue in
            guard newExternalValue != isExpandedLocal else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpandedLocal = newExternalValue
            }
        }

        if isExpandedLocal {
            VStack(alignment: .leading, spacing: 0) {
                let displayRules: [(id: String, name: String, icon: String)] = {
                    if rules.isEmpty {
                        return [("all", "All", "square.grid.3x3.fill")]
                    }
                    return rules.map { rule in
                        if rule == "fullscreen" {
                            return (rule, "Fullscreen", "rectangle.expand.vertical")
                        } else if let space = spaceManager.availableSpaces.first(where: { $0.id == rule }) {
                            return (rule, space.name, "square.grid.2x2")
                        } else {
                            return (rule, rule, "questionmark.square")
                        }
                    }
                }()

                List(selection: $selection) {
                    ForEach(displayRules, id: \.id) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.secondary)
                            Text(item.name)
                                .foregroundColor(item.id == "all" ? .secondary : .primary)
                                .italic(item.id == "all")
                            Spacer()
                        }
                        .tag(item.id == "all" ? nil : item.id)
                    }
                }
                .frame(height: min(160, CGFloat(displayRules.count) * 28 + 28))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                HStack {
                    Menu {
                        Button("Fullscreen") {
                            addRule("fullscreen")
                        }
                        
                        Divider()
                        
                        if spaceManager.availableSpaces.isEmpty {
                            Text("No Spaces available (DesktopRenamer not running?)")
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
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    addButton(
                        systemImage: "minus",
                        action: removeSelectedRule,
                        disabled: selection == nil
                    )
                    
                    Divider().frame(height: 16)
                    
                    addButton(
                        systemImage: "trash",
                        action: removeAllRules,
                        disabled: rules.isEmpty
                    )
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func addButton(
        systemImage: String,
        action: @escaping () -> Void,
        disabled: Bool = false,
        frameWidth: CGFloat = 24
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: frameWidth, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
    
    private func removeAllRules() {
        let alert = NSAlert()
        alert.messageText = "Remove All Targeted Spaces"
        alert.informativeText = "Are you sure to remove all targeted spaces?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        Task {
            if let targetWindow = NSApp.suitableSheetWindow(nil) {
                let response = await alert.beginSheetModal(for: targetWindow)
                if response == .alertFirstButtonReturn {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        rules.removeAll()
                        selection = nil
                        onRuleChange()
                    }
                }
            }
        }
    }
}
