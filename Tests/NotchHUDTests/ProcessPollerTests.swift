import Foundation
import Testing
@testable import NotchHUD

private func envelope(
    id: String,
    agent: String = "claude-code",
    pid: Int? = nil,
    tty: String? = nil,
    source: String? = "notch-emit"
) -> SessionEnvelope {
    SessionEnvelope(
        schema: 1,
        id: id,
        agent: agent,
        pid: pid,
        status: .working,
        updated: "2026-08-18T10:00:00Z",
        seq: 1,
        terminal: tty.map {
            TerminalIdentity(
                termProgram: nil,
                tty: $0,
                itermSessionId: nil,
                weztermPane: nil,
                kittyWindowId: nil,
                windowId: nil
            )
        },
        source: source
    )
}

// MARK: - Agent regex matching

@Test func agentNameMatchesBareAndPathedCommands() {
    #expect(ProcessPoller.agentName(forCommand: "claude") == "claude")
    #expect(ProcessPoller.agentName(forCommand: "/opt/homebrew/bin/codex exec build") == "codex")
    #expect(ProcessPoller.agentName(forCommand: "claude --resume abc") == "claude")
}

@Test func agentNameMatchesInterpreterWrappedCommands() {
    #expect(ProcessPoller.agentName(forCommand: "node /usr/local/bin/claude --continue") == "claude")
    #expect(ProcessPoller.agentName(forCommand: "FOO=1 node /Users/x/.bin/codex") == "codex")
}

@Test func agentNameRejectsLookalikes() {
    #expect(ProcessPoller.agentName(forCommand: "vim claude") == nil)
    #expect(ProcessPoller.agentName(forCommand: "vim claude-notes.md") == nil)
    #expect(ProcessPoller.agentName(forCommand: "grep claude /tmp/log") == nil)
    #expect(ProcessPoller.agentName(forCommand: "sh /Users/x/bin/notch-claude-hook") == nil)
    #expect(ProcessPoller.agentName(forCommand: "claudette") == nil)
    #expect(ProcessPoller.agentName(forCommand: "") == nil)
}

// MARK: - Plan: skip ttyless workers

@Test func planSkipsTtylessProcesses() {
    let processes = [
        AgentProcess(pid: 100, tty: nil, command: "claude"),
        AgentProcess(pid: 200, tty: "/dev/ttys004", command: "codex"),
    ]

    let (candidates, removeIDs) = ProcessPoller.plan(processes: processes, envelopes: [])

    #expect(candidates == [PollerCandidate(pid: 200, agent: "codex", tty: "/dev/ttys004")])
    #expect(removeIDs.isEmpty)
}

// MARK: - Plan: source-rank protection

@Test func planSkipsProcessesOnHookReportedTTY() {
    let processes = [
        AgentProcess(pid: 100, tty: "/dev/ttys001", command: "claude"),
        AgentProcess(pid: 200, tty: "/dev/ttys002", command: "codex"),
    ]
    let envelopes = [
        envelope(id: "claude-abc", tty: "/dev/ttys001"),
    ]

    let (candidates, removeIDs) = ProcessPoller.plan(processes: processes, envelopes: envelopes)

    #expect(candidates == [PollerCandidate(pid: 200, agent: "codex", tty: "/dev/ttys002")])
    #expect(removeIDs.isEmpty)
}

@Test func planRemovesPollerSessionWhenHookTakesOver() {
    let processes = [
        AgentProcess(pid: 100, tty: "/dev/ttys001", command: "claude"),
    ]
    let envelopes = [
        envelope(id: "claude-abc", tty: "/dev/ttys001"),
        envelope(id: "poller-100", agent: "claude", pid: 100, tty: "/dev/ttys001", source: ProcessPoller.source),
    ]

    let (candidates, removeIDs) = ProcessPoller.plan(processes: processes, envelopes: envelopes)

    #expect(candidates.isEmpty)
    #expect(removeIDs == ["poller-100"])
}

@Test func planNeverRemovesHookSessions() {
    let envelopes = [
        envelope(id: "claude-abc", tty: "/dev/ttys001"),
        envelope(id: "claude-gone", tty: nil),
    ]

    let (candidates, removeIDs) = ProcessPoller.plan(processes: [], envelopes: envelopes)

    #expect(candidates.isEmpty)
    #expect(removeIDs.isEmpty)
}

// MARK: - Plan: clear on exit

@Test func planRemovesPollerSessionWhenProcessExits() {
    let envelopes = [
        envelope(id: "poller-100", agent: "codex", pid: 100, tty: "/dev/ttys004", source: ProcessPoller.source),
    ]

    let (candidates, removeIDs) = ProcessPoller.plan(processes: [], envelopes: envelopes)

    #expect(candidates.isEmpty)
    #expect(removeIDs == ["poller-100"])
}

@Test func planKeepsPollerSessionWhileProcessLives() {
    let processes = [
        AgentProcess(pid: 100, tty: "/dev/ttys004", command: "codex"),
    ]
    let envelopes = [
        envelope(id: "poller-100", agent: "codex", pid: 100, tty: "/dev/ttys004", source: ProcessPoller.source),
    ]

    let (candidates, removeIDs) = ProcessPoller.plan(processes: processes, envelopes: envelopes)

    #expect(candidates == [PollerCandidate(pid: 100, agent: "codex", tty: "/dev/ttys004")])
    #expect(removeIDs.isEmpty)
}

@Test func planDeduplicatesProcessesSharingATTY() {
    let processes = [
        AgentProcess(pid: 200, tty: "/dev/ttys004", command: "claude mcp serve"),
        AgentProcess(pid: 100, tty: "/dev/ttys004", command: "claude"),
    ]

    let (candidates, _) = ProcessPoller.plan(processes: processes, envelopes: [])

    #expect(candidates == [PollerCandidate(pid: 100, agent: "claude", tty: "/dev/ttys004")])
}

// MARK: - ps output parsing

@Test func parsePSOutputExtractsPidTTYAndCommand() {
    let output = """
          100 ttys004  claude --resume
          200 ??       /usr/sbin/distnoted
        garbage line
    """

    let processes = ProcessPoller.parsePSOutput(output)

    #expect(processes == [
        AgentProcess(pid: 100, tty: "/dev/ttys004", command: "claude --resume"),
        AgentProcess(pid: 200, tty: nil, command: "/usr/sbin/distnoted"),
    ])
}
