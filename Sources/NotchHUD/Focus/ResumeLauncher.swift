import Foundation

/// Reopens a finished Claude Code conversation in a new Terminal.app tab via
/// `claude --resume`. Uses the same AppleScriptRunner (and therefore the same
/// Automation permission) as click-to-focus; when automation is denied, the
/// row copies `command(for:)` to the clipboard instead so the resume is still
/// one paste away.
enum ResumeLauncher {
    static func command(
        for session: RecentSession,
        directoryExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        let cd = directoryExists(session.cwd)
            ? "cd '\(session.cwd.replacingOccurrences(of: "'", with: "'\\''"))'"
            : "cd \"$HOME\""
        return "\(cd) && claude --resume \(session.id)"
    }

    static func resume(_ session: RecentSession) throws {
        let shellCommand = command(for: session)
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
          activate
          do script "\(escaped)"
        end tell
        """
        _ = try AppleScriptRunner.run(source)
    }
}
