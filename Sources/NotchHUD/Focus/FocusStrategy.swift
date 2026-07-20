protocol FocusStrategy: Sendable {
    func canHandle(_ identity: TerminalIdentity) -> Bool
    func focus(_ identity: TerminalIdentity) throws
}

enum FocusError: Error {
    case notFound
    case permissionDenied(String)
    case scriptFailed(String)
}
