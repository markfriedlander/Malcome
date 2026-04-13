import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "text.quote")
            }
            .tag(0)

            NavigationStack {
                RadarView()
            }
            .tabItem {
                Label("Radar", systemImage: "dot.radiowaves.left.and.right")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }
}
