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

    /// `-replayDir <path>` on the command line (simulator) or launch arguments (device).
    /// A relative path is resolved inside the app's Documents directory, which is the only
    /// place `devicectl device copy to` can put frames on a device.
    private static func replayDirArgument() -> URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-replayDir"), i + 1 < args.count else { return nil }
        let path = args[i + 1]
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : AppDirectories.documents.appendingPathComponent(path)
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
