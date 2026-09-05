import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, autoToggle, shortcuts, permissions, about

    var id: String { rawValue }

    var localizedName: LocalizedStringResource {
        switch self {
        case .general: return "General"
        case .autoToggle: return "Auto Toggle"
        case .permissions: return "Permissions"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .autoToggle: return "switch.2"
        case .permissions: return "lock.shield"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }

    var modularTab: ModularSettingsTab {
        ModularSettingsTab(id: id, title: localizedName, systemImage: iconName)
    }
}

let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth: CGFloat = 750
let defaultSettingsWindowHeight: CGFloat = 550
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 16
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var inputManager: InputManager
    @EnvironmentObject var hotkeyManager: HotkeyManager

    @StateObject private var navigationState = ModularSettingsNavigationState()
    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText = ""
    @State private var isIndexingSettings = true

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
            } detail: {
                detailView
            }

            if isIndexingSettings {
                // Pre-render each page briefly so every modular row is
                // registered for settings search, including hidden tabs.
                ZStack {
                    ForEach(SettingsTab.allCases) { tab in
                        settingsContent(for: tab)
                            .environmentObject(navigationState)
                            .environment(\.isModularSettingsPreRendering, true)
                    }
                }
                .frame(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
                .opacity(0.001)
                .allowsHitTesting(false)
            }
        }
        .environmentObject(navigationState)
        .navigationTitle("")
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
        .onChange(of: searchText) { newValue in
            navigationState.searchText = newValue
            if !newValue.isEmpty {
                let tabs = filteredTabs
                if let selectedTab, !tabs.contains(selectedTab) {
                    self.selectedTab = tabs.first
                } else if selectedTab == nil {
                    selectedTab = tabs.first
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isIndexingSettings = false
            }
        }
    }

    private var filteredTabs: [SettingsTab] {
        guard !searchText.isEmpty else { return SettingsTab.allCases }

        let query = searchText.lowercased()
        return SettingsTab.allCases.filter { tab in
            let matchesTabName = tab.id.lowercased().contains(query)
                || String(localized: tab.localizedName).lowercased().contains(query)

            let matchesSetting = navigationState.registeredItems.contains { item in
                item.tabID == tab.id && (
                    item.title.lowercased().contains(query)
                        || item.localizedTitle.lowercased().contains(query)
                        || item.keywords.contains { $0.contains(query) }
                )
            }

            return matchesTabName || matchesSetting
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.leading, -4)
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func sidebarContent(titleSize: CGFloat, spacing: CGFloat) -> some View {
        Section {
            if filteredTabs.isEmpty {
                Text("No results")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.top, 4)
            } else {
                ForEach(filteredTabs) { tab in
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarItem(for: tab)

                        if !searchText.isEmpty {
                            let matchingItems = navigationState.registeredItems.filter { item in
                                item.tabID == tab.id && (
                                    item.title.localizedCaseInsensitiveContains(searchText)
                                        || item.localizedTitle.localizedCaseInsensitiveContains(searchText)
                                        || item.keywords.contains {
                                            $0.localizedCaseInsensitiveContains(searchText)
                                        }
                                )
                            }

                            ForEach(matchingItems) { item in
                                Button {
                                    selectedTab = tab
                                    navigationState.scrollToItemID = item.title
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 12)

                                        Text(modularSettingsHighlightedText(
                                            text: item.localizedTitle,
                                            query: searchText,
                                            color: nil
                                        ))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(height: 18)
                            }
                        }
                    }
                    .tag(tab)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: spacing) {
                Color.clear.frame(height: 45)
                Text("Opt")
                    .font(.custom("Syncopate-Bold", size: titleSize))
                    .foregroundStyle(.primary)
                Text("Clicker")
                    .font(.custom("Syncopate-Bold", size: titleSize))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 10)
                searchField
                    .padding(.bottom, 12)
            }
        }
        .collapsible(false)
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 14.0, *) {
            List(selection: $selectedTab) {
                sidebarContent(titleSize: 21, spacing: 2)
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .ignoresSafeArea(.container, edges: .top)
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
        } else {
            List(selection: $selectedTab) {
                sidebarContent(titleSize: 21, spacing: 2)
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .ignoresSafeArea(.container, edges: .top)
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        let activeTab = selectedTab ?? filteredTabs.first ?? .general

        ZStack(alignment: .top) {
            settingsContent(for: activeTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, titleHeaderHeight)

            VStack(spacing: 0) {
                HStack {
                    Text(activeTab.localizedName)
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.leading, 20)
                    Spacer()
                }
                .frame(height: titleHeaderHeight)
                .background(.bar)
                Divider()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            ModularSettingsContainer(tab.modularTab) {
                GeneralSettingsView(inputManager: inputManager)
            }
        case .autoToggle:
            ModularSettingsContainer(tab.modularTab) {
                AutoToggleSettingsView(inputManager: inputManager)
            }
        case .permissions:
            ModularSettingsContainer(tab.modularTab) {
                PermissionsSettingsView()
            }
        case .shortcuts:
            ModularSettingsContainer(tab.modularTab) {
                ShortcutsSettingsView()
            }
        case .about:
            ModularSettingsContainer(tab.modularTab) {
                AboutView()
            }
        }
    }

    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName)
                    .font(.system(size: sidebarFontSize, weight: .medium))
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: sidebarRowHeight - 15)
            }
        }
        .frame(height: sidebarRowHeight)
    }
}

extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalSelector = #selector(getter: canCollapse)
        let swizzledSelector = #selector(getter: swizzledCanCollapse)

        guard
            let originalMethod = class_getInstanceMethod(NSSplitViewItem.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledSelector)
        else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc private var swizzledCanCollapse: Bool {
        if let window = viewController.view.window,
           window.identifier?.rawValue == "SettingsWindow" {
            return false
        }
        return self.swizzledCanCollapse
    }

    static func swizzle() {
        _ = swizzler
    }
}
