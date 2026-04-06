//
//  MalcomeApp.swift
//  Malcome
//
//  Created by Mark Friedlander on 3/21/26.
//

import SwiftUI

@main
struct MalcomeApp: App {
    @StateObject private var appModel = AppViewModel(container: AppContainer.live())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
    }
}
