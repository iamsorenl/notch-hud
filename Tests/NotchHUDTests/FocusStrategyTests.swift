import Testing
@testable import NotchHUD

private func identity(termProgram: String?, tty: String? = "/dev/ttys005") -> TerminalIdentity {
    TerminalIdentity(
        termProgram: termProgram,
        tty: tty,
        itermSessionId: nil,
        weztermPane: nil,
        kittyWindowId: nil,
        windowId: nil
    )
}

@Test func vscodeStrategyHandlesVSCodeAndCursorSessions() {
    let strategy = VSCodeStrategy()
    #expect(strategy.canHandle(identity(termProgram: "vscode")))
    #expect(!strategy.canHandle(identity(termProgram: "Apple_Terminal")))
    #expect(!strategy.canHandle(identity(termProgram: nil)))
}
