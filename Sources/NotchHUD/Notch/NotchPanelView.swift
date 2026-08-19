import AppKit
import SwiftUI

struct NotchPanelView: View {
    let store: SessionStore
    let pendingStore: PendingStore
    let usageProvider: UsageProvider
    let focusDispatcher: FocusDispatcher
    let decisionWriter: ApprovalDecisionWriter
    let panelPrefs: NotchWindowManager.PanelPrefs
    let onTogglePin: @MainActor () -> Void
    let onToggleGhost: @MainActor () -> Void
    let onApprovalDismiss: @MainActor (String) -> Void
    let onSizeChange: @MainActor (CGSize) -> Void

    @State private var feedback: [String: SessionRowFeedback] = [:]
    @State private var sessionListHeight: CGFloat?
    @State private var recentsListHeight: CGFloat?
    @State private var panelTab: PanelTab = .live

    enum PanelTab {
        case live
        case resume
    }

    private let sessionIndex = SessionIndex()

    private let maximumPanelHeight: CGFloat = 520
    private var maximumSessionListHeight: CGFloat {
        // Budget: panel max (520) minus header, tab strip, and paddings —
        // otherwise the list's last row clips under the bottom rounding.
        pendingStore.hasPending ? 175 : 434
    }

    private let panelShape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: 22,
            bottomTrailing: 22,
            topTrailing: 0
        ),
        style: .continuous
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let approval = pendingStore.current {
                ApprovalCardView(
                    approval: approval,
                    decisionWriter: decisionWriter,
                    onDismiss: onApprovalDismiss
                )
            }

            tabStrip

            TimelineView(.periodic(from: .now, by: 30)) { context in
                if panelTab == .resume {
                    ScrollView(.vertical) {
                        RecentsSectionView(
                            index: sessionIndex,
                            liveSessionIDs: Set(store.sessions.map(\.id)),
                            onGrantAccess: openAutomationSettings
                        )
                        .frame(maxWidth: .infinity)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        recentsListHeight = proxy.size.height
                                    }
                                    .onChange(of: proxy.size.height) { _, height in
                                        recentsListHeight = height
                                    }
                            }
                        }
                    }
                    .frame(
                        height: min(
                            recentsListHeight ?? maximumSessionListHeight,
                            maximumSessionListHeight
                        )
                    )
                } else if store.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(store.sessions) { session in
                                SessionRowView(
                                    session: session,
                                    now: context.date,
                                    feedback: feedback[session.id],
                                    onSelect: focus,
                                    onGrantAccess: openAutomationSettings
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        sessionListHeight = proxy.size.height
                                    }
                                    .onChange(of: proxy.size.height) { _, height in
                                        sessionListHeight = height
                                    }
                            }
                        }
                    }
                    .frame(
                        height: min(
                            sessionListHeight ?? maximumSessionListHeight,
                            maximumSessionListHeight
                        )
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(
            minWidth: 680,
            maxWidth: 680,
            maxHeight: maximumPanelHeight,
            alignment: .top
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.notchBackground.opacity(0.97))
        .clipShape(panelShape)
        .overlay {
            panelShape
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        onSizeChange(proxy.size)
                    }
                    .onChange(of: proxy.size) { _, size in
                        onSizeChange(size)
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 4) {
                summaryPart(store.counts.working, "working", color: DisplayStatus.working.color)
                summarySeparator
                summaryPart(store.counts.needsMe, "needs you", color: DisplayStatus.needsMe.color)
                summarySeparator
                summaryPart(store.counts.done, "done", color: DisplayStatus.done.color)
            }

            Spacer()

            if let usage = usageProvider.snapshot {
                HStack(spacing: 10) {
                    usageMeter("5h", usage.fiveHourPercent)
                    usageMeter("7d", usage.sevenDayPercent)
                }
                .padding(.trailing, 10)
                .accessibilityLabel("Claude usage")
            }

            Button {
                onTogglePin()
            } label: {
                Image(systemName: panelPrefs.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        panelPrefs.pinned
                            ? DisplayStatus.needsMe.color
                            : .white.opacity(0.5)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .help(panelPrefs.pinned ? "Unpin panel" : "Keep panel open")
            .accessibilityLabel(panelPrefs.pinned ? "Unpin panel" : "Pin panel open")

            Menu {
                Toggle(
                    "Hide notch (hover still works)",
                    isOn: Binding(
                        get: { panelPrefs.ghosted },
                        set: { _ in onToggleGhost() }
                    )
                )
                Button("Automation Settings…") { openAutomationSettings() }
                Divider()
                Button("Quit NotchHUD") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            tabButton("live", tab: .live)
            tabButton("resume", tab: .resume)
            Spacer()
        }
    }

    private func tabButton(_ label: String, tab: PanelTab) -> some View {
        Button {
            panelTab = tab
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(panelTab == tab ? 0.92 : 0.45))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.white.opacity(panelTab == tab ? 0.1 : 0))
                .clipShape(.rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func summaryPart(_ count: Int, _ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    @ViewBuilder
    private func usageMeter(_ label: String, _ percent: Int?) -> some View {
        if let percent {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(.white.opacity(0.4))
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: 28, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                percent >= 90
                                    ? DisplayStatus.needsMe.color
                                    : Color.white.opacity(0.6)
                            )
                            .frame(width: 28 * CGFloat(percent) / 100)
                    }
                Text("\(percent)%")
                    .foregroundStyle(.white.opacity(0.58))
                    .monospacedDigit()
            }
        }
    }

    private var summarySeparator: some View {
        Text("·")
            .foregroundStyle(.white.opacity(0.28))
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            AgentSprite(status: .idle, size: 18)
            Text("No active sessions")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
    }

    private func focus(_ session: Session) {
        guard session.terminal?.tty != nil else { return }
        feedback[session.id] = nil

        Task {
            switch await focusDispatcher.focus(session) {
            case .success:
                break
            case .failure(.permissionDenied):
                show(.permissionDenied, for: session.id, duration: .seconds(10))
            case .failure(.notFound), .failure(.scriptFailed):
                show(.notFound, for: session.id, duration: .seconds(2))
            }
        }
    }

    private func show(_ value: SessionRowFeedback, for sessionID: String, duration: Duration) {
        feedback[sessionID] = value

        Task {
            try? await Task.sleep(for: duration)
            if feedback[sessionID] == value {
                feedback[sessionID] = nil
            }
        }
    }

    private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
