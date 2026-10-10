import Foundation

/// Keeps the most recent workouts as a JSON file; newest first, capped at 100 like Android.
public final class SessionHistoryStore {
    public static let maxRecords = 100
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("workout_history.json")
    }

    public func load() -> [WorkoutRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([WorkoutRecord].self, from: data) else { return [] }
        return records
    }

    public func prepend(_ record: WorkoutRecord) {
        let records = Array(([record] + load()).prefix(Self.maxRecords))
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
