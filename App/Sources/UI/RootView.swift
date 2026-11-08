import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            GradientBackground()
            if let engine = app.engine {
                GameScreen(engine: engine)
                    .id(engine.level.id)
                    .transition(.opacity)
            } else {
                MenuView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: app.engine?.level.id)
    }
}
