import SwiftUI
import UIKit

enum Tab: String, CaseIterable {
    case home, sources, pro, settings
}

/// Four tabs on paper; the Welcome screen covers them until the user chooses what Carry covers.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: Tab = LaunchOptions.initialTab
    @State private var forcedWelcome = LaunchOptions.forceWelcome

    init() { TabBarStyle.apply() }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                HomeView(location: model.location)
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(Tab.home)
                SourcesView(location: model.location)
                    .tabItem { Label("Sources", systemImage: "switch.2") }
                    .tag(Tab.sources)
                ProView(pro: model.pro)
                    .tabItem { Label("Pro", systemImage: "text.below.photo") }
                    .tag(Tab.pro)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .tint(Theme.tangerine)

            if forcedWelcome || !model.welcomeDone {
                WelcomeView {
                    model.welcomeDone = true
                    tab = .sources
                    forcedWelcome = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.welcomeDone)
        .animation(.easeOut(duration: 0.15), value: forcedWelcome)
    }
}

/// Opaque paper tab bar with a hairline, ink2 idle, tangerine selected.
enum TabBarStyle {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UITheme.paper
        appearance.shadowColor = UITheme.line
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = UITheme.ink2
            item.normal.titleTextAttributes = [.foregroundColor: UITheme.ink2]
            item.selected.iconColor = UITheme.tangerine
            item.selected.titleTextAttributes = [.foregroundColor: UITheme.tangerine]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
