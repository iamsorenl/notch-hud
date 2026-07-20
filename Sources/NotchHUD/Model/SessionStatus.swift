import SwiftUI

enum SessionStatus: String, Codable, Sendable {
    case starting, working, needs_me, done, unknown
}

enum DisplayStatus: Hashable, Sendable {
    case working
    case needsMe
    case done
    case idle

    var color: Color {
        switch self {
        case .working:
            Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
        case .needsMe:
            Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)
        case .done:
            Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        case .idle:
            Color(red: 72 / 255, green: 72 / 255, blue: 74 / 255)
        }
    }

    var label: String {
        switch self {
        case .working:
            "Working"
        case .needsMe:
            "Needs me"
        case .done:
            "Done"
        case .idle:
            "Idle"
        }
    }
}

extension SessionStatus {
    var displayStatus: DisplayStatus {
        switch self {
        case .starting, .working:
            .working
        case .needs_me:
            .needsMe
        case .done:
            .done
        case .unknown:
            .idle
        }
    }
}
