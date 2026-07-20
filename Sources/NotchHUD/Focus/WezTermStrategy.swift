struct WezTermStrategy: FocusStrategy {
    func canHandle(_ identity: TerminalIdentity) -> Bool {
        false
    }

    func focus(_ identity: TerminalIdentity) throws {
        throw FocusError.notFound
    }
}
