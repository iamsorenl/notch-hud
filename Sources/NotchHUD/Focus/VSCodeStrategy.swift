import AppKit
import Foundation

/// VS Code's integrated terminal (and Cursor's, which reports the same
/// TERM_PROGRAM) has no scriptable tab model like the real terminals, so the
/// jump is app activation: raise the editor's windows. Workspace-precise
/// focusing needs the `code` CLI, which is layered on here if it ever shows up.
struct VSCodeStrategy: FocusStrategy {
    /// Cursor is a VS Code fork and reuses its TERM_PROGRAM.
    private static let bundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    func canHandle(_ identity: TerminalIdentity) -> Bool {
        identity.termProgram == "vscode"
    }

    func focus(_ identity: TerminalIdentity) throws {
        let app = Self.bundleIdentifiers
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .first

        guard let app else {
            throw FocusError.notFound
        }

        let activate = {
            _ = app.activate(options: [.activateAllWindows])
        }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }
    }
}
