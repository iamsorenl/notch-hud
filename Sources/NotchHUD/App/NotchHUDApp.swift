import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
@MainActor
struct NotchHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var sessionStore: SessionStore?
    private var pendingStore: PendingStore?
    private var focusDispatcher: FocusDispatcher?
    private var spoolWatcher: SpoolWatcher?
    private var pendingWatcher: PendingWatcher?
    private var stalenessSweeper: StalenessSweeper?
    private var processPoller: ProcessPoller?
    private var usageProvider: UsageProvider?
    private var windowManager: NotchWindowManager?
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let environment = AppEnvironment()
        let sessionStore = SessionStore()
        let pendingStore = PendingStore()
        let focusDispatcher = FocusDispatcher()
        let spoolWatcher = SpoolWatcher(spoolURL: environment.spoolURL, store: sessionStore)
        let stalenessSweeper = StalenessSweeper(
            spoolURL: environment.spoolURL,
            store: sessionStore,
            workingStaleSeconds: environment.workingStaleSeconds,
            dropSeconds: environment.dropSeconds
        )
        let processPoller = ProcessPoller(spoolURL: environment.spoolURL)
        let usageProvider = UsageProvider()
        let windowManager = NotchWindowManager(
            environment: environment,
            store: sessionStore,
            pendingStore: pendingStore,
            usageProvider: usageProvider,
            focusDispatcher: focusDispatcher
        )
        let pendingWatcher = PendingWatcher(pendingURL: environment.pendingURL) {
            [weak windowManager] approvals in
            windowManager?.applyPendingApprovals(approvals)
        }
        self.environment = environment
        self.sessionStore = sessionStore
        self.pendingStore = pendingStore
        self.focusDispatcher = focusDispatcher
        self.spoolWatcher = spoolWatcher
        self.pendingWatcher = pendingWatcher
        self.stalenessSweeper = stalenessSweeper
        self.processPoller = processPoller
        self.usageProvider = usageProvider
        self.windowManager = windowManager

        spoolWatcher.start()
        pendingWatcher.start()
        stalenessSweeper.start()
        processPoller.start()
        usageProvider.start()
        windowManager.boot()
        installStatusItem()
        // ⌃⌥⌘N toggles the panel. Plain ⌘N is "New" in every app and a global
        // hotkey would steal it system-wide, so the chord adds ⌃⌥.
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ) { [weak windowManager] in
            windowManager?.togglePanel()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.shutdown()
        usageProvider?.stop()
        processPoller?.stop()
        stalenessSweeper?.stop()
        pendingWatcher?.stop()
        spoolWatcher?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func toggleGhost(_ sender: NSMenuItem) {
        let ghosted = !(windowManager?.isGhosted ?? false)
        windowManager?.setGhosted(ghosted)
        sender.state = ghosted ? .on : .off
    }

    @objc
    private func toggleKeyboardOnly(_ sender: NSMenuItem) {
        let keyboardOnly = !(windowManager?.isKeyboardOnly ?? false)
        windowManager?.setKeyboardOnly(keyboardOnly)
        sender.state = keyboardOnly ? .on : .off
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        windowManager?.repinToBuiltInScreen()
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "NotchHUD"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "NotchHUD"
        }

        let menu = NSMenu()
        let ghostItem = NSMenuItem(
            title: "Hide notch (hover still works)",
            action: #selector(toggleGhost(_:)),
            keyEquivalent: ""
        )
        ghostItem.target = self
        ghostItem.state = (windowManager?.isGhosted ?? false) ? .on : .off
        menu.addItem(ghostItem)

        let keyboardOnlyItem = NSMenuItem(
            title: "Open only with ⌃⌥⌘N",
            action: #selector(toggleKeyboardOnly(_:)),
            keyEquivalent: ""
        )
        keyboardOnlyItem.target = self
        keyboardOnlyItem.state = (windowManager?.isKeyboardOnly ?? false) ? .on : .off
        menu.addItem(keyboardOnlyItem)

        let pauseItem = NSMenuItem(
            title: "Pause approvals",
            action: #selector(togglePauseApprovals(_:)),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.state = approvalsAreEnabled ? .off : .on
        menu.addItem(pauseItem)

        let toggleItem = NSMenuItem(
            title: "Toggle panel",
            action: #selector(togglePanel(_:)),
            keyEquivalent: "n"
        )
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit NotchHUD",
            action: #selector(quitNotchHUD(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc
    private func togglePauseApprovals(_ sender: NSMenuItem) {
        let shouldPause = sender.state != .on
        guard writeApprovalsEnabled(!shouldPause) else { return }
        sender.state = shouldPause ? .on : .off
        if shouldPause {
            windowManager?.collapse(reason: .manual)
        }
    }

    @objc
    private func togglePanel(_ sender: NSMenuItem) {
        windowManager?.togglePanel()
    }

    @objc
    private func quitNotchHUD(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private var approvalsAreEnabled: Bool {
        guard let configURL = environment?.configURL,
              let data = try? Data(contentsOf: configURL),
              let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any]
        else {
            return false
        }
        return object["approvals"] as? Bool == true
    }

    private func writeApprovalsEnabled(_ enabled: Bool) -> Bool {
        guard let configURL = environment?.configURL else { return false }

        do {
            var config: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                config = existing
            }

            config["approvals"] = enabled
            var data = try JSONSerialization.data(
                withJSONObject: config,
                options: [.prettyPrinted, .sortedKeys]
            )
            data.append(0x0A)
            try data.write(to: configURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: configURL.path
            )
            return true
        } catch {
            NSLog(
                "NotchHUD could not update %@: %@",
                configURL.path,
                error.localizedDescription
            )
            return false
        }
    }
}
