import SwiftUI

struct NotchPeekView: View {
    let store: SessionStore

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(store.sessions.prefix(3))) { session in
                    AgentSprite(status: session.displayStatus, size: 12)
                }
            }

            if let compactStatus {
                Text(compactStatus.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(compactStatus.color)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var compactStatus: (label: String, color: Color)? {
        let counts = store.counts
        if counts.needsMe > 0 {
            return ("Needs you", DisplayStatus.needsMe.color)
        }
        if counts.working > 0 {
            return ("Working…", .white)
        }
        if store.total > 0, counts.done == store.total {
            return ("Done", DisplayStatus.done.color)
        }
        return nil
    }

    private var accessibilitySummary: String {
        let counts = store.counts
        return "\(store.total) active sessions, \(counts.working) working, \(counts.needsMe) need attention, \(counts.done) done"
    }
}

extension Color {
    static let notchBackground = Color(red: 0.078, green: 0.078, blue: 0.086)
}
