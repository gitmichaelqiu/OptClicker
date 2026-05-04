import SwiftUI

struct AboutView: View {
    var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "OptClicker"
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var currentYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header Section
                HStack(spacing: 20) {
                    if let nsImage = NSApplication.shared.applicationIconImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                        
                        Text("v\(appVersion)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("© \(currentYear) Michael Yicheng Qiu")
                            .font(.footnote)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                // Description
                Text("OptClicker lets you simulate right-clicks by pressing the Option (⌥) key.")
                    .font(.body)
                    .foregroundColor(.secondary)

                // Links Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Links")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        AboutLinkRow(title: "GitHub Repository", url: "https://github.com/gitmichaelqiu/OptClicker")
                        AboutLinkRow(title: "Michael's Website", url: "https://gitmichaelqiu.github.io")
                        AboutLinkRow(title: "Michael's GitHub", url: "https://github.com/gitmichaelqiu")
                    }
                }

                // More Apps Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("More Apps")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        OtherAppRow(
                            imageName: "DesktopRenamerIcon", // Try to find icon in Assets
                            appName: "DesktopRenamer",
                            description: "The ultimate desktop naming and management tool.",
                            url: "https://github.com/gitmichaelqiu/DesktopRenamer"
                        )
                        
                        OtherAppRow(
                            imageName: "SpaceSwitcherIcon",
                            appName: "SpaceSwitcher",
                            description: "Control which app and dock to show in each space.",
                            url: "https://github.com/gitmichaelqiu/SpaceSwitcher"
                        )
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AboutLinkRow: View {
    let title: String
    let url: String
    
    @State private var isHovering = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 4) {
                Text(title)
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct OtherAppRow: View {
    let imageName: String
    let appName: String
    let description: String
    let url: String
    
    @State private var isHovering = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 16) {
                // Icon Placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "app.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 6 : 2, x: 0, y: 2)
                .scaleEffect(isHovering ? 1.05 : 1.0)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isHovering {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
