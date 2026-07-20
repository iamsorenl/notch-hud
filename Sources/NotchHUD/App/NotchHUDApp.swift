import AppKit
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
    private var focusDispatcher: FocusDispatcher?
    private var spoolWatcher: SpoolWatcher?
    private var windowManager: NotchWindowManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let environment = AppEnvironment()
        let sessionStore = SessionStore()
        let focusDispatcher = FocusDispatcher()
        let spoolWatcher = SpoolWatcher(spoolURL: environment.spoolURL, store: sessionStore)
        let windowManager = NotchWindowManager(
            environment: environment,
            store: sessionStore,
            focusDispatcher: focusDispatcher
        )
        self.environment = environment
        self.sessionStore = sessionStore
        self.focusDispatcher = focusDispatcher
        self.spoolWatcher = spoolWatcher
        self.windowManager = windowManager

        spoolWatcher.start()
        windowManager.boot()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        spoolWatcher?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        windowManager?.repinToBuiltInScreen()
    }
}
