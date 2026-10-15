import Combine
import Foundation
import ServiceManagement

enum StartMenuLogoStyle: String, CaseIterable, Identifiable {
    case apple
    case windows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .windows: return "Windows"
        }
    }
}

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
    @Published var startMenuLogoStyle: StartMenuLogoStyle {
        didSet { defaults.set(startMenuLogoStyle.rawValue, forKey: Keys.startMenuLogoStyle) }
    }
    @Published var showWeatherWidget: Bool {
        didSet { defaults.set(showWeatherWidget, forKey: Keys.showWeatherWidget) }
    }
    @Published var showSearchButton: Bool {
        didSet { defaults.set(showSearchButton, forKey: Keys.showSearchButton) }
    }
    @Published var showTaskViewButton: Bool {
        didSet { defaults.set(showTaskViewButton, forKey: Keys.showTaskViewButton) }
    }
    @Published var showQuickSettingsButton: Bool {
        didSet { defaults.set(showQuickSettingsButton, forKey: Keys.showQuickSettingsButton) }
    }
    @Published var showNetworkButton: Bool {
        didSet { defaults.set(showNetworkButton, forKey: Keys.showNetworkButton) }
    }
    @Published var showVolumeButton: Bool {
        didSet { defaults.set(showVolumeButton, forKey: Keys.showVolumeButton) }
    }
    @Published var showBatteryButton: Bool {
        didSet { defaults.set(showBatteryButton, forKey: Keys.showBatteryButton) }
    }
    @Published var showClock: Bool {
        didSet { defaults.set(showClock, forKey: Keys.showClock) }
    }
    @Published var showNotificationButton: Bool {
        didSet { defaults.set(showNotificationButton, forKey: Keys.showNotificationButton) }
    }
    @Published var showDesktopButton: Bool {
        didSet { defaults.set(showDesktopButton, forKey: Keys.showDesktopButton) }
    }
    @Published var windowPreviewsEnabled: Bool {
        didSet { defaults.set(windowPreviewsEnabled, forKey: Keys.windowPreviewsEnabled) }
    }
    @Published var windowsStyleControlsEnabled: Bool {
        didSet {
            defaults.set(windowsStyleControlsEnabled, forKey: Keys.windowsStyleControlsEnabled)
        }
    }
    @Published var windowControlsShowTitle: Bool {
        didSet { defaults.set(windowControlsShowTitle, forKey: Keys.windowControlsShowTitle) }
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
            Keys.startMenuLogoStyle: StartMenuLogoStyle.apple.rawValue,
            Keys.showWeatherWidget: true,
            Keys.showSearchButton: true,
            Keys.showTaskViewButton: true,
            Keys.showQuickSettingsButton: true,
            Keys.showNetworkButton: true,
            Keys.showVolumeButton: true,
            Keys.showBatteryButton: true,
            Keys.showClock: true,
            Keys.showNotificationButton: true,
            Keys.showDesktopButton: true,
            Keys.windowPreviewsEnabled: true,
            Keys.windowsStyleControlsEnabled: true,
            Keys.windowControlsShowTitle: true,
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
        startMenuLogoStyle = StartMenuLogoStyle(
            rawValue: defaults.string(forKey: Keys.startMenuLogoStyle) ?? ""
        ) ?? .apple
        showWeatherWidget = defaults.bool(forKey: Keys.showWeatherWidget)
        showSearchButton = defaults.bool(forKey: Keys.showSearchButton)
        showTaskViewButton = defaults.bool(forKey: Keys.showTaskViewButton)
        showQuickSettingsButton = defaults.bool(forKey: Keys.showQuickSettingsButton)
        showNetworkButton = defaults.bool(forKey: Keys.showNetworkButton)
        showVolumeButton = defaults.bool(forKey: Keys.showVolumeButton)
        showBatteryButton = defaults.bool(forKey: Keys.showBatteryButton)
        showClock = defaults.bool(forKey: Keys.showClock)
        showNotificationButton = defaults.bool(forKey: Keys.showNotificationButton)
        showDesktopButton = defaults.bool(forKey: Keys.showDesktopButton)
        windowPreviewsEnabled = defaults.bool(forKey: Keys.windowPreviewsEnabled)
        windowsStyleControlsEnabled = defaults.bool(forKey: Keys.windowsStyleControlsEnabled)
        windowControlsShowTitle = defaults.bool(forKey: Keys.windowControlsShowTitle)
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
        windowPreviewsEnabled = true
        windowsStyleControlsEnabled = true
        windowControlsShowTitle = true
        edgeSnappingEnabled = true
        snapLayoutsEnabled = true
        keyboardSnappingEnabled = true
        snapActivationDistance = 12
    }

    func resetTaskbarItems() {
        showWeatherWidget = true
        showSearchButton = true
        showTaskViewButton = true
        showQuickSettingsButton = true
        showNetworkButton = true
        showVolumeButton = true
        showBatteryButton = true
        showClock = true
        showNotificationButton = true
        showDesktopButton = true
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
        static let startMenuLogoStyle = "WindowsTaskbar.StartMenuLogoStyle"
        static let showWeatherWidget = "WindowsTaskbar.ShowWeatherWidget"
        static let showSearchButton = "WindowsTaskbar.ShowSearchButton"
        static let showTaskViewButton = "WindowsTaskbar.ShowTaskViewButton"
        static let showQuickSettingsButton = "WindowsTaskbar.ShowQuickSettingsButton"
        static let showNetworkButton = "WindowsTaskbar.ShowNetworkButton"
        static let showVolumeButton = "WindowsTaskbar.ShowVolumeButton"
        static let showBatteryButton = "WindowsTaskbar.ShowBatteryButton"
        static let showClock = "WindowsTaskbar.ShowClock"
        static let showNotificationButton = "WindowsTaskbar.ShowNotificationButton"
        static let showDesktopButton = "WindowsTaskbar.ShowDesktopButton"
        static let windowPreviewsEnabled = "WindowsTaskbar.WindowPreviewsEnabled"
        static let windowsStyleControlsEnabled = "WindowsTaskbar.WindowsStyleControlsEnabled"
        static let windowControlsShowTitle = "WindowsTaskbar.WindowControlsShowTitle"
        static let hasCompletedOnboarding = "WindowsTaskbar.HasCompletedOnboarding"
        static let windowManagementEnabled = "WindowsTaskbar.WindowManagementEnabled"
        static let edgeSnappingEnabled = "WindowsTaskbar.EdgeSnappingEnabled"
        static let snapLayoutsEnabled = "WindowsTaskbar.SnapLayoutsEnabled"
        static let keyboardSnappingEnabled = "WindowsTaskbar.KeyboardSnappingEnabled"
        static let snapActivationDistance = "WindowsTaskbar.SnapActivationDistance"
    }
}
