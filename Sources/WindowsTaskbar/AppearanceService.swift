import AppKit
import Combine
import Foundation

@MainActor
final class AppearanceService: ObservableObject {
    @Published private(set) var isDarkMode = false

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func toggleDarkMode() {
        let source = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("Unable to toggle appearance: \(error)")
        } else {
            isDarkMode.toggle()
        }
    }

    func refresh() {
        isDarkMode = NSApp.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
    }
}
