import AppKit
import SwiftUI

/// The Recents section of the expanded panel: recent finished Claude Code
/// conversations with a filter-chip row (All · per-project · +N overflow).
/// Clicking a row resumes that conversation in a new Terminal tab; if
/// Terminal automation is denied, the resume command is copied to the
/// clipboard instead so it stays one paste away.
struct RecentsSectionView: View {
    let index: SessionIndex
    let liveSessionIDs: Set<String>
    let onGrantAccess: () -> Void

    @State private var recents: [RecentSession] = []
    @State private var selectedProject: String?
    @State private var feedback: [String: Feedback] = [:]

    enum Feedback: Equatable {
        case permissionDenied
        case copied
    }

    private static let rowLimit = 20
    private static let inlineChipLimit = 3

    private var projects: [String] {
        var seen = Set<String>()
        return recents.compactMap { session in
            seen.insert(session.projectName).inserted ? session.projectName : nil
        }
    }

    private var visibleRecents: [RecentSession] {
        let filtered = selectedProject.map { project in
            recents.filter { $0.projectName == project }
        } ?? recents
        return Array(filtered.prefix(Self.rowLimit))
    }

    var body: some View {
        // The scan trigger must live OUTSIDE any emptiness check: gating the
        // whole body on `!recents.isEmpty` would unmount the trigger and the
        // list could never populate.
        VStack(alignment: .leading, spacing: 6) {
            if recents.isEmpty {
                Text("No recent sessions")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            } else {
                filterChips
                ForEach(visibleRecents) { session in
                    RecentSessionRowView(
                        session: session,
                        feedback: feedback[session.id],
                        onSelect: resume,
                        onGrantAccess: onGrantAccess
                    )
                }
            }
        }
        .onChange(of: liveSessionIDs, initial: true) { _, live in
            recents = index.scan(liveSessionIDs: live)
        }
        .onDisappear {
            selectedProject = nil
        }
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            Text("Recents")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))

            chip("All", isSelected: selectedProject == nil) {
                selectedProject = nil
            }
            ForEach(projects.prefix(Self.inlineChipLimit), id: \.self) { project in
                chip(project, isSelected: selectedProject == project) {
                    selectedProject = selectedProject == project ? nil : project
                }
            }
            if projects.count > Self.inlineChipLimit {
                Menu {
                    ForEach(projects.dropFirst(Self.inlineChipLimit), id: \.self) { project in
                        Button(project) { selectedProject = project }
                    }
                } label: {
                    chipLabel(
                        "+\(projects.count - Self.inlineChipLimit)",
                        isSelected: selectedProject.map {
                            projects.dropFirst(Self.inlineChipLimit).contains($0)
                        } ?? false
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Spacer()
        }
    }

    private func chip(
        _ label: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            chipLabel(label, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(isSelected ? 0.14 : 0.05))
            .clipShape(.capsule)
    }

    private func resume(_ session: RecentSession) {
        feedback[session.id] = nil
        do {
            try ResumeLauncher.resume(session)
        } catch {
            guard let command = ResumeLauncher.command(for: session) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            let value: Feedback = if case FocusError.permissionDenied = error {
                .permissionDenied
            } else {
                .copied
            }
            show(value, for: session.id)
        }
    }

    private func show(_ value: Feedback, for sessionID: String) {
        feedback[sessionID] = value

        Task {
            try? await Task.sleep(for: .seconds(value == .permissionDenied ? 10 : 3))
            if feedback[sessionID] == value {
                feedback[sessionID] = nil
            }
        }
    }
}
