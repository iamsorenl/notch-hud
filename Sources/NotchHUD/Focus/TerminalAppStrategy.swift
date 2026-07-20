import Foundation

struct TerminalAppStrategy: FocusStrategy {
    func canHandle(_ identity: TerminalIdentity) -> Bool {
        identity.termProgram == "Apple_Terminal" && identity.tty != nil
    }

    func focus(_ identity: TerminalIdentity) throws {
        guard let tty = identity.tty else {
            throw FocusError.notFound
        }

        let escapedTTY = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
          activate
          set target to "\(escapedTTY)"
          repeat with w in windows
            repeat with t in tabs of w
              if (tty of t) is target then
                set selected of t to true
                set index of w to 1
                return "ok"
              end if
            end repeat
          end repeat
        end tell
        return "notfound"
        """

        if try AppleScriptRunner.run(source) == "notfound" {
            throw FocusError.notFound
        }
    }
}
