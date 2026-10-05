import Combine
import Foundation
import ServiceManagement

@MainActor
final class PreferencesService: ObservableObject {
    static let minimumTaskbarIconSize = 26.0
    static let defaultTaskbarIconSize = 36.0
    static let maximumTaskbarIconSize = 56.0
    static let minimumNavigationIconSize = 12.0
    static let defaultNavigationIconSize = 16.0
    static let maximumNavigationIconSize = 28.0

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
    @Published var navigationIconSize: Double {
        didSet {
            let clamped = Self.clampNavigationIconSize(navigationIconSize)
            if clamped != navigationIconSize {
                navigationIconSize = clamped
                return
            }
            defaults.set(navigationIconSize, forKey: Keys.navigationIconSize)
        }
    }
    @Published var windowManagementEnabled: Bool {
        didSet { defaults.set(windowManagementEnabled, forKey: Keys.windowManagementEnabled) }
    }
    @Published var edgeSnappingEnabled: Bool {
        didSet { defaults.set(edgeSnappingEnabled, forKey: Keys.edgeSnappingEnabled) }
    }
    @Published var snapLayoutsEnabled: Bool {
        didSet { defaults.set(snapLayoutsEnabled, forKey: Keys.snapLayoutsEnabled) }
    }
    @Published var keyboardSnappingEnabled: Bool {
        didSet { defaults.set(keyboardSnappingEnabled, forKey: Keys.keyboardSnappingEnabled) }
    }
    @Published var snapActivationDistance: Double {
        didSet {
            let clamped = min(max(snapActivationDistance, 6), 32)
            if clamped != snapActivationDistance {
                snapActivationDistance = clamped
                return
            }
            defaults.set(snapActivationDistance, forKey: Keys.snapActivationDistance)
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
            Keys.taskbarIconSize: Self.defaultTaskbarIconSize,
            Keys.navigationIconSize: Self.defaultNavigationIconSize,
            Keys.windowManagementEnabled: true,
            Keys.edgeSnappingEnabled: true,
            Keys.snapLayoutsEnabled: true,
            Keys.keyboardSnappingEnabled: true,
            Keys.snapActivationDistance: 12.0
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
        navigationIconSize = Self.clampNavigationIconSize(
            defaults.double(forKey: Keys.navigationIconSize)
        )
        windowManagementEnabled = defaults.bool(forKey: Keys.windowManagementEnabled)
        edgeSnappingEnabled = defaults.bool(forKey: Keys.edgeSnappingEnabled)
        snapLayoutsEnabled = defaults.bool(forKey: Keys.snapLayoutsEnabled)
        keyboardSnappingEnabled = defaults.bool(forKey: Keys.keyboardSnappingEnabled)
        snapActivationDistance = min(max(
            defaults.double(forKey: Keys.snapActivationDistance),
            6
        ), 32)
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

    func resetNavigationIconSize() {
        navigationIconSize = Self.defaultNavigationIconSize
    }

    func resetWindowManagementSettings() {
        windowManagementEnabled = true
        edgeSnappingEnabled = true
        snapLayoutsEnabled = true
        keyboardSnappingEnabled = true
        snapActivationDistance = 12
    }

    static func clampTaskbarIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTaskbarIconSize }
        return min(max(value, minimumTaskbarIconSize), maximumTaskbarIconSize)
    }

    static func clampNavigationIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultNavigationIconSize }
        return min(max(value, minimumNavigationIconSize), maximumNavigationIconSize)
    }

    private enum Keys {
        static let hideMacDock = "WindowsTaskbar.HideMacDock"
        static let showOnAllDisplays = "WindowsTaskbar.ShowOnAllDisplays"
        static let taskbarIconSize = "WindowsTaskbar.TaskbarIconSize"
        static let taskbarIconSizeVersion = "WindowsTaskbar.TaskbarIconSizeVersion"
        static let navigationIconSize = "WindowsTaskbar.NavigationIconSize"
        static let hasCompletedOnboarding = "WindowsTaskbar.HasCompletedOnboarding"
        static let windowManagementEnabled = "WindowsTaskbar.WindowManagementEnabled"
        static let edgeSnappingEnabled = "WindowsTaskbar.EdgeSnappingEnabled"
        static let snapLayoutsEnabled = "WindowsTaskbar.SnapLayoutsEnabled"
        static let keyboardSnappingEnabled = "WindowsTaskbar.KeyboardSnappingEnabled"
        static let snapActivationDistance = "WindowsTaskbar.SnapActivationDistance"
    }
}
