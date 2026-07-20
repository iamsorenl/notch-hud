import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    private typealias NotchedHUD = DynamicNotch<NotchPanelView, NotchPeekView, EmptyView>
    private typealias FloatingPeek = DynamicNotch<NotchPeekView, EmptyView, EmptyView>
    private typealias FloatingPanel = DynamicNotch<NotchPanelView, EmptyView, EmptyView>

    private let environment: AppEnvironment
    private let store: SessionStore
    private let focusDispatcher: FocusDispatcher
    private var hoverController: HoverController?
    private var selectedScreen: NSScreen?
    private var notchedHUD: NotchedHUD?
    private var floatingPeek: FloatingPeek?
    private var floatingPanel: FloatingPanel?
    private var transitionTask: Task<Void, Never>?
    private var transitionGeneration = 0
    private(set) var isExpanded = false

    init(environment: AppEnvironment, store: SessionStore, focusDispatcher: FocusDispatcher) {
        self.environment = environment
        self.store = store
        self.focusDispatcher = focusDispatcher
    }

    func boot() {
        _ = environment.spoolURL

        let hoverController = HoverController(delegate: self)
        self.hoverController = hoverController
        repinToBuiltInScreen()
    }

    func repinToBuiltInScreen() {
        guard let screen = preferredScreen() else {
            NSLog("NotchHUD could not find a screen to pin to.")
            return
        }

        hoverController?.suspend()
        selectedScreen = screen
        isExpanded = false

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            await self.hideEveryNotch()
            guard self.transitionGeneration == generation else { return }

            self.clearNotches()
            if screen.safeAreaInsets.top > 0 {
                await self.installNotchedHUD(on: screen, generation: generation)
            } else {
                NSLog("NotchHUD found no notched display; using a top-center floating pill.")
                await self.installFloatingHUD(on: screen, generation: generation)
            }

            guard self.transitionGeneration == generation, !self.isExpanded else { return }
            self.hoverController?.pin(to: screen)
        }
    }

    func expand() {
        HoverDiag.log("expand() called isExpanded=\(isExpanded) selectedScreen=\(selectedScreen != nil) notchedHUD=\(notchedHUD != nil)")
        guard !isExpanded, let screen = selectedScreen else { return }
        guard notchedHUD != nil || (floatingPeek != nil && floatingPanel != nil) else { return }
        isExpanded = true

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()

        if let notchedHUD {
            configureWindow(notchedHUD.windowController?.window, ignoresMouseEvents: false)
            transitionTask = Task { [weak self, weak notchedHUD] in
                guard let self, let notchedHUD else { return }
                await notchedHUD.expand(on: screen)
                guard self.transitionGeneration == generation, self.isExpanded else { return }
                self.configureWindow(notchedHUD.windowController?.window, ignoresMouseEvents: false)
            }
            return
        }

        guard let floatingPeek, let floatingPanel else { return }
        transitionTask = Task { [weak self, weak floatingPeek, weak floatingPanel] in
            guard let self, let floatingPeek, let floatingPanel else { return }
            await floatingPeek.hide()
            guard self.transitionGeneration == generation, self.isExpanded else { return }
            await floatingPanel.expand(on: screen)
            guard self.transitionGeneration == generation, self.isExpanded else { return }
            self.configureWindow(floatingPanel.windowController?.window, ignoresMouseEvents: false)
        }
    }

    func collapse() {
        guard isExpanded, let screen = selectedScreen else { return }
        isExpanded = false

        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()

        if let notchedHUD {
            configureWindow(notchedHUD.windowController?.window, ignoresMouseEvents: true)
            transitionTask = Task { [weak self, weak notchedHUD] in
                guard let self, let notchedHUD else { return }
                await notchedHUD.compact(on: screen)
                guard self.transitionGeneration == generation, !self.isExpanded else { return }
                self.configureWindow(notchedHUD.windowController?.window, ignoresMouseEvents: true)
            }
            return
        }

        guard let floatingPeek, let floatingPanel else { return }
        configureWindow(floatingPanel.windowController?.window, ignoresMouseEvents: true)
        transitionTask = Task { [weak self, weak floatingPeek, weak floatingPanel] in
            guard let self, let floatingPeek, let floatingPanel else { return }
            await floatingPanel.hide()
            guard self.transitionGeneration == generation, !self.isExpanded else { return }
            await floatingPeek.expand(on: screen)
            guard self.transitionGeneration == generation, !self.isExpanded else { return }
            self.configureWindow(floatingPeek.windowController?.window, ignoresMouseEvents: true)
        }
    }

    func containsExpandedContent(at point: NSPoint) -> Bool {
        guard isExpanded, let screen = selectedScreen else { return false }

        let notchHeight = max(
            screen.safeAreaInsets.top,
            screen.frame.maxY - screen.visibleFrame.maxY
        )
        let width: CGFloat = 370
        let height: CGFloat = 230
        let contentRect = NotchGeometry.expandedContentRect(
            frameMidX: screen.frame.midX,
            frameMaxY: screen.frame.maxY,
            notchHeight: notchHeight,
            width: width,
            height: height
        )
        return contentRect.contains(point)
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    private func installNotchedHUD(on screen: NSScreen, generation: Int) async {
        let store = store
        let focusDispatcher = focusDispatcher
        let notch = NotchedHUD(
            hoverBehavior: [],
            style: .notch,
            expanded: { NotchPanelView(store: store, focusDispatcher: focusDispatcher) },
            compactLeading: { NotchPeekView(store: store) },
            compactTrailing: { EmptyView() }
        )
        notchedHUD = notch

        await notch.compact(on: screen)
        guard transitionGeneration == generation, !isExpanded else { return }
        configureWindow(notch.windowController?.window, ignoresMouseEvents: true)
    }

    private func installFloatingHUD(on screen: NSScreen, generation: Int) async {
        let store = store
        let focusDispatcher = focusDispatcher
        let peek = FloatingPeek(
            hoverBehavior: [],
            style: .floating,
            expanded: { NotchPeekView(store: store) }
        )
        let panel = FloatingPanel(
            hoverBehavior: [],
            style: .floating,
            expanded: { NotchPanelView(store: store, focusDispatcher: focusDispatcher) }
        )
        floatingPeek = peek
        floatingPanel = panel

        await peek.expand(on: screen)
        guard transitionGeneration == generation, !isExpanded else { return }
        configureWindow(peek.windowController?.window, ignoresMouseEvents: true)
    }

    private func configureWindow(_ window: NSWindow?, ignoresMouseEvents: Bool) {
        guard let window else { return }
        window.ignoresMouseEvents = ignoresMouseEvents
        window.level = .screenSaver
        window.collectionBehavior.formUnion([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ])
    }

    private func hideEveryNotch() async {
        if let notchedHUD {
            await notchedHUD.hide()
        }
        if let floatingPeek {
            await floatingPeek.hide()
        }
        if let floatingPanel {
            await floatingPanel.hide()
        }
    }

    private func clearNotches() {
        notchedHUD = nil
        floatingPeek = nil
        floatingPanel = nil
    }
}

extension NotchWindowManager: HoverControllerDelegate {
    func hoverControllerDidEnter(_ controller: HoverController) {
        expand()
    }

    func hoverControllerDidExit(_ controller: HoverController) {
        collapse()
    }

    func hoverController(_ controller: HoverController, containsExpandedPoint point: NSPoint) -> Bool {
        containsExpandedContent(at: point)
    }
}
