import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("Today", systemImage: "text.quote")
            }

            NavigationStack {
                RadarView()
            }
            .tabItem {
                Label("Radar", systemImage: "dot.radiowaves.left.and.right")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }
}
