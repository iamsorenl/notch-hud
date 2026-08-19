import Foundation
import Testing
@testable import NotchHUD

private func recent(
    id: String,
    project: String = "demo",
    lastActive: Date
) -> RecentSession {
    RecentSession(
        id: id,
        title: "t-\(id)",
        projectName: project,
        cwd: "/Users/x/\(project)",
        lastActive: lastActive
    )
}

// MARK: - Head parsing (real transcript record shapes)

@Test func parseHeadExtractsTitlePromptAndCwd() {
    let lines = [
        #"{"type":"last-prompt","leafUuid":"7806192a","sessionId":"abc"}"#,
        #"{"type":"last-prompt","lastPrompt":"I want to make a pokemon game","sessionId":"abc"}"#,
        #"{"type":"ai-title","aiTitle":"Plan Pokemon game project on Linear","sessionId":"abc"}"#,
        #"{"type":"user","cwd":"/Users/Soren/Desktop/Active Projects","sessionId":"abc"}"#,
    ]
    let meta = SessionIndex.parseHead(lines)
    #expect(meta.aiTitle == "Plan Pokemon game project on Linear")
    #expect(meta.lastPrompt == "I want to make a pokemon game")
    #expect(meta.cwd == "/Users/Soren/Desktop/Active Projects")
}

@Test func parseHeadSkipsMalformedLinesAndToleratesMissingFields() {
    let lines = [
        "not json at all {{{",
        #"{"type":"ai-title","sessionId":"abc"}"#,
        #"{"type":"file-history-snapshot"}"#,
    ]
    let meta = SessionIndex.parseHead(lines)
    #expect(meta.aiTitle == nil)
    #expect(meta.lastPrompt == nil)
    #expect(meta.cwd == nil)
}

// MARK: - Planning (exclusion, ordering, cap)

@Test func planExcludesLiveSpoolSessions() {
    let now = Date()
    let sessions = [
        recent(id: "aaa", lastActive: now),
        recent(id: "bbb", lastActive: now.addingTimeInterval(-60)),
    ]
    let planned = SessionIndex.plan(
        candidates: sessions,
        liveSessionIDs: ["claude-aaa", "poller-42"],
        limit: 10
    )
    #expect(planned.map(\.id) == ["bbb"])
}

@Test func planSortsNewestFirstAndCaps() {
    let now = Date()
    let sessions = (0..<5).map { i in
        recent(id: "s\(i)", lastActive: now.addingTimeInterval(Double(-i * 60)))
    }
    let planned = SessionIndex.plan(
        candidates: sessions.shuffled(),
        liveSessionIDs: [],
        limit: 3
    )
    #expect(planned.map(\.id) == ["s0", "s1", "s2"])
}

// MARK: - Resume command

@Test func resumeCommandChangesDirectoryAndResumes() {
    let session = recent(id: "abc-123", lastActive: Date())
    let command = ResumeLauncher.command(for: session, directoryExists: { _ in true })
    #expect(command == "cd '/Users/x/demo' && claude --resume 'abc-123'")
}

@Test func resumeCommandFallsBackToHomeWhenCwdIsGone() {
    let session = recent(id: "abc-123", lastActive: Date())
    let command = ResumeLauncher.command(for: session, directoryExists: { _ in false })
    #expect(command == "cd \"$HOME\" && claude --resume 'abc-123'")
}

@Test func resumeCommandRejectsShellMetacharactersInSessionID() {
    let hostile = recent(id: "x'; rm -rf ~; echo '", lastActive: Date())
    #expect(ResumeLauncher.command(for: hostile, directoryExists: { _ in true }) == nil)
    #expect(!ResumeLauncher.isValidSessionID("a b"))
    #expect(!ResumeLauncher.isValidSessionID(""))
    #expect(ResumeLauncher.isValidSessionID("0c68dd8b-ed0e-4a65-8702-55d1d3b9dd3c"))
}
