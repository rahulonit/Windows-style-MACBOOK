import Combine
import Foundation
import ServiceManagement

@MainActor
final class PreferencesService: ObservableObject {
    static let minimumTaskbarIconSize = 26.0
    static let defaultTaskbarIconSize = 36.0
    static let maximumTaskbarIconSize = 56.0

    @Published var hideMacDock: Bool {
        didSet { defaults.set(hideMacDock, forKey: Keys.hideMacDock) }
    }
    @Published var showOnAllDisplays: Bool {
        didSet { defaults.set(showOnAllDisplays, forKey: Keys.showOnAllDisplays) }
    }
    @Published var taskbarIconSize: Double {
        didSet {
            let clamped = Self.clampTaskbarIconSize(taskbarIconSize)
            if clamped != taskbarIconSize {
                taskbarIconSize = clamped
                return
            }
            defaults.set(taskbarIconSize, forKey: Keys.taskbarIconSize)
        }
    }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginItemError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.hideMacDock: true,
            Keys.showOnAllDisplays: true,
            Keys.taskbarIconSize: Self.defaultTaskbarIconSize
        ])
        hideMacDock = defaults.bool(forKey: Keys.hideMacDock)
        showOnAllDisplays = defaults.bool(forKey: Keys.showOnAllDisplays)
        if defaults.integer(forKey: Keys.taskbarIconSizeVersion) < 2 {
            taskbarIconSize = Self.defaultTaskbarIconSize
            defaults.set(2, forKey: Keys.taskbarIconSizeVersion)
        } else {
            taskbarIconSize = Self.clampTaskbarIconSize(
                defaults.double(forKey: Keys.taskbarIconSize)
            )
        }
        defaults.set(taskbarIconSize, forKey: Keys.taskbarIconSize)
        refreshLaunchAtLogin()
    }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Keys.hasCompletedOnboarding)
    }

    func resetOnboarding() {
        defaults.set(false, forKey: Keys.hasCompletedOnboarding)
    }

    func resetTaskbarIconSize() {
        taskbarIconSize = Self.defaultTaskbarIconSize
    }

    static func clampTaskbarIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTaskbarIconSize }
        return min(max(value, minimumTaskbarIconSize), maximumTaskbarIconSize)
    }

    private enum Keys {
        static let hideMacDock = "WindowsTaskbar.HideMacDock"
        static let showOnAllDisplays = "WindowsTaskbar.ShowOnAllDisplays"
        static let taskbarIconSize = "WindowsTaskbar.TaskbarIconSize"
        static let taskbarIconSizeVersion = "WindowsTaskbar.TaskbarIconSizeVersion"
        static let hasCompletedOnboarding = "WindowsTaskbar.HasCompletedOnboarding"
    }
}
