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

@MainActor
enum SystemActions {
    private static var desktopHiddenProcessIdentifiers: [pid_t] = []
    private static var desktopPreviouslyActiveProcessIdentifier: pid_t?
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

    static func openWeather() {
        openApplication(at: "/System/Applications/Weather.app")
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
        if !desktopHiddenProcessIdentifiers.isEmpty {
            restoreDesktopIfNeeded()
            return
        }

        let applications = workspace.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != "com.apple.finder"
                && !$0.isHidden
        }
        desktopHiddenProcessIdentifiers = applications.map(\.processIdentifier)
        desktopPreviouslyActiveProcessIdentifier = applications.first(where: \.isActive)?
            .processIdentifier
        applications.forEach { $0.hide() }
        workspace.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.finder" })?
            .activate(options: [.activateAllWindows])
    }

    static func restoreDesktopIfNeeded() {
        guard !desktopHiddenProcessIdentifiers.isEmpty else { return }
        let workspace = NSWorkspace.shared
        let identifiers = Set(desktopHiddenProcessIdentifiers)
        let applications = workspace.runningApplications.filter {
            identifiers.contains($0.processIdentifier)
        }
        applications.forEach { $0.unhide() }
        if let previousPID = desktopPreviouslyActiveProcessIdentifier,
           let previousApplication = applications.first(where: {
               $0.processIdentifier == previousPID
           }) {
            previousApplication.activate(options: [.activateAllWindows])
        }
        desktopHiddenProcessIdentifiers = []
        desktopPreviouslyActiveProcessIdentifier = nil
    }

    static func performPowerAction(_ action: PowerAction) {
        switch action {
        case .lock:
            lockScreen()
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

    private static func lockScreen() {
        // Control-Command-Q is macOS's system Lock Screen shortcut. Posting it
        // through CoreGraphics avoids an Automation permission request for
        // System Events and actually locks the session instead of only turning
        // off the display.
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 12,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 12,
                keyDown: false
              )
        else { return }
        let flags: CGEventFlags = [.maskControl, .maskCommand]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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
