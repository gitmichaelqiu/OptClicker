import SwiftUI
import Combine

/// Describes one destination in a modular settings sidebar.
public struct ModularSettingsTab: Hashable, Identifiable {
    public let id: String
    public let title: LocalizedStringResource
    public let systemImage: String

    public init(
        id: String,
        title: LocalizedStringResource,
        systemImage: String
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }

    public static func == (lhs: ModularSettingsTab, rhs: ModularSettingsTab) -> Bool {
        lhs.id == rhs.id && lhs.title.key == rhs.title.key && lhs.systemImage == rhs.systemImage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title.key)
        hasher.combine(systemImage)
    }
}

public struct ModularSettingsSearchItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let localizedTitle: String
    public let tabID: String
    public let keywords: [String]

    init(title: String, tabID: String, keywords: [String]) {
        self.id = "\(tabID):\(title)"
        self.title = title
        self.localizedTitle = NSLocalizedString(title, comment: "")
        self.tabID = tabID
        self.keywords = keywords
    }
}

@MainActor
public final class ModularSettingsNavigationState: ObservableObject {
    @Published public var searchText = ""
    @Published public var scrollToItemID: String?
    @Published public private(set) var registeredItems: [ModularSettingsSearchItem] = []

    private var registrationCounts = [String: Int]()

    public init() {}

    public func register(title: String, tabID: String, keywords: [String] = []) {
        let key = "\(tabID):\(title)"
        let count = registrationCounts[key, default: 0]
        registrationCounts[key] = count + 1
        guard count == 0 else { return }

        let allKeywords = keywords
            .flatMap(Self.tokens)
            + Self.tokens(title)
            + Self.tokens(NSLocalizedString(title, comment: ""))

        registeredItems.append(
            ModularSettingsSearchItem(
                title: title,
                tabID: tabID,
                keywords: Array(Set(allKeywords)).sorted()
            )
        )
    }

    public func unregister(title: String, tabID: String) {
        let key = "\(tabID):\(title)"
        let count = registrationCounts[key, default: 0]
        guard count > 1 else {
            registrationCounts[key] = nil
            registeredItems.removeAll { $0.id == key }
            return
        }
        registrationCounts[key] = count - 1
    }

    private static func tokens(_ value: String) -> [String] {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}

private struct ModularSettingsTabKey: EnvironmentKey {
    static let defaultValue = ModularSettingsTab(id: "default", title: "Settings", systemImage: "gearshape")
}

private struct ModularSettingsPreRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var modularSettingsTab: ModularSettingsTab {
        get { self[ModularSettingsTabKey.self] }
        set { self[ModularSettingsTabKey.self] = newValue }
    }

    var isModularSettingsPreRendering: Bool {
        get { self[ModularSettingsPreRenderingKey.self] }
        set { self[ModularSettingsPreRenderingKey.self] = newValue }
    }
}

public struct ModularSettingsContainer<Content: View>: View {
    private let tab: ModularSettingsTab
    private let content: () -> Content
    @EnvironmentObject private var navigationState: ModularSettingsNavigationState

    public init(_ tab: ModularSettingsTab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
                    .padding(16)
            }
            .environment(\.modularSettingsTab, tab)
            .onChange(of: navigationState.scrollToItemID) { itemID in
                guard let itemID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { proxy.scrollTo(itemID, anchor: .center) }
                    navigationState.scrollToItemID = nil
                }
            }
        }
    }
}

public struct ModularSettingsRow<Content: View>: View {
    private let title: LocalizedStringResource
    private let helperText: LocalizedStringKey?
    private let warningText: LocalizedStringKey?
    private let content: Content
    @AppStorage("ShowSettingsDemoVideos") private var showDemoVideos = true
    @Environment(\.modularSettingsTab) private var tab
    @Environment(\.isModularSettingsPreRendering) private var isPreRendering
    @EnvironmentObject private var navigationState: ModularSettingsNavigationState

    public init(
        _ title: LocalizedStringResource,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.content = content()
    }

    public var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(modularSettingsHighlightedText(
                    text: String(localized: title),
                    query: navigationState.searchText
                ))
                if let helperText { ModularSettingsInfoButton(text: helperText) }
                if let warningText { ModularSettingsWarningButton(text: warningText) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .id(title.key)
        .onAppear { navigationState.register(title: title.key, tabID: tab.id) }
        .onDisappear {
            if !isPreRendering {
                navigationState.unregister(title: title.key, tabID: tab.id)
            }
        }
    }
}

public struct ModularSettingsSection<Content: View>: View {
    private let title: LocalizedStringKey?
    private let helperText: LocalizedStringKey?
    private let content: Content

    public init(
        _ title: LocalizedStringKey? = nil,
        helperText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 4) {
                    Text(title).font(.headline)
                    if let helperText { ModularSettingsInfoButton(text: helperText) }
                }
                .padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, title == nil ? -10 : 0)
    }
}

public struct ModularSettingsInfoButton: View {
    let text: LocalizedStringKey
    @State private var isPresented = false

    public init(text: LocalizedStringKey) { self.text = text }

    public var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

public struct ModularSettingsWarningButton: View {
    let text: LocalizedStringKey
    @State private var isPresented = false

    public init(text: LocalizedStringKey) { self.text = text }

    public var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

public func modularSettingsHighlightedText(
    text: String,
    query: String,
    color: Color? = .blue
) -> AttributedString {
    var attributed = AttributedString(text)
    guard !query.isEmpty else { return attributed }

    var searchStart = attributed.startIndex
    while searchStart < attributed.endIndex {
        let remaining = String(attributed[searchStart...].characters)
        guard let range = remaining.lowercased().range(of: query.lowercased()) else { break }
        let offset = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
        let length = remaining.distance(from: range.lowerBound, to: range.upperBound)
        let start = attributed.index(searchStart, offsetByCharacters: offset)
        let end = attributed.index(start, offsetByCharacters: length)
        if let color { attributed[start..<end].foregroundColor = color }
        attributed[start..<end].inlinePresentationIntent = .stronglyEmphasized
        searchStart = end
    }
    return attributed
}
