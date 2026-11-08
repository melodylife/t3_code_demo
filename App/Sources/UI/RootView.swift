import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            GradientBackground()
            if showsSplash {
                SplashScreenView { showsSplash = false }
                    .transition(.opacity)
                    .zIndex(1)
            } else if let engine = app.engine {
                GameScreen(engine: engine)
                    .id(engine.sessionID)
                    .transition(.opacity)
            } else {
                MenuView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showsSplash)
        .animation(.easeInOut(duration: 0.22), value: app.engine?.sessionID)
    }
}
