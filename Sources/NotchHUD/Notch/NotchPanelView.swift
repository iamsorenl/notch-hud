import AppKit
import SwiftUI

struct NotchPanelView: View {
    let store: SessionStore
    let focusDispatcher: FocusDispatcher

    @State private var feedback: [String: SessionRowFeedback] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(store.total)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }

            Divider()
                .overlay(.white.opacity(0.12))

            if store.sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
            } else {
                VStack(spacing: 5) {
                    ForEach(store.sessions) { session in
                        SessionRowView(
                            session: session,
                            feedback: feedback[session.id],
                            onSelect: focus,
                            onGrantAccess: openAutomationSettings
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Color.notchBackground)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func focus(_ session: Session) {
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
