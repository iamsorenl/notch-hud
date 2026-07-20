import Foundation
import Testing
@testable import NotchHUD

@Test func spoolURLIsInHomeDirectory() {
    let environment = AppEnvironment()
    let spoolPath = environment.spoolURL.standardizedFileURL.path
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    #expect(spoolPath.hasSuffix("/.notch-hud/sessions"))
    #expect(spoolPath.hasPrefix(homePath + "/"))
}
