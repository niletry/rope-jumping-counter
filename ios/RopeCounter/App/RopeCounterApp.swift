import SwiftUI

@main
struct RopeCounterApp: App {
    @State private var store = WorkoutStore(replayDir: RopeCounterApp.replayDirArgument())

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .tint(Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255))
                .onAppear {
                    // Debug replay: skip the setup screen and start a free workout on the frames.
                    if store.replayDir != nil && store.screen == .setup {
                        store.config.mode = .free
                        store.startWorkout()
                    }
                }
        }
    }

    /// `-replayDir /abs/path` on the command line (simulator) or launch arguments (device).
    private static func replayDirArgument() -> URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-replayDir"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }
}

struct RootView: View {
    @Bindable var store: WorkoutStore

    var body: some View {
        switch store.screen {
        case .setup: SetupScreen(store: store)
        case .workout: WorkoutScreen(store: store)
        case .history: HistoryScreen(store: store)
        }
    }
}
