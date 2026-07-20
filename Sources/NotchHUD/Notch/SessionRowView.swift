import SwiftUI

enum SessionRowFeedback: Equatable {
    case permissionDenied
    case notFound
}

struct SessionRowView: View {
    let session: Session
    let feedback: SessionRowFeedback?
    let onSelect: (Session) -> Void
    let onGrantAccess: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onSelect(session)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(session.displayStatus.color)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(Text(session.displayStatus.label))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.project)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let detail = session.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .help("Raise this session's terminal")

            if feedback == .permissionDenied {
                Button(action: onGrantAccess) {
                    Label("Grant access", systemImage: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Open Automation privacy settings")
            } else if feedback == .notFound {
                Text("Window not found")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 32)
        .background(.white.opacity(isHovering ? 0.11 : 0.045))
        .clipShape(.rect(cornerRadius: 8))
        .onHover { isHovering = $0 }
    }
}
