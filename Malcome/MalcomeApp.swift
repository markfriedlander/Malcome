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

    #if DEBUG
    @State private var apiServer = MalcomeAPIServer()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                #if DEBUG
                .task {
                    apiServer.start(appModel: appModel)
                }
                #endif
        }
    }
}
