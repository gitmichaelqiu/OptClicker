import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, autoToggle, shortcuts, permissions, about

    var id: String { self.rawValue }

    var localizedName: String {
        switch self {
        case .general: return NSLocalizedString("General", comment: "")
        case .autoToggle: return NSLocalizedString("Auto Toggle", comment: "")
        case .permissions: return NSLocalizedString("Permissions", comment: "")
        case .shortcuts: return NSLocalizedString("Shortcuts", comment: "")
        case .about: return NSLocalizedString("About", comment: "")
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
}

// UI layout constants for consistent sizing.
let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth: CGFloat = 750
let defaultSettingsWindowHeight: CGFloat = 550
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 14
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var inputManager: InputManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    @State private var selectedTab: SettingsTab? = .general
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("")
        .modifier(ToolbarHider())
        .edgesIgnoringSafeArea(.top)
        .frame(
            width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight
        )
    }

    struct ToolbarHider: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.toolbar(.hidden, for: .windowToolbar)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 14.0, *) {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Color.clear.frame(height: 30)
                        Text("Opt").font(.custom("Syncopate-Bold", size: 21)).foregroundStyle(.primary)
                        Text("Clicker").font(.custom("Syncopate-Bold", size: 21)).foregroundStyle(.primary).padding(.bottom, 20)
                    }
                }
                .collapsible(false)
            }
            .scrollDisabled(true)
            .removeSidebarToggle()
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
            .edgesIgnoringSafeArea(.top)
        } else {
            // Fallback for macOS 13
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Color.clear.frame(height: 30)
                        Text("Opt").font(.system(size: 21, weight: .bold, design: .monospaced)).foregroundStyle(.primary)
                        Text("Clicker").font(.system(size: 21, weight: .bold, design: .monospaced)).foregroundStyle(.primary).padding(.bottom, 20)
                    }
                }
                .collapsible(false)
            }
            .scrollDisabled(true)
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
            .listStyle(.sidebar)
            .edgesIgnoringSafeArea(.top)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                if let tab = selectedTab {
                    switch tab {
                    case .general:
                        GeneralSettingsView(inputManager: inputManager)
                    case .autoToggle:
                        AutoToggleSettingsView(inputManager: inputManager)
                    case .permissions:
                        PermissionsSettingsView()
                    case .shortcuts:
                        ShortcutsSettingsView()
                    case .about:
                        AboutView()
                    }
                } else {
                    Text("Select a category").foregroundColor(.secondary).frame(
                        maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, titleHeaderHeight)

            if let tab = selectedTab {
                VStack(spacing: 0) {
                    HStack {
                        Text(tab.localizedName).font(.system(size: 18, weight: .semibold)).padding(
                            .leading, 20)
                        Spacer()
                    }
                    .frame(height: titleHeaderHeight)
                    .background(.bar)
                    Divider()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .edgesIgnoringSafeArea(.top)
    }

    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName).font(.system(size: sidebarFontSize, weight: .medium))
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName).resizable().scaledToFit().frame(
                    height: sidebarRowHeight - 16)
            }
        }
        .frame(height: sidebarRowHeight)
    }
}

@available(macOS 14.0, *)
extension View {
    func removeSidebarToggle() -> some View {
        toolbar(removing: .sidebarToggle)
            .toolbar {
                Color.clear
            }
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
