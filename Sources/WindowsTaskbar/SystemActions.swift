import AppKit

enum PowerAction: String, CaseIterable, Identifiable {
    case lock = "Lock"
    case sleep = "Sleep"
    case restart = "Restart"
    case shutDown = "Shut Down"
    case signOut = "Sign Out"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .lock: return "lock"
        case .sleep: return "moon.zzz"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .signOut: return "rectangle.portrait.and.arrow.right"
        }
    }
}

enum SystemActions {
    static func openApplications() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
    }

    static func openSpotlight() {
        openApplication(at: "/System/Library/CoreServices/Spotlight.app")
    }

    static func openMissionControl() {
        openApplication(at: "/System/Applications/Mission Control.app")
    }

    static func openControlCenter() {
        openApplication(at: "/System/Library/CoreServices/ControlCenter.app")
    }

    static func openNotificationCenter() {
        openApplication(at: "/System/Library/CoreServices/NotificationCenter.app")
    }

    static func openNetworkSettings() {
        openPreferencePane("/System/Library/PreferencePanes/Network.prefPane")
    }

    static func openSoundSettings() {
        openPreferencePane("/System/Library/PreferencePanes/Sound.prefPane")
    }

    static func openBatterySettings() {
        openPreferencePane("/System/Library/PreferencePanes/Battery.prefPane")
    }

    static func openDateAndTimeSettings() {
        openPreferencePane("/System/Library/PreferencePanes/DateAndTime.prefPane")
    }

    static func showDesktop() {
        let workspace = NSWorkspace.shared
        for application in workspace.runningApplications where
            application.activationPolicy == .regular && application.bundleIdentifier != "com.apple.finder" {
            application.hide()
        }
        workspace.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.finder" })?
            .activate(options: [.activateAllWindows])
    }

    static func performPowerAction(_ action: PowerAction) {
        switch action {
        case .lock:
            run("/usr/bin/pmset", ["displaysleepnow"])
        case .sleep:
            run("/usr/bin/pmset", ["sleepnow"])
        case .restart:
            run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"])
        case .shutDown:
            run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"])
        case .signOut:
            run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to log out"])
        }
    }

    private static func openApplication(at path: String) {
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("Unable to open \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private static func openPreferencePane(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private static func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            NSLog("Unable to run system action: \(error.localizedDescription)")
        }
    }
}
