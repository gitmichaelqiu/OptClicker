import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutoToggleView: View {
    @Binding var rules: [String]
    @Binding var isExpanded: Bool
    let onRuleChange: () -> Void

    @State private var selection: String? = nil
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
        SettingsRow("Target apps") {
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
                let sortedApps: [(id: String, name: String, icon: NSImage?)] = {
                    let categorized = rules.compactMap { rule -> (id: String, name: String, icon: NSImage?, typeOrder: Int)? in
                        if rule.hasPrefix("proc:") {
                            // Exact proc
                            let kw = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !kw.isEmpty else { return nil }
                            let displayName = String(format: NSLocalizedString("Process: %@", comment: ""), kw)
                            return (rule, displayName, nil, 0)
                        } else if rule.hasPrefix("proc~") {
                            // Partial proc
                            let kw = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !kw.isEmpty else { return nil }
                            let displayName = String(format: NSLocalizedString("Process (Partial): %@", comment: ""), kw)
                            return (rule, displayName, nil, 1)
                        } else if rule.hasPrefix("web:") {
                            // Website
                            let kw = String(rule.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !kw.isEmpty else { return nil }
                            let displayName = String(format: NSLocalizedString("Website: %@", comment: ""), kw)
                            return (rule, displayName, NSImage(systemSymbolName: "network", accessibilityDescription: nil), 2)
                        } else {
                            // Bundle ID fallback
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule),
                               let bundle = Bundle(url: url) {
                                let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? rule
                                let icon = NSWorkspace.shared.icon(forFile: url.path)
                                return (rule, name, icon, 3)
                            } else {
                                return (rule, rule, nil, 3)
                            }
                        }
                    }
                    
                    let sorted = categorized.sorted { lhs, rhs in
                        if lhs.typeOrder != rhs.typeOrder {
                            return lhs.typeOrder < rhs.typeOrder
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }

                    return sorted.map { ($0.id, $0.name, $0.icon) }
                }()

                List(selection: $selection) {
                    ForEach(sortedApps, id: \.id) { item in
                        HStack {
                            if let icon = item.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .cornerRadius(4)
                            }
                            Text(item.name)
                            Spacer()
                        }
                        .tag(item.id)
                    }
                }
                .frame(height: min(160, CGFloat(sortedApps.count) * 28 + 28))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                HStack {
                    // Add App (by bundle ID)
                    addButton(
                        systemImage: "plus",
                        action: { addAppByBundleID() },
                        frameWidth: 12
                    )
                    
                    // Extra add
                    Menu {
                        Button(NSLocalizedString("Steam Games", comment: "")) { addSteamApp() }
                        Button(NSLocalizedString("Chrome Apps", comment: "")) { addChromeApp() }
                        Button(NSLocalizedString("CrossOver Apps", comment: "")) { addCrossOverApp() }
                        Button(NSLocalizedString("Safari Apps", comment: ""))  { addSafariApp() }
                        Button(
                            String(format: NSLocalizedString("Minecraft (%@)", comment: ""), String(format: NSLocalizedString("Process: %@", comment: ""), "java"))
                        ) { addMinecraftJavaApp() }
                            .disabled(InputManager.isRuleDuplicated(newRule: "proc:java"))
                    } label: {
                    }
                    .frame(width: 8, height: 14)
                    .buttonStyle(.borderless)

                    Divider().frame(height: 16)

                    // Add by Process Name
                    addButton(
                        systemImage: "character.textbox",
                        action: addAppByProcessName,
                        frameWidth: 20
                    )
                    
                    // Partial match
                    Menu {
                        Button(NSLocalizedString("Partial match", comment: "")) { addPartialMatchProcess() }
                    } label: {
                    }
                    .frame(width: 8, height: 14)
                    .buttonStyle(.borderless)

                    Divider().frame(height: 16)

                    // Add Website
                    addButton(
                        systemImage: "network",
                        action: addWebsiteRule,
                        frameWidth: 20
                    )

                    Divider().frame(height: 16)

                    // Remove Selected
                    addButton(
                        systemImage: "minus",
                        action: removeSelectedRule,
                        disabled: selection == nil
                    )
                    
                    Divider().frame(height: 16)
                    
                    // Remove All
                    addButton(
                        systemImage: "trash",
                        action: removeAllRules,
                        disabled: rules.isEmpty
                    )
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
    
    private func addSteamApp() {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            print("Failed to get Application Support directory")
            return
        }

        let steamCommonPath = appSupportURL
            .appendingPathComponent("Steam")
            .appendingPathComponent("steamapps")
            .appendingPathComponent("common")
        
        if !FileManager.default.fileExists(atPath: steamCommonPath.path) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Folder Not Found", comment: "")
            alert.informativeText =  String(format: NSLocalizedString("OptClicker cannot find %@ app folder", comment: ""), "Steam")
            alert.alertStyle = .warning
            
            Task {
                if let targetWindow = NSApp.suitableSheetWindow(nil) {
                    _ = await alert.beginSheetModal(for: targetWindow)
                } else {
                    alert.runModal()
                }
            }
            
            return
        }

        addAppByBundleID(path: steamCommonPath)
    }
    
    private func addChromeApp() {
        let userHomeURL = FileManager.default.homeDirectoryForCurrentUser
        
        let appFolderPath = userHomeURL
            .appendingPathComponent("Applications")
            .appendingPathComponent("Chrome Apps.localized")
        
        if !FileManager.default.fileExists(atPath: appFolderPath.path) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Folder Not Found", comment: "")
            alert.informativeText =  String(format: NSLocalizedString("OptClicker cannot find %@ app folder", comment: ""), "Chrome Apps")
            alert.alertStyle = .warning
            
            Task {
                if let targetWindow = NSApp.suitableSheetWindow(nil) {
                    _ = await alert.beginSheetModal(for: targetWindow)
                } else {
                    alert.runModal()
                }
            }
            
            return
        }
        
        addAppByBundleID(path: appFolderPath)
    }
    
    private func addCrossOverApp() {
        let userHomeURL = FileManager.default.homeDirectoryForCurrentUser
        
        let appFolderPath = userHomeURL
            .appendingPathComponent("Applications")
            .appendingPathComponent("CrossOver")
        
        if !FileManager.default.fileExists(atPath: appFolderPath.path) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Folder Not Found", comment: "")
            alert.informativeText =  String(format: NSLocalizedString("OptClicker cannot find %@ app folder", comment: ""), "CrossOver")
            alert.alertStyle = .warning
            
            Task {
                if let targetWindow = NSApp.suitableSheetWindow(nil) {
                    _ = await alert.beginSheetModal(for: targetWindow)
                } else {
                    alert.runModal()
                }
            }
            
            return
        }
        
        addAppByBundleID(path: appFolderPath)
    }
    
    private func addSafariApp() {
        let userHomeURL = FileManager.default.homeDirectoryForCurrentUser
        
        let appFolderPath = userHomeURL
            .appendingPathComponent("Applications")
        
        if !FileManager.default.fileExists(atPath: appFolderPath.path) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Folder Not Found", comment: "")
            alert.informativeText =  String(format: NSLocalizedString("OptClicker cannot find %@ app folder", comment: ""), "Safari Apps")
            alert.alertStyle = .warning
            
            Task {
                if let targetWindow = NSApp.suitableSheetWindow(nil) {
                    _ = await alert.beginSheetModal(for: targetWindow)
                } else {
                    alert.runModal()
                }
            }
            
            return
        }
        
        addAppByBundleID(path: appFolderPath)
    }
    
    private func addMinecraftJavaApp() {
        let rule = "proc:java"
        if !InputManager.isRuleDuplicated(newRule: rule) {
            withAnimation(.easeInOut(duration: 0.2)) {
                rules.append(rule)
                onRuleChange()
            }
        }
    }

    private func addAppByBundleID(path: URL? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = NSLocalizedString("Choose Application", comment: "")
        
        var targetURL = path
        if let path = path, !path.hasDirectoryPath {
            targetURL = nil
        }
        if let url = targetURL, !FileManager.default.fileExists(atPath: url.path) {
            targetURL = nil
        }

        if let url = targetURL, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            panel.directoryURL = url
        }
        
        if let hostWindow = NSApp.suitableSheetWindow(nil) {
            panel.beginSheetModal(for: hostWindow) { response in
                if response == .OK, let url = panel.url {
                    self.handleSelectedApp(url)
                }
            }
        } else {
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                self.handleSelectedApp(url)
            }
        }
    }

    private func handleSelectedApp(_ url: URL) {
        if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
            if !rules.contains(bundleId) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    rules.append(bundleId)
                    onRuleChange()
                }
            }
        }
    }
    
    private func addAppByProcessName() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Add App by Process Name", comment: "")
        alert.informativeText = NSLocalizedString("Enter the exact process name (case-insensitive):", comment: "")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("Process", comment: "")
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("Add", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        if let hostWindow = NSApp.suitableSheetWindow(nil) {
            alert.beginSheetModal(for: hostWindow) { response in
                if response == .alertFirstButtonReturn {
                    self.processKeyword(textField.stringValue)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.processKeyword(textField.stringValue)
            }
        }
    }
    
    private func processKeyword(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            let rule = "proc:\(keyword)"
            if !InputManager.isRuleDuplicated(newRule: rule) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    rules.append(rule)
                    onRuleChange()
                }
            } else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Duplicated Process", comment: "")
                alert.informativeText = String(format: NSLocalizedString("Process %@ already exists", comment: ""), keyword)
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.alertStyle = .informational
                
                Task {
                    if let targetWindow = NSApp.suitableSheetWindow(nil) {
                        _ = await alert.beginSheetModal(for: targetWindow)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    private func addPartialMatchProcess() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Add Partial Process Match", comment: "")
        alert.informativeText = NSLocalizedString("Enter a pattern (case-insensitive).", comment: "")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("Process", comment: "")
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("Add", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        if let hostWindow = NSApp.suitableSheetWindow(nil) {
            alert.beginSheetModal(for: hostWindow) { response in
                if response == .alertFirstButtonReturn {
                    self.processPartialKeyword(textField.stringValue)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.processPartialKeyword(textField.stringValue)
            }
        }
    }

    private func processPartialKeyword(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            let rule = "proc~\(keyword)"
            if !InputManager.isRuleDuplicated(newRule: rule) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    rules.append(rule)
                    onRuleChange()
                }
            } else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Duplicated Process", comment: "")
                alert.informativeText = String(format: NSLocalizedString("Process %@ already exists", comment: ""), keyword)
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.alertStyle = .informational
                
                Task {
                    if let targetWindow = NSApp.suitableSheetWindow(nil) {
                        _ = await alert.beginSheetModal(for: targetWindow)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }
    }

    private func addWebsiteRule() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Add Website Rule", comment: "")
        alert.informativeText = NSLocalizedString("Enter a domain or URL (e.g., google.com):", comment: "")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = NSLocalizedString("example.com", comment: "")
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("Add", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        if let hostWindow = NSApp.suitableSheetWindow(nil) {
            alert.beginSheetModal(for: hostWindow) { response in
                if response == .alertFirstButtonReturn {
                    self.processWebsiteKeyword(textField.stringValue)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.processWebsiteKeyword(textField.stringValue)
            }
        }
    }

    private func processWebsiteKeyword(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            let rule = "web:\(keyword)"
            if !InputManager.isRuleDuplicated(newRule: rule) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    rules.append(rule)
                    onRuleChange()
                }
            } else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Duplicated Process", comment: "")
                alert.informativeText = String(format: NSLocalizedString("Process %@ already exists", comment: ""), keyword)
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.alertStyle = .informational
                
                Task {
                    if let targetWindow = NSApp.suitableSheetWindow(nil) {
                        _ = await alert.beginSheetModal(for: targetWindow)
                    } else {
                        alert.runModal()
                    }
                }
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
        alert.messageText = NSLocalizedString("Remove All Target Apps", comment: "")
        alert.informativeText =  NSLocalizedString("Are you sure to remove all target apps?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
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
