import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Today", systemImage: "sparkles.rectangle.stack")
            }

            NavigationStack {
                IdentityReviewView()
            }
            .tabItem {
                Label("Identity", systemImage: "person.text.rectangle")
            }

            NavigationStack {
                SourcesView()
            }
            .tabItem {
                Label("Sources", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }
}
