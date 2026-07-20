import Foundation

struct Session: Identifiable, Sendable {
    let id: String
    let agent: String
    let project: String
    let status: SessionStatus
    let detail: String?
    let updatedAt: Date
    let seq: Int
    let terminal: TerminalIdentity?

    init(envelope: SessionEnvelope, updatedAt: Date) {
        id = envelope.id
        agent = envelope.agent
        project = Self.projectName(from: envelope)
        status = envelope.status
        detail = envelope.detail
        self.updatedAt = updatedAt
        seq = envelope.seq
        terminal = envelope.terminal
    }

    init?(envelope: SessionEnvelope) {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        guard let updatedAt = fractionalFormatter.date(from: envelope.updated)
            ?? standardFormatter.date(from: envelope.updated)
        else {
            return nil
        }

        self.init(envelope: envelope, updatedAt: updatedAt)
    }

    var displayStatus: DisplayStatus {
        status.displayStatus
    }

    private static func projectName(from envelope: SessionEnvelope) -> String {
        if let project = envelope.project, !project.isEmpty {
            return project
        }

        if let cwd = envelope.cwd, !cwd.isEmpty {
            let basename = URL(fileURLWithPath: cwd).lastPathComponent
            if !basename.isEmpty {
                return basename
            }
        }

        return envelope.id
    }
}
