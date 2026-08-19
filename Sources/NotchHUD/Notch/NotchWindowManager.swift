import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    enum ExpansionReason: String {
        case hover
        case pending
        case manual
    }

    /// Panel-level state SwiftUI needs to observe (pin keeps the expanded
    /// panel open across hover exits until the user unpins; ghosted hides the
    /// resting pill while leaving hover armed).
    @Observable
    final class PanelPrefs {
        var pinned = false
        var ghosted = UserDefaults.standard.bool(forKey: NotchWindowManager.ghostDefaultsKey)
    }

    let panelPrefs = PanelPrefs()

    /// Ghost mode: the resting pill is invisible so it never covers screen
    /// content, but the hover region stays armed — hovering the notch area
    /// still drops the panel. Persisted across launches.
    static let ghostDefaultsKey = "pillGhosted"
    var isGhosted: Bool { panelPrefs.ghosted }

    func setGhosted(_ ghosted: Bool) {
        panelPrefs.ghosted = ghosted
        UserDefaults.standard.set(ghosted, forKey: Self.ghostDefaultsKey)
        applyGhostState()
    }

    /// The pill window must come back whenever the panel is expanded —
    /// otherwise a ghosted notch would drop an invisible backdrop on hover.
    private func applyGhostState() {
        let alpha: CGFloat = (isGhosted && !isExpanded) ? 0 : 1
        notchedHUD?.windowController?.window?.alphaValue = alpha
        floatingPeek?.windowController?.window?.alphaValue = alpha
    }

    func togglePanelPinned() {
        panelPrefs.pinned.toggle()
        if !panelPrefs.pinned, !containsExpandedContent(at: NSEvent.mouseLocation) {
            collapse(reason: .manual)
        }
    }

    private typealias NotchedHUD = DynamicNotch<EmptyView, NotchPeekView, NotchPeekTrailingView>
    private typealias FloatingPeek = DynamicNotch<NotchFloatingPeekView, EmptyView, EmptyView>

    private let environment: AppEnvironment
    private let store: SessionStore
    private let pendingStore: PendingStore
    private let usageProvider: UsageProvider
    private let focusDispatcher: FocusDispatcher
    private let decisionWriter: ApprovalDecisionWriter
    private var hoverController: HoverController?
    private var selectedScreen: NSScreen?
    private var notchedHUD: NotchedHUD?
    private var floatingPeek: FloatingPeek?
    private var interactivePanel: InteractiveNotchPanel?
    private var panelHostingView: NSHostingView<NotchPanelView>?
    private var transitionTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var globalMouseDownMonitor: Any?
    private var localEventMonitor: Any?
    private var transitionGeneration = 0
    private var renderedPanelSize: CGSize?
    private var pendingAutoExpandActive = false
    private(set) var isExpanded = false
    private(set) var expansionReason: ExpansionReason?

    init(
        environment: AppEnvironment,
        store: SessionStore,
        pendingStore: PendingStore,
        usageProvider: UsageProvider,
        focusDispatcher: FocusDispatcher
    ) {
        self.environment = environment
        self.store = store
        self.pendingStore = pendingStore
        self.usageProvider = usageProvider
        self.focusDispatcher = focusDispatcher
        decisionWriter = ApprovalDecisionWriter(
            decisionsURL: environment.decisionsURL,
            sessionAllowURL: environment.sessionAllowURL
        )
    }

    func boot() {
        _ = environment.spoolURL
        _ = environment.pendingURL

        let hoverController = HoverController(delegate: self)
        self.hoverController = hoverController
        installInteractionMonitors()
        repinToBuiltInScreen()
    }

    func shutdown() {
        hoverController?.suspend()
        transitionTask?.cancel()
        watchdogTask?.cancel()
        removeInteractionMonitors()
        removeInteractivePanel()
    }

    /// Display transitions (lid open/close, plug/unplug) fire a burst of
    /// didChangeScreenParameters notifications, and mid-burst the screen list
    /// is transitional — the built-in can still be listed while dissolving.
    /// Two hard-won rules live here:
    /// 1. Serial + debounced: the new task JOINS the cancelled predecessor
    ///    (a cancelled task mid-expand still creates its window afterwards),
    ///    then waits out the burst before acting.
    /// 2. Final-state-driven: the target screen is computed AFTER the debounce,
    ///    never captured from the notification, and teardown closes windows
    ///    synchronously — animated hides during display churn orphan windows.
    func repinToBuiltInScreen() {
        hoverController?.suspend()
        resetExpansionState(reason: .manual)
        renderedPanelSize = nil

        transitionGeneration += 1
        let generation = transitionGeneration
        let previous = transitionTask
        previous?.cancel()
        transitionTask = Task { [weak self] in
            _ = await previous?.value
            guard let self, self.transitionGeneration == generation else { return }

            try? await Task.sleep(for: .milliseconds(400))
            guard self.transitionGeneration == generation else { return }

            self.clearNotches()
            self.closeOrphanedNotchWindows()

            guard let screen = self.preferredScreen() else {
                NSLog("NotchHUD could not find a screen to pin to.")
                return
            }
            self.selectedScreen = screen

            if screen.safeAreaInsets.top > 0 {
                await self.installNotchedHUD(on: screen, generation: generation)
            } else {
                NSLog("NotchHUD found no notched display; using a top-center floating pill.")
                await self.installFloatingHUD(on: screen, generation: generation)
            }
            self.applyGhostState()

            guard self.transitionGeneration == generation, !self.isExpanded else { return }
            self.closeOrphanedNotchWindows(keepingCurrent: true)
            self.installInteractivePanel()
            self.hoverController?.pin(to: screen)
            if self.pendingStore.hasPending {
                self.pendingAutoExpandActive = true
                self.expand(reason: .pending)
            } else {
                self.pendingAutoExpandActive = false
            }
        }
    }

    func applyPendingApprovals(_ approvals: [PendingApproval]) {
        let previouslyHadPending = pendingStore.hasPending
        pendingStore.apply(approvals)
        store.markPendingApprovals(sessionIDs: Set(approvals.map(\.sessionId)))
        handlePendingTransition(previouslyHadPending: previouslyHadPending)
    }

    private func approvalDidResolve(sessionID: String) {
        let previouslyHadPending = pendingStore.hasPending
        pendingStore.dismiss(sessionID: sessionID)
        store.markPendingApprovals(sessionIDs: Set(pendingStore.approvals.map(\.sessionId)))
        handlePendingTransition(previouslyHadPending: previouslyHadPending)
    }

    private func handlePendingTransition(previouslyHadPending: Bool) {
        if pendingStore.hasPending {
            pendingAutoExpandActive = true
            expand(reason: .pending)
            return
        }

        guard previouslyHadPending || pendingAutoExpandActive else { return }
        pendingAutoExpandActive = false
        if !containsExpandedContent(at: NSEvent.mouseLocation) {
            collapse(reason: .pending)
        }
    }

    func expand(reason: ExpansionReason) {
        HoverDiag.log(
            "expand(reason: \(reason.rawValue)) isExpanded=\(isExpanded) "
                + "selectedScreen=\(selectedScreen != nil) notchedHUD=\(notchedHUD != nil)"
        )
        guard !isExpanded, let screen = selectedScreen else { return }
        guard notchedHUD != nil || floatingPeek != nil else { return }

        isExpanded = true
        expansionReason = reason
        applyGhostState()
        startWatchdog()

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        showInteractivePanel()

        if let notchedHUD {
            configurePassThroughWindow(notchedHUD.windowController?.window)
            transitionTask = Task { [weak self, weak notchedHUD] in
                guard let self, let notchedHUD else { return }
                await notchedHUD.expand(on: screen)
                guard self.transitionGeneration == generation, self.isExpanded else { return }
                self.configurePassThroughWindow(notchedHUD.windowController?.window)
                self.showInteractivePanel()
            }
            return
        }

        guard let floatingPeek else { return }
        configurePassThroughWindow(floatingPeek.windowController?.window)
        transitionTask = Task { [weak self, weak floatingPeek] in
            guard let self, let floatingPeek else { return }
            await floatingPeek.hide()
            guard self.transitionGeneration == generation, self.isExpanded else { return }
            self.showInteractivePanel()
        }
    }

    func collapse(reason: ExpansionReason) {
        if reason == .hover, pendingAutoExpandActive, pendingStore.hasPending {
            HoverDiag.log("collapse(reason: hover) ignored while a pending card is showing")
            return
        }
        guard isExpanded else { return }

        HoverDiag.log("collapse(reason: \(reason.rawValue))")
        isExpanded = false
        expansionReason = nil
        applyGhostState()
        watchdogTask?.cancel()
        watchdogTask = nil
        interactivePanel?.orderOut(nil)

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        guard let screen = selectedScreen else { return }

        if let notchedHUD {
            configurePassThroughWindow(notchedHUD.windowController?.window)
            transitionTask = Task { [weak self, weak notchedHUD] in
                guard let self, let notchedHUD else { return }
                await notchedHUD.compact(on: screen)
                guard self.transitionGeneration == generation, !self.isExpanded else { return }
                self.configurePassThroughWindow(notchedHUD.windowController?.window)
                // The compact animation restores window alpha; re-ghost after
                // it finishes or the pill reappears despite ghost mode.
                self.applyGhostState()
            }
            return
        }

        guard let floatingPeek else { return }
        transitionTask = Task { [weak self, weak floatingPeek] in
            guard let self, let floatingPeek else { return }
            await floatingPeek.expand(on: screen)
            guard self.transitionGeneration == generation, !self.isExpanded else { return }
            self.configurePassThroughWindow(floatingPeek.windowController?.window)
            self.applyGhostState()
        }
    }

    func containsExpandedContent(at point: NSPoint) -> Bool {
        guard isExpanded, let panel = interactivePanel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    private func installNotchedHUD(on screen: NSScreen, generation: Int) async {
        let store = store
        let pendingStore = pendingStore
        let notch = NotchedHUD(
            hoverBehavior: [],
            style: .notch,
            expanded: { EmptyView() },
            compactLeading: { NotchPeekView(store: store, pendingStore: pendingStore) },
            compactTrailing: { NotchPeekTrailingView(store: store) }
        )
        notch.transitionConfiguration.skipIntermediateHides = true
        notchedHUD = notch

        await notch.compact(on: screen)
        guard transitionGeneration == generation, !isExpanded else { return }
        configurePassThroughWindow(notch.windowController?.window)
    }

    private func installFloatingHUD(on screen: NSScreen, generation: Int) async {
        let store = store
        let pendingStore = pendingStore
        let peek = FloatingPeek(
            hoverBehavior: [],
            style: .floating,
            expanded: { NotchFloatingPeekView(store: store, pendingStore: pendingStore) }
        )
        floatingPeek = peek

        await peek.expand(on: screen)
        guard transitionGeneration == generation, !isExpanded else { return }
        configurePassThroughWindow(peek.windowController?.window)
    }

    private func installInteractivePanel() {
        removeInteractivePanel()

        let store = store
        let pendingStore = pendingStore
        let focusDispatcher = focusDispatcher
        let decisionWriter = decisionWriter
        let rootView = NotchPanelView(
            store: store,
            pendingStore: pendingStore,
            usageProvider: usageProvider,
            focusDispatcher: focusDispatcher,
            decisionWriter: decisionWriter,
            panelPrefs: panelPrefs,
            onTogglePin: { [weak self] in
                self?.togglePanelPinned()
            },
            onToggleGhost: { [weak self] in
                guard let self else { return }
                self.setGhosted(!self.isGhosted)
            },
            onApprovalDismiss: { [weak self] sessionID in
                self?.approvalDidResolve(sessionID: sessionID)
            },
            onSizeChange: { [weak self] size in
                self?.updateRenderedPanelSize(size)
            }
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]

        let panel = InteractiveNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.onEscape = { [weak self] in
            self?.collapse(reason: .manual)
        }

        interactivePanel = panel
        panelHostingView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            updateRenderedPanelSize(fittingSize)
        }
    }

    private func showInteractivePanel() {
        guard isExpanded, let panel = interactivePanel else { return }

        if renderedPanelSize == nil, let hostingView = panelHostingView {
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            if fittingSize.width > 0, fittingSize.height > 0 {
                updateRenderedPanelSize(fittingSize)
            }
        }

        guard renderedPanelSize != nil else {
            // Never make an unmeasured (and potentially oversized) panel interactive.
            return
        }
        positionInteractivePanel()
        panel.makeKeyAndOrderFront(nil)
    }

    private func updateRenderedPanelSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        renderedPanelSize = CGSize(
            width: ceil(min(size.width, 720)),
            height: ceil(min(size.height, 560))
        )
        positionInteractivePanel()
        if isExpanded, interactivePanel?.isVisible != true {
            showInteractivePanel()
        }
    }

    private func positionInteractivePanel() {
        guard
            let panel = interactivePanel,
            let screen = selectedScreen,
            let panelSize = renderedPanelSize
        else {
            return
        }

        let notchBandHeight = max(
            screen.safeAreaInsets.top,
            screen.frame.maxY - screen.visibleFrame.maxY
        )
        let frame = NSRect(
            x: screen.frame.midX - (panelSize.width / 2),
            y: screen.frame.maxY - notchBandHeight - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func removeInteractivePanel() {
        interactivePanel?.onEscape = nil
        interactivePanel?.orderOut(nil)
        interactivePanel?.close()
        interactivePanel = nil
        panelHostingView = nil
    }

    private func configurePassThroughWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior.formUnion([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ])
    }

    private func installInteractionMonitors() {
        guard globalMouseDownMonitor == nil, localEventMonitor == nil else { return }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLeftMouseDown(at: NSEvent.mouseLocation)
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53, self.isExpanded {
                self.collapse(reason: .manual)
                return nil
            }
            if event.type == .leftMouseDown {
                self.handleLeftMouseDown(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func removeInteractionMonitors() {
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func handleLeftMouseDown(at point: NSPoint) {
        guard isExpanded, !containsExpandedContent(at: point) else { return }
        collapse(reason: .manual)
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            var lastPointerInsideTime = ProcessInfo.processInfo.systemUptime

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard let self, self.isExpanded else { return }

                let now = ProcessInfo.processInfo.systemUptime
                if self.containsExpandedContent(at: NSEvent.mouseLocation) {
                    lastPointerInsideTime = now
                } else if now - lastPointerInsideTime >= 120 {
                    NSLog(
                        "NotchHUD watchdog force-collapsed a panel left expanded "
                            + "for 120 seconds without the pointer inside."
                    )
                    self.collapse(reason: .manual)
                    return
                }
            }
        }
    }

    private func resetExpansionState(reason: ExpansionReason) {
        if isExpanded {
            HoverDiag.log("resetExpansionState(reason: \(reason.rawValue))")
        }
        isExpanded = false
        expansionReason = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        interactivePanel?.orderOut(nil)
    }

    private func hideEveryNotch() async {
        if let notchedHUD {
            await notchedHUD.hide()
        }
        if let floatingPeek {
            await floatingPeek.hide()
        }
    }

    private func clearNotches() {
        removeInteractivePanel()
        notchedHUD = nil
        floatingPeek = nil
    }

    /// Closes DynamicNotchKit panels that no live reference owns. After
    /// clearNotches() every legitimate reference is nil, so all kit panels are
    /// ghosts; with `keepingCurrent` the freshly installed HUD's window is
    /// spared and anything else (e.g. created by an interleaved task) goes.
    private func closeOrphanedNotchWindows(keepingCurrent: Bool = false) {
        let current: Set<NSWindow> = keepingCurrent
            ? Set([notchedHUD?.windowController?.window,
                   floatingPeek?.windowController?.window].compactMap { $0 })
            : []

        for window in NSApp.windows
        where String(describing: type(of: window)) == "DynamicNotchPanel"
            && !current.contains(window) {
            window.close()
        }
    }
}

extension NotchWindowManager: HoverControllerDelegate {
    func hoverControllerDidEnter(_ controller: HoverController) {
        expand(reason: .hover)
    }

    func hoverControllerDidExit(_ controller: HoverController) {
        guard !panelPrefs.pinned else { return }
        collapse(reason: .hover)
    }

    func hoverController(_ controller: HoverController, containsExpandedPoint point: NSPoint) -> Bool {
        containsExpandedContent(at: point)
    }
}

@MainActor
/// Hosting view that acts on the first click even when its panel is not key —
/// a floating approval card must respond immediately, never swallow a click to "focus".
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class InteractiveNotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
