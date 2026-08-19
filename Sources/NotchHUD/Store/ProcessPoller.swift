import Foundation

struct AgentProcess: Equatable, Sendable {
    let pid: Int
    let tty: String?
    let command: String
}

struct PollerCandidate: Equatable, Sendable {
    let pid: Int
    let agent: String
    let tty: String
}

/// Detects agent CLI processes that are not already reporting via hooks and
/// surfaces them through the spool, so SpoolWatcher/StalenessSweeper treat
/// them like any other session. Hook-reported sessions always win: a process
/// whose tty is claimed by a non-poller envelope is skipped, and poller
/// envelopes are removed once the process exits or a hook takes over.
@MainActor
final class ProcessPoller {
    nonisolated static let source = "process-poller"
    nonisolated static let agentNamePattern = "^(claude|codex|aider|goose|gemini|amp)$"
    private nonisolated static let interpreters: Set<String> = [
        "node", "bun", "deno", "env", "sh", "bash", "zsh", "python", "python3",
    ]

    private let spoolURL: URL
    private let fileManager: FileManager
    private let listProcesses: () -> [AgentProcess]
    private let lookupTermProgram: (Int) -> String?
    private var timer: Timer?

    init(
        spoolURL: URL,
        fileManager: FileManager = .default,
        listProcesses: @escaping () -> [AgentProcess] = ProcessPoller.listRunningProcesses,
        lookupTermProgram: @escaping (Int) -> String? = ProcessPoller.termProgram(forPID:)
    ) {
        self.spoolURL = spoolURL
        self.fileManager = fileManager
        self.listProcesses = listProcesses
        self.lookupTermProgram = lookupTermProgram
    }

    func start() {
        guard timer == nil else { return }

        poll()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Pure logic

    nonisolated static func agentName(forCommand command: String) -> String? {
        guard let regex = try? Regex(agentNamePattern) else { return nil }

        for token in command.split(separator: " ").prefix(4) {
            if token.contains("=") {
                continue
            }
            let basename = String(token.split(separator: "/").last ?? token)
            if basename.wholeMatch(of: regex) != nil {
                return basename
            }
            if !interpreters.contains(basename) {
                return nil
            }
        }
        return nil
    }

    nonisolated static func plan(
        processes: [AgentProcess],
        envelopes: [SessionEnvelope]
    ) -> (candidates: [PollerCandidate], removeIDs: [String]) {
        let hookTTYs = Set(
            envelopes
                .filter { $0.source != source }
                .compactMap { $0.terminal?.tty }
        )

        var candidates: [PollerCandidate] = []
        var claimedTTYs = Set<String>()
        for process in processes.sorted(by: { $0.pid < $1.pid }) {
            guard let tty = process.tty,
                  !hookTTYs.contains(tty),
                  !claimedTTYs.contains(tty),
                  let agent = agentName(forCommand: process.command)
            else {
                continue
            }
            claimedTTYs.insert(tty)
            candidates.append(PollerCandidate(pid: process.pid, agent: agent, tty: tty))
        }

        let candidatePIDs = Set(candidates.map(\.pid))
        let removeIDs = envelopes
            .filter { $0.source == source }
            .filter { envelope in
                envelope.pid.map { !candidatePIDs.contains($0) } ?? true
            }
            .map(\.id)

        return (candidates, removeIDs)
    }

    /// Extracts TERM_PROGRAM from `ps eww` output (environment appended to the
    /// command line). Focus strategies route on this, so a session without it
    /// cannot be raised by click-to-focus.
    nonisolated static func parseTermProgram(_ output: String) -> String? {
        for token in output.split(separator: " ") where token.hasPrefix("TERM_PROGRAM=") {
            let value = token.dropFirst("TERM_PROGRAM=".count)
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    nonisolated static func termProgram(forPID pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["eww", "-o", "command=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return parseTermProgram(output)
        } catch {
            return nil
        }
    }

    nonisolated static func parsePSOutput(_ output: String) -> [AgentProcess] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let pid = Int(fields[0]) else { return nil }
            let rawTTY = String(fields[1])
            let tty = rawTTY.hasPrefix("tty") ? "/dev/" + rawTTY : nil
            return AgentProcess(pid: pid, tty: tty, command: fields[2...].joined(separator: " "))
        }
    }

    // MARK: - Polling

    private func poll(now: Date = Date()) {
        let envelopes = readEnvelopes()
        let (candidates, removeIDs) = Self.plan(
            processes: listProcesses(),
            envelopes: envelopes
        )

        var envelopesByID: [String: SessionEnvelope] = [:]
        for envelope in envelopes where envelope.source == Self.source {
            envelopesByID[envelope.id] = envelope
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let updated = formatter.string(from: now)

        for candidate in candidates {
            let id = "poller-\(candidate.pid)"
            let existing = envelopesByID[id]
            let envelope = SessionEnvelope(
                schema: 1,
                id: id,
                agent: candidate.agent,
                pid: candidate.pid,
                project: candidate.agent,
                status: .unknown,
                updated: updated,
                started: existing?.started ?? updated,
                seq: (existing?.seq ?? 0) + 1,
                terminal: TerminalIdentity(
                    termProgram: existing?.terminal?.termProgram
                        ?? lookupTermProgram(candidate.pid),
                    tty: candidate.tty,
                    itermSessionId: nil,
                    weztermPane: nil,
                    kittyWindowId: nil,
                    windowId: nil
                ),
                source: Self.source
            )
            write(envelope)
        }

        for id in removeIDs {
            removeSpoolFile(for: id)
        }
    }

    private func readEnvelopes() -> [SessionEnvelope] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: spoolURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { fileURL in
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return try? JSONDecoder().decode(SessionEnvelope.self, from: data)
            }
    }

    private func write(_ envelope: SessionEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let fileURL = spoolURL.appendingPathComponent("\(envelope.id).json", isDirectory: false)
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func removeSpoolFile(for sessionID: String) {
        guard !sessionID.isEmpty,
              !sessionID.contains("/"),
              sessionID != ".",
              sessionID != ".."
        else {
            return
        }

        let fileURL = spoolURL.appendingPathComponent("\(sessionID).json", isDirectory: false)
        try? fileManager.removeItem(at: fileURL)
    }

    private nonisolated static func listRunningProcesses() -> [AgentProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,tty=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return parsePSOutput(output)
    }
}
