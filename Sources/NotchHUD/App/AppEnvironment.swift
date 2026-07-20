import Foundation

struct AppEnvironment {
    let spoolURL: URL
    let workingStaleSeconds: TimeInterval = 90
    let dropSeconds: TimeInterval = 900

    init(fileManager: FileManager = .default) {
        spoolURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch-hud", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: spoolURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: spoolURL.path
            )
        } catch {
            NSLog("NotchHUD could not prepare its session spool: %@", error.localizedDescription)
        }
    }
}
