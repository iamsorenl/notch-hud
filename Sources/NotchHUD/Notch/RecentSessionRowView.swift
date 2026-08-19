import SwiftUI

/// One recent finished conversation: title · project · age. Deliberately more
/// muted than live SessionRowView cards so the live sessions stay dominant.
struct RecentSessionRowView: View {
    let session: RecentSession
    let feedback: RecentsSectionView.Feedback?
    let onSelect: (RecentSession) -> Void
    let onGrantAccess: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                onSelect(session)
            } label: {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(session.projectName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                    Text(Session.compactDuration(Date().timeIntervalSince(session.lastActive)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(isHovering ? 0.06 : 0.025))
                .clipShape(.rect(cornerRadius: 9))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Resume this conversation in Terminal")

            if feedback == .permissionDenied {
                HStack(spacing: 8) {
                    Text("Command copied — or grant access:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                    Button(action: onGrantAccess) {
                        Label("Grant Automation access", systemImage: "gearshape")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DisplayStatus.needsMe.color)
                    }
                    .buttonStyle(.plain)
                }
            } else if feedback == .copied {
                Text("Resume command copied to clipboard")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
