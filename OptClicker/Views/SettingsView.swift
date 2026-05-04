import SwiftUI

enum SettingsTab: String {
    case general, advanced, about
}

struct SettingsView: View {
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general
    @ObservedObject var inputManager: InputManager
    
    var body: some View {
        if #available(macOS 15.0, *) {
            TabView(selection: $selectedTab) {
                Tab(NSLocalizedString("Settings.General", comment: "General"), systemImage: "gearshape.fill", value: .general) {
                    GeneralSettingsView(inputManager: inputManager)
                }
                Tab(NSLocalizedString("Settings.Advanced", comment: "Advanced"), systemImage: "gearshape.2.fill", value: .advanced) {
                    AdvancedSettingsView()
                }
                Tab(NSLocalizedString("Settings.About", comment: "About"), systemImage: "info.circle.fill", value: .about) {
                    AboutView()
                }
            }
            .scenePadding()
        } else {
            TabView(selection: $selectedTab) {
                GeneralSettingsView(inputManager: inputManager)
                   .tabItem {
                       Label(
                           NSLocalizedString("Settings.General", comment: "General"),
                           systemImage: "gearshape.fill"
                       )
                   }
                   .tag(SettingsTab.general)

                AdvancedSettingsView()
                   .tabItem {
                       Label(
                           NSLocalizedString("Settings.Advanced", comment: "Advanced"),
                           systemImage: "gearshape.2.fill"
                       )
                   }
                   .tag(SettingsTab.advanced)

                AboutView()
                   .tabItem {
                       Label(
                           NSLocalizedString("Settings.About", comment: "About"),
                           systemImage: "info.circle.fill"
                       )
                   }
                   .tag(SettingsTab.about)
                }
                .scenePadding()
        }
    }
}
