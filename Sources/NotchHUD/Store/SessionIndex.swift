import Foundation

struct RecentSession: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let projectName: String
    let cwd: String
    let lastActive: Date
}

/// Read-only index over Claude Code's transcript store
/// (`~/.claude/projects/<slug>/<sessionId>.jsonl`). Transcripts reach tens of
/// megabytes, but every field a Recents row needs (ai-title, last-prompt, cwd)
/// sits in the first few KB — so only a bounded head is ever read. The format
/// is Claude Code's internal, unversioned format: every line is optional, and
/// a file with no parsable records still yields a row from its filename+mtime.
struct SessionIndex: Sendable {
    struct HeadMetadata: Equatable {
        var aiTitle: String?
        var lastPrompt: String?
        var cwd: String?
    }

    /// Newest transcripts per page; the view raises the limit via Load more.
    static let pageSize = 40
    // 256 KB: some transcripts open with multi-hundred-KB snapshot lines
    // before the title/cwd records; 64 KB missed them.
    private static let headByteLimit = 256 * 1024
    private static let headLineLimit = 200

    let rootURL: URL

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.rootURL = rootURL
    }

    // MARK: - Pure logic

    static func parseHead(_ lines: [String]) -> HeadMetadata {
        var meta = HeadMetadata()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if meta.aiTitle == nil, let title = record["aiTitle"] as? String, !title.isEmpty {
                meta.aiTitle = title
            }
            if meta.lastPrompt == nil, let prompt = record["lastPrompt"] as? String, !prompt.isEmpty {
                meta.lastPrompt = prompt
            }
            if meta.cwd == nil, let cwd = record["cwd"] as? String, !cwd.isEmpty {
                meta.cwd = cwd
            }
            if meta.aiTitle != nil, meta.lastPrompt != nil, meta.cwd != nil {
                break
            }
        }
        return meta
    }

    /// Live spool sessions never appear in Recents. Hook envelopes use the id
    /// form `claude-<sessionId>`; poller envelopes never match a transcript id.
    static func plan(
        candidates: [RecentSession],
        liveSessionIDs: Set<String>,
        limit: Int
    ) -> [RecentSession] {
        candidates
            .filter { !liveSessionIDs.contains("claude-\($0.id)") && !liveSessionIDs.contains($0.id) }
            .sorted { $0.lastActive > $1.lastActive }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Scanning

    func scan(
        liveSessionIDs: Set<String>,
        limit: Int = SessionIndex.pageSize
    ) -> (sessions: [RecentSession], hasMore: Bool) {
        let fileManager = FileManager.default
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return ([], false)
        }

        var candidates: [(url: URL, mtime: Date)] = []
        for dir in projectDirs {
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                candidates.append((file, mtime))
            }
        }

        let sessions = candidates
            .sorted { $0.mtime > $1.mtime }
            .prefix(limit)
            .compactMap { candidate -> RecentSession? in
                let id = candidate.url.deletingPathExtension().lastPathComponent
                guard ResumeLauncher.isValidSessionID(id) else { return nil }
                let meta = Self.parseHead(Self.readHeadLines(of: candidate.url))
                let projectName = meta.cwd.map { ($0 as NSString).lastPathComponent }
                    ?? Self.readableSlug(candidate.url.deletingLastPathComponent().lastPathComponent)
                return RecentSession(
                    id: id,
                    title: meta.aiTitle ?? meta.lastPrompt ?? projectName,
                    projectName: projectName,
                    cwd: meta.cwd ?? NSHomeDirectory(),
                    lastActive: candidate.mtime
                )
            }

        return (
            Self.plan(candidates: sessions, liveSessionIDs: liveSessionIDs, limit: limit),
            candidates.count > limit
        )
    }

    /// Project directory slugs are cwd paths with "/" mangled to "-"
    /// ("-Users-Soren-Desktop-notch-hud"). The path can't be reconstructed
    /// reliably, but stripping the home-directory prefix makes the fallback
    /// label readable ("Desktop-notch-hud").
    static func readableSlug(_ slug: String) -> String {
        let homeSlug = NSHomeDirectory().replacingOccurrences(of: "/", with: "-")
        guard slug.hasPrefix("\(homeSlug)-") else { return slug }
        return String(slug.dropFirst(homeSlug.count + 1))
    }

    private static func readHeadLines(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headByteLimit),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(headLineLimit)
            .map(String.init)
    }
}
