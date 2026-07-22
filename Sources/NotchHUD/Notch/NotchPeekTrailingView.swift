import SwiftUI

struct NotchPeekTrailingView: View {
    let store: SessionStore

    var body: some View {
        if store.total > 0 {
            Text("\(store.total) sessions")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .monospacedDigit()
                .fixedSize()
        }
    }
}

struct NotchFloatingPeekView: View {
    let store: SessionStore
    let pendingStore: PendingStore

    var body: some View {
        HStack(spacing: 12) {
            NotchPeekView(store: store, pendingStore: pendingStore)
            NotchPeekTrailingView(store: store)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
