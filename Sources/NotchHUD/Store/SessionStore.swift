import Observation

@Observable
@MainActor
final class SessionStore {
    private(set) var sessions: [Session] = []

    func apply(_ sessions: [Session]) {
        self.sessions = sessions.sorted { lhs, rhs in
            let lhsRank = Self.sortRank(for: lhs.displayStatus)
            let rhsRank = Self.sortRank(for: rhs.displayStatus)

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            let lhsCanFocus = lhs.terminal?.tty != nil
            let rhsCanFocus = rhs.terminal?.tty != nil
            if lhsCanFocus != rhsCanFocus {
                return lhsCanFocus
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    var counts: (working: Int, needsMe: Int, done: Int) {
        var working = 0
        var needsMe = 0
        var done = 0

        for session in sessions {
            switch session.displayStatus {
            case .working:
                working += 1
            case .needsMe:
                needsMe += 1
            case .done:
                done += 1
            case .idle:
                break
            }
        }

        return (working, needsMe, done)
    }

    var total: Int {
        sessions.count
    }

    private static func sortRank(for status: DisplayStatus) -> Int {
        switch status {
        case .needsMe:
            0
        case .working:
            1
        case .done:
            2
        case .idle:
            3
        }
    }
}
