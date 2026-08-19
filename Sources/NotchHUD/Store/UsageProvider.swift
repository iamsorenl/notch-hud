import Foundation
import Observation

/// M5 usage meters (5-hour / 7-day windows).
///
/// Probe results on this machine (2026-08-18): NO clean local source exists.
/// - The `claude` CLI has no `usage` subcommand (`claude --help` lists none).
/// - `~/.claude/stats-cache.json` holds stale lifetime token stats, not
///   rate-limit window utilization.
/// - Nothing under `~/.claude` caches OAuth rate-limit / usage data.
///
/// Per the M5 gate ("meters real or cleanly absent") the provider therefore
/// waits for `~/.claude/usage.json` — the shape Claude Code's `/usage` view
/// surfaces — and publishes nil until that file exists and parses:
///
///     {"five_hour": {"utilization": 37}, "seven_day": {"utilization": 12}}
///
/// While `snapshot` is nil the panel header renders no meters at all.
/// Never invent numbers.
struct UsageSnapshot: Equatable {
    var fiveHourPercent: Int?
    var sevenDayPercent: Int?

    static func parse(_ data: Data) -> UsageSnapshot? {
        guard let file = try? JSONDecoder().decode(UsageFile.self, from: data) else {
            return nil
        }

        let snapshot = UsageSnapshot(
            fiveHourPercent: file.fiveHour?.percent,
            sevenDayPercent: file.sevenDay?.percent
        )
        guard snapshot.fiveHourPercent != nil || snapshot.sevenDayPercent != nil else {
            return nil
        }
        return snapshot
    }

    private struct UsageFile: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }

        struct Window: Decodable {
            let utilization: Double

            var percent: Int {
                Swift.min(Swift.max(Int(utilization.rounded()), 0), 100)
            }
        }
    }
}

@MainActor
@Observable
final class UsageProvider {
    private(set) var snapshot: UsageSnapshot?

    private let usageURL: URL
    private var timer: Timer?

    init(
        usageURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/usage.json", isDirectory: false)
    ) {
        self.usageURL = usageURL
    }

    func start() {
        guard timer == nil else { return }

        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        snapshot = (try? Data(contentsOf: usageURL)).flatMap(UsageSnapshot.parse)
    }
}
