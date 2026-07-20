import SwiftUI

struct NotchPeekView: View {
    let store: SessionStore

    var body: some View {
        HStack(spacing: 7) {
            Text("\(store.total)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()

            HStack(spacing: 4) {
                ForEach(statusDots, id: \.self) { status in
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.notchBackground)
        .clipShape(.rect(cornerRadius: 10))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var statusDots: [DisplayStatus] {
        var statuses: [DisplayStatus] = []
        for session in store.sessions where !statuses.contains(session.displayStatus) {
            statuses.append(session.displayStatus)
            if statuses.count == 3 {
                break
            }
        }
        return statuses
    }

    private var accessibilitySummary: String {
        let counts = store.counts
        return "\(store.total) active sessions, \(counts.working) working, \(counts.needsMe) need attention, \(counts.done) done"
    }
}

extension Color {
    static let notchBackground = Color(red: 0.04, green: 0.04, blue: 0.047)
}
