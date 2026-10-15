import SwiftUI

enum TaskbarFlyout: Equatable {
    case start
    case overflow
    case accessibility
    case windowPreview
    case network
    case bluetooth
    case volume
    case battery
    case calendar
    case quickSettings
    case notificationCenter
    case settings
    case onboarding
}

struct SystemFlyoutView: View {
    let kind: TaskbarFlyout
    @ObservedObject var state: TaskbarState

    var body: some View {
        ZStack {
            VisualEffectView()
            Color(red: 0.07, green: 0.09, blue: 0.14).opacity(0.72)

            Group {
                switch kind {
                case .start:
                    StartMenuView(state: state)
                case .overflow:
                    OverflowAppsView(state: state)
                case .accessibility:
                    AccessibilityPermissionView(
                        state: state,
                        service: state.accessibilityService
                    )
                case .windowPreview:
                    WindowPreviewView(
                        state: state,
                        service: state.windowPreviewService
                    )
                case .network:
                    NetworkFlyout(service: state.networkService)
                case .bluetooth:
                    BluetoothFlyout(service: state.bluetoothService)
                case .volume:
                    VolumeFlyout(service: state.audioService)
                case .battery:
                    BatteryFlyout(service: state.batteryService)
                case .calendar:
                    CalendarFlyout(state: state)
                case .quickSettings:
                    QuickSettingsFlyout(state: state)
                case .notificationCenter:
                    NotificationCenterFlyout(
                        state: state,
                        service: state.notificationService
                    )
                case .settings:
                    SettingsFlyout(state: state, service: state.preferencesService)
                case .onboarding:
                    OnboardingFlyout(state: state, service: state.preferencesService)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: TaskbarTheme.flyoutCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TaskbarTheme.flyoutCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        }
        .preferredColorScheme(.dark)
    }
}

private struct OnboardingFlyout: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject var service: PreferencesService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 30))
                    .foregroundStyle(TaskbarTheme.activeIndicator)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Windows Taskbar")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Complete these steps for the full desktop experience.")
                        .foregroundStyle(.secondary)
                }
            }

            setupRow(
                title: "Window controls",
                detail: state.accessibilityService.isTrusted
                    ? "Accessibility access enabled"
                    : "Required for snapping, resizing, restoring, and closing windows",
                symbol: state.accessibilityService.isTrusted
                    ? "checkmark.circle.fill"
                    : "macwindow.badge.plus",
                isComplete: state.accessibilityService.isTrusted,
                buttonTitle: state.accessibilityService.isTrusted ? "Enabled" : "Allow"
            ) {
                state.requestAccessibilityPermission()
            }

            setupRow(
                title: "Nearby Wi-Fi",
                detail: state.networkService.permissionState == .authorized
                    ? "Location access enabled"
                    : "macOS requires Location access to show network names",
                symbol: state.networkService.permissionState == .authorized
                    ? "checkmark.circle.fill"
                    : "location.circle",
                isComplete: state.networkService.permissionState == .authorized,
                buttonTitle: state.networkService.permissionState == .authorized
                    ? "Enabled"
                    : "Allow"
            ) {
                state.networkService.requestPermissionAndScan()
            }

            preferenceToggle(
                title: "Launch at login",
                detail: "Start the taskbar automatically after you sign in.",
                isOn: Binding(
                    get: { service.launchAtLogin },
                    set: { service.setLaunchAtLogin($0) }
                )
            )

            preferenceToggle(
                title: "Hide the macOS Dock",
                detail: "Restore the Dock automatically when the taskbar exits.",
                isOn: $service.hideMacDock
            )

            if let error = service.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Spacer()

            HStack {
                Button("Open Privacy Settings") {
                    state.accessibilityService.openPrivacySettings()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Finish setup", action: state.completeOnboarding)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func setupRow(
        title: String,
        detail: String,
        symbol: String,
        isComplete: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(isComplete ? .green : TaskbarTheme.activeIndicator)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .disabled(isComplete)
        }
        .padding(11)
        .background(TaskbarTheme.hoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func preferenceToggle(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case personalization = "Personalization"
    case taskbar = "Taskbar items"
    case windows = "Window management"
    case system = "System behavior"
    case permissions = "Permissions"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .personalization: return "paintbrush.fill"
        case .taskbar: return "rectangle.bottomthird.inset.filled"
        case .windows: return "macwindow.on.rectangle"
        case .system: return "desktopcomputer"
        case .permissions: return "checkmark.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .personalization: return "Size and visual scale"
        case .taskbar: return "Choose what appears"
        case .windows: return "Controls, previews, and snapping"
        case .system: return "Dock, displays, and startup"
        case .permissions: return "Required macOS access"
        case .about: return "Version and capabilities"
        }
    }
}

@MainActor
private struct SettingsDraft: Equatable {
    var taskbarIconSize: Double
    var navigationIconSize: Double
    var startMenuLogoStyle: StartMenuLogoStyle
    var showWeatherWidget: Bool
    var showSearchButton: Bool
    var showTaskViewButton: Bool
    var showQuickSettingsButton: Bool
    var showNetworkButton: Bool
    var showVolumeButton: Bool
    var showBatteryButton: Bool
    var showClock: Bool
    var showNotificationButton: Bool
    var showDesktopButton: Bool
    var hideMacDock: Bool
    var showOnAllDisplays: Bool
    var launchAtLogin: Bool
    var windowManagementEnabled: Bool
    var windowsStyleControlsEnabled: Bool
    var windowControlsShowTitle: Bool
    var windowPreviewsEnabled: Bool
    var edgeSnappingEnabled: Bool
    var snapLayoutsEnabled: Bool
    var keyboardSnappingEnabled: Bool
    var snapActivationDistance: Double

    init(service: PreferencesService) {
        taskbarIconSize = service.taskbarIconSize
        navigationIconSize = service.navigationIconSize
        startMenuLogoStyle = service.startMenuLogoStyle
        showWeatherWidget = service.showWeatherWidget
        showSearchButton = service.showSearchButton
        showTaskViewButton = service.showTaskViewButton
        showQuickSettingsButton = service.showQuickSettingsButton
        showNetworkButton = service.showNetworkButton
        showVolumeButton = service.showVolumeButton
        showBatteryButton = service.showBatteryButton
        showClock = service.showClock
        showNotificationButton = service.showNotificationButton
        showDesktopButton = service.showDesktopButton
        hideMacDock = service.hideMacDock
        showOnAllDisplays = service.showOnAllDisplays
        launchAtLogin = service.launchAtLogin
        windowManagementEnabled = service.windowManagementEnabled
        windowsStyleControlsEnabled = service.windowsStyleControlsEnabled
        windowControlsShowTitle = service.windowControlsShowTitle
        windowPreviewsEnabled = service.windowPreviewsEnabled
        edgeSnappingEnabled = service.edgeSnappingEnabled
        snapLayoutsEnabled = service.snapLayoutsEnabled
        keyboardSnappingEnabled = service.keyboardSnappingEnabled
        snapActivationDistance = service.snapActivationDistance
    }

    mutating func resetTaskbarItems() {
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

    mutating func resetWindowManagement() {
        windowManagementEnabled = true
        windowsStyleControlsEnabled = true
        windowControlsShowTitle = true
        windowPreviewsEnabled = true
        edgeSnappingEnabled = true
        snapLayoutsEnabled = true
        keyboardSnappingEnabled = true
        snapActivationDistance = 12
    }

    func apply(to service: PreferencesService) {
        service.taskbarIconSize = taskbarIconSize
        service.navigationIconSize = navigationIconSize
        service.startMenuLogoStyle = startMenuLogoStyle
        service.showWeatherWidget = showWeatherWidget
        service.showSearchButton = showSearchButton
        service.showTaskViewButton = showTaskViewButton
        service.showQuickSettingsButton = showQuickSettingsButton
        service.showNetworkButton = showNetworkButton
        service.showVolumeButton = showVolumeButton
        service.showBatteryButton = showBatteryButton
        service.showClock = showClock
        service.showNotificationButton = showNotificationButton
        service.showDesktopButton = showDesktopButton
        service.hideMacDock = hideMacDock
        service.showOnAllDisplays = showOnAllDisplays
        if launchAtLogin != service.launchAtLogin {
            service.setLaunchAtLogin(launchAtLogin)
        }
        service.windowManagementEnabled = windowManagementEnabled
        service.windowsStyleControlsEnabled = windowsStyleControlsEnabled
        service.windowControlsShowTitle = windowControlsShowTitle
        service.windowPreviewsEnabled = windowPreviewsEnabled
        service.edgeSnappingEnabled = edgeSnappingEnabled
        service.snapLayoutsEnabled = snapLayoutsEnabled
        service.keyboardSnappingEnabled = keyboardSnappingEnabled
        service.snapActivationDistance = snapActivationDistance
    }
}

struct SettingsFlyout: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject var service: PreferencesService
    var showsHeader = true
    @State private var selectedCategory: SettingsCategory = .personalization
    @State private var draft: SettingsDraft
    @State private var showsSavedConfirmation = false

    init(
        state: TaskbarState,
        service: PreferencesService,
        showsHeader: Bool = true
    ) {
        self.state = state
        self.service = service
        self.showsHeader = showsHeader
        _draft = State(initialValue: SettingsDraft(service: service))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if showsHeader {
                    sidebarBrand
                }

                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(
                                    selectedCategory == category
                                        ? Color.white
                                        : Color.white.opacity(0.72)
                                )
                                .frame(width: 30, height: 30)
                                .background(
                                    selectedCategory == category
                                        ? Color.white.opacity(0.12)
                                        : Color.white.opacity(0.04)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(category.subtitle)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 54)
                        .background {
                            if selectedCategory == category {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                TaskbarTheme.accentPurple.opacity(0.38),
                                                TaskbarTheme.accentCyan.opacity(0.16)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                                    }
                            }
                        }
                        .overlay(alignment: .leading) {
                            if selectedCategory == category {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [TaskbarTheme.accentCyan, .white],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 3, height: 26)
                                    .shadow(color: TaskbarTheme.accentCyan.opacity(0.7), radius: 5)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Windows Skin Pack")
                        .font(.caption.weight(.semibold))
                    Text("Version \(appVersion)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSettingsCard(cornerRadius: 13)
            }
            .padding(14)
            .frame(width: 226)
            .background {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.16),
                        TaskbarTheme.accentPurple.opacity(0.06),
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 0.5)

            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                ScrollView {
                    categoryContent
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                }
            }
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 15) {
            Image(systemName: selectedCategory.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [TaskbarTheme.accentPurple, TaskbarTheme.accentCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: TaskbarTheme.accentPurple.opacity(0.35), radius: 14, y: 5)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedCategory.rawValue)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(selectedCategory.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedCategory == .taskbar {
                Button("Reset") { draft.resetTaskbarItems() }
                    .buttonStyle(.bordered)
            } else if selectedCategory == .windows {
                Button("Reset") { draft.resetWindowManagement() }
                    .buttonStyle(.bordered)
            }

            if showsSavedConfirmation {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Button(action: saveChanges) {
                Label("Save changes", systemImage: "checkmark")
            }
                .buttonStyle(.borderedProminent)
                .tint(TaskbarTheme.accentPurple)
                .controlSize(.large)
                .disabled(!hasPendingChanges)
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [TaskbarTheme.accentPurple, TaskbarTheme.accentCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("Skin Settings")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Make the desktop yours")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var categoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selectedCategory {
            case .personalization:
                startLogoSetting
                iconSizeSetting
                navigationIconSizeSetting
            case .taskbar:
                taskbarItemsPage
            case .windows:
                windowManagementPage
            case .system:
                systemBehaviorPage
            case .permissions:
                permissionsPage
            case .about:
                aboutPage
            }
        }
    }

    private var taskbarItemsPage: some View {
        VStack(spacing: 8) {
            settingRow(
                title: "Weather widget",
                detail: "Open Apple Weather from the left side of the taskbar.",
                isOn: $draft.showWeatherWidget
            )
            settingRow(
                title: "Search",
                detail: "Open Spotlight from a centered taskbar button.",
                isOn: $draft.showSearchButton
            )
            settingRow(
                title: "Task View",
                detail: "Open Mission Control to see all application windows.",
                isOn: $draft.showTaskViewButton
            )
            settingRow(
                title: "Quick settings",
                detail: "Show the system-control chevron in the notification area.",
                isOn: $draft.showQuickSettingsButton
            )
            settingRow(
                title: "Wi-Fi",
                detail: "Show network status and nearby Wi-Fi controls.",
                isOn: $draft.showNetworkButton
            )
            settingRow(
                title: "Sound",
                detail: "Show the current volume and audio controls.",
                isOn: $draft.showVolumeButton
            )
            settingRow(
                title: "Battery",
                detail: "Show charge, power source, health, and percentage.",
                isOn: $draft.showBatteryButton
            )
            settingRow(
                title: "Clock and calendar",
                detail: "Show the date, time, and Windows-style calendar.",
                isOn: $draft.showClock
            )
            settingRow(
                title: "Notifications",
                detail: "Show the notification bell and unread badge.",
                isOn: $draft.showNotificationButton
            )
            settingRow(
                title: "Show Desktop",
                detail: "Show the desktop target at the far-right edge.",
                isOn: $draft.showDesktopButton
            )
        }
    }

    private var windowManagementPage: some View {
        VStack(spacing: 8) {
            settingRow(
                title: "Enable window management",
                detail: "Keep windows above the taskbar and enable all controls below.",
                isOn: $draft.windowManagementEnabled
            )
            settingRow(
                title: "Windows-style window controls",
                detail: "Attach minimize, Snap Layouts, maximize/restore, and close controls.",
                isOn: $draft.windowsStyleControlsEnabled
            )
            .disabled(!draft.windowManagementEnabled)
            settingRow(
                title: "Show app title and icon",
                detail: "Include identity information in the active window control strip.",
                isOn: $draft.windowControlsShowTitle
            )
            .disabled(
                !draft.windowManagementEnabled || !draft.windowsStyleControlsEnabled
            )
            settingRow(
                title: "Grouped window previews",
                detail: "Show live thumbnails when an application has multiple windows.",
                isOn: $draft.windowPreviewsEnabled
            )
            .disabled(!draft.windowManagementEnabled)
            settingRow(
                title: "Snap at screen edges",
                detail: "Drag a title bar to an edge or corner to arrange the window.",
                isOn: $draft.edgeSnappingEnabled
            )
            .disabled(!draft.windowManagementEnabled)
            settingRow(
                title: "Snap Layouts",
                detail: "Display Windows-style layouts from the maximize controls.",
                isOn: $draft.snapLayoutsEnabled
            )
            .disabled(!draft.windowManagementEnabled)
            settingRow(
                title: "Keyboard snapping",
                detail: "Use Control–Option–Arrow; add Shift to move between displays.",
                isOn: $draft.keyboardSnappingEnabled
            )
            .disabled(!draft.windowManagementEnabled)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edge activation distance")
                            .font(.system(size: 13, weight: .semibold))
                        Text("How close a dragged window must be before snapping activates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(draft.snapActivationDistance.rounded())) pt")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                Slider(value: $draft.snapActivationDistance, in: 6...32, step: 1)
                    .disabled(
                        !draft.windowManagementEnabled || !draft.edgeSnappingEnabled
                    )
            }
            .padding(14)
            .glassSettingsCard(cornerRadius: 12)
        }
    }

    private var systemBehaviorPage: some View {
        VStack(spacing: 8) {
            settingRow(
                title: "Hide the macOS Dock",
                detail: "Restore the original Dock automatically when this app exits.",
                isOn: $draft.hideMacDock
            )
            settingRow(
                title: "Show on all displays",
                detail: "Display an independent taskbar on every connected screen.",
                isOn: $draft.showOnAllDisplays
            )
            settingRow(
                title: "Launch at login",
                detail: "Start Windows Skin Pack automatically after signing in.",
                isOn: Binding(
                    get: { draft.launchAtLogin },
                    set: { draft.launchAtLogin = $0 }
                )
            )
            if let error = service.loginItemError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 10) {
            permissionCard(
                title: "Accessibility",
                detail: "Required once for snapping, resizing, minimizing, restoring, and closing application windows.",
                symbol: "macwindow.badge.plus",
                enabled: state.accessibilityService.isTrusted,
                buttonTitle: "Review access"
            ) {
                state.accessibilityService.openPrivacySettings()
            }
            permissionCard(
                title: "Location for Wi-Fi",
                detail: "macOS requires location access before an app can display nearby network names.",
                symbol: "location.circle.fill",
                enabled: state.networkService.permissionState == .authorized,
                buttonTitle: "Request access"
            ) {
                state.networkService.requestPermissionAndScan()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup assistant")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Review the recommended permissions and startup options again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run setup again") {
                    service.resetOnboarding()
                    state.toggleFlyout(.onboarding)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .glassSettingsCard(cornerRadius: 12)
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [TaskbarTheme.accentPurple, TaskbarTheme.accentCyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(
                                color: TaskbarTheme.accentPurple.opacity(0.35),
                                radius: 16,
                                y: 6
                            )
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows Skin Pack")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("A native Windows-inspired desktop layer for macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                capabilityRow("Windows-style taskbar and Start menu", "checkmark.circle.fill")
                capabilityRow("App launching and grouped window previews", "checkmark.circle.fill")
                capabilityRow("Snap Layouts and keyboard window management", "checkmark.circle.fill")
                capabilityRow("Wi-Fi, sound, battery, calendar, and notifications", "checkmark.circle.fill")
                capabilityRow("Multi-display and full-screen behavior", "checkmark.circle.fill")
            }
            .padding(16)
            .glassSettingsCard()

            Text("Built with native AppKit and SwiftUI. Some system integrations require permission from macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hasPendingChanges: Bool {
        draft != SettingsDraft(service: service)
    }

    private func saveChanges() {
        draft.apply(to: service)
        state.refreshAfterSettingsChange()
        draft = SettingsDraft(service: service)
        withAnimation(.easeOut(duration: 0.16)) {
            showsSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.16)) {
                showsSavedConfirmation = false
            }
        }
    }

    private func permissionCard(
        title: String,
        detail: String,
        symbol: String,
        enabled: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(enabled ? .green : TaskbarTheme.activeIndicator)
                .frame(width: 42, height: 42)
                .background((enabled ? Color.green : TaskbarTheme.activeIndicator).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(enabled ? "Allowed" : "Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(enabled ? .green : .orange)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(enabled ? "Review" : buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .glassSettingsCard(cornerRadius: 12)
    }

    private func capabilityRow(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary, .green)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.3.2"
    }

    private func sectionHeader(
        _ title: String,
        symbol: String,
        resetAction: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if let resetAction {
                Button("Reset", action: resetAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.top, 2)
    }

    private var startLogoSetting: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start button logo")
                    .font(.system(size: 14, weight: .semibold))
                Text("Switch between the familiar Apple mark and a Windows-style Start logo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ForEach(StartMenuLogoStyle.allCases) { style in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            draft.startMenuLogoStyle = style
                        }
                    } label: {
                        HStack(spacing: 11) {
                            StartMenuLogoView(
                                style: style,
                                size: 28,
                                color: draft.startMenuLogoStyle == style
                                    ? .white
                                    : Color.white.opacity(0.72)
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(style == .apple ? "macOS identity" : "Windows Start")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: draft.startMenuLogoStyle == style
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(
                                    draft.startMenuLogoStyle == style
                                        ? TaskbarTheme.accentCyan
                                        : Color.white.opacity(0.24)
                                )
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    draft.startMenuLogoStyle == style
                                        ? TaskbarTheme.accentPurple.opacity(0.22)
                                        : Color.white.opacity(0.035)
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(
                                    draft.startMenuLogoStyle == style
                                        ? TaskbarTheme.accentCyan.opacity(0.68)
                                        : Color.white.opacity(0.08),
                                    lineWidth: draft.startMenuLogoStyle == style ? 1.2 : 0.7
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .glassSettingsCard()
    }

    private var iconSizeSetting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Taskbar icon size")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Application and navigation icons resize; Wi-Fi, volume, and battery stay at 20 pt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(draft.taskbarIconSize.formatted(.number.precision(.fractionLength(0...1))) + " pt")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Image(systemName: "app.fill")
                    .font(.system(size: 14))
                    .frame(width: 20)
                Slider(
                    value: $draft.taskbarIconSize,
                    in: PreferencesService.minimumTaskbarIconSize...PreferencesService.maximumTaskbarIconSize,
                    step: 0.5
                )
                Image(systemName: "app.fill")
                    .font(.system(size: 32))
                    .frame(width: 36)
            }

            HStack {
                HStack(spacing: 8) {
                    StartMenuLogoView(
                        style: draft.startMenuLogoStyle,
                        size: TaskbarTheme.startIconSize(
                            for: CGFloat(draft.taskbarIconSize)
                        )
                    )
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: TaskbarTheme.navigationIconSize(
                            for: CGFloat(draft.taskbarIconSize)
                        )))
                    Image(systemName: "wifi")
                        .font(.system(size: TaskbarTheme.systemTrayIconSize))
                }
                .frame(height: 34)
                Spacer()
                Button("Reset") {
                    draft.taskbarIconSize = PreferencesService.defaultTaskbarIconSize
                }
                    .buttonStyle(.bordered)
                    .disabled(
                        draft.taskbarIconSize
                            == PreferencesService.defaultTaskbarIconSize
                    )
            }
        }
        .padding(16)
        .glassSettingsCard()
    }

    private var navigationIconSizeSetting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search and Task View icon size")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Changes navigation icons independently from application icons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    draft.navigationIconSize.formatted(
                        .number.precision(.fractionLength(0...1))
                    ) + " pt"
                )
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .frame(width: 20)
                Slider(
                    value: $draft.navigationIconSize,
                    in: PreferencesService.minimumNavigationIconSize...PreferencesService.maximumNavigationIconSize,
                    step: 0.5
                )
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 26))
                    .frame(width: 32)
            }

            HStack {
                Text("Default: 16 pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    draft.navigationIconSize = PreferencesService.defaultNavigationIconSize
                }
                    .buttonStyle(.bordered)
                    .disabled(
                        draft.navigationIconSize
                            == PreferencesService.defaultNavigationIconSize
                    )
            }
        }
        .padding(16)
        .glassSettingsCard()
    }

    private func settingRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .glassSettingsCard(cornerRadius: 12)
    }

    private func permissionStatus(_ title: String, enabled: Bool) -> some View {
        Label(
            "\(title): \(enabled ? "Enabled" : "Not enabled")",
            systemImage: enabled ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(enabled ? .green : .secondary)
    }
}

private struct SettingsGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.105),
                                TaskbarTheme.accentPurple.opacity(0.055),
                                Color.white.opacity(0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.19),
                                TaskbarTheme.accentPurple.opacity(0.18),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    }
}

private extension View {
    func glassSettingsCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(SettingsGlassCardModifier(cornerRadius: cornerRadius))
    }
}

private struct NotificationCenterFlyout: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject var service: TaskbarNotificationService

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications")
                        .font(.system(size: 19, weight: .semibold))
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    state.perform(SystemActions.openNotificationCenter)
                } label: {
                    Label("macOS", systemImage: "macwindow")
                }
                .buttonStyle(.bordered)
                .help("Open macOS Notification Center")

                if !service.notifications.isEmpty {
                    Button("Clear all", action: service.clearAll)
                        .buttonStyle(.bordered)
                }
            }

            Group {
                if service.notifications.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text("No new notifications")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(service.notifications) { notification in
                                notificationCard(notification)
                            }
                        }
                    }
                    .frame(maxHeight: 245)
                }
            }

            Divider()

            Text("Widgets")
                .font(.system(size: 15, weight: .semibold))

            LazyVGrid(columns: columns, spacing: 10) {
                widgetCard(
                    title: "Wi-Fi",
                    value: state.networkService.statusText,
                    symbol: state.networkService.isPowered ? "wifi" : "wifi.slash"
                )
                widgetCard(
                    title: "Battery",
                    value: state.batteryService.percentage.map { "\($0)%" }
                        ?? "Not available",
                    symbol: state.batteryService.symbolName
                )
                widgetCard(
                    title: "Sound",
                    value: state.audioService.isMuted
                        ? "Muted"
                        : "\(Int((state.audioService.volume * 100).rounded()))%",
                    symbol: state.audioService.isMuted
                        ? "speaker.slash.fill"
                        : "speaker.wave.2.fill"
                )
                widgetCard(
                    title: "Running apps",
                    value: "\(state.runningBundleIdentifiers.count)",
                    symbol: "square.grid.2x2.fill"
                )
            }

            Text(
                "This panel shows taskbar and system-status events. macOS keeps other apps’ notification history private."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func notificationCard(_ notification: TaskbarNotification) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: notification.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(categoryColor(notification.category))
                .frame(width: 30, height: 30)
                .background(categoryColor(notification.category).opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notification.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(notification.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                service.dismiss(notification)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(TaskbarTheme.hoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func widgetCard(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(TaskbarTheme.activeIndicator)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 55)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func categoryColor(_ category: TaskbarNotification.Category) -> Color {
        switch category {
        case .network: return .blue
        case .battery: return .green
        case .bluetooth: return .indigo
        case .application: return .orange
        case .system: return TaskbarTheme.activeIndicator
        }
    }
}

private struct QuickSettingsFlyout: View {
    @ObservedObject var state: TaskbarState

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("Quick settings")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(Date(), style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                quickTile(
                    title: "Wi-Fi",
                    detail: state.networkService.statusText,
                    symbol: state.networkService.isPowered ? "wifi" : "wifi.slash",
                    isActive: state.networkService.isPowered
                ) {
                    state.networkService.setPowered(!state.networkService.isPowered)
                }

                quickTile(
                    title: "Bluetooth",
                    detail: state.bluetoothService.statusText,
                    symbol: "bluetooth",
                    isActive: state.bluetoothService.isPowered
                ) {
                    state.toggleFlyout(.bluetooth)
                }

                quickTile(
                    title: "Dark mode",
                    detail: state.appearanceService.isDarkMode ? "On" : "Off",
                    symbol: state.appearanceService.isDarkMode ? "moon.fill" : "sun.max.fill",
                    isActive: state.appearanceService.isDarkMode
                ) {
                    state.appearanceService.toggleDarkMode()
                }

                quickTile(
                    title: "Mute",
                    detail: state.audioService.isMuted ? "On" : "Off",
                    symbol: state.audioService.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isActive: state.audioService.isMuted
                ) {
                    state.audioService.toggleMute()
                }
            }

            controlSlider(
                title: "Brightness",
                symbol: "sun.max.fill",
                value: Binding(
                    get: { state.brightnessService.brightness },
                    set: { state.brightnessService.setBrightness($0) }
                ),
                isEnabled: state.brightnessService.isAvailable
            )

            controlSlider(
                title: "Volume",
                symbol: state.audioService.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                value: Binding(
                    get: { state.audioService.volume },
                    set: { state.audioService.setVolume($0) }
                ),
                isEnabled: state.audioService.isAvailable
            )

            if !state.bluetoothService.connectedDeviceNames.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connected devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(state.bluetoothService.connectedDeviceNames.joined(separator: "  •  "))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                }
            }

            HStack {
                Button {
                    state.toggleFlyout(.battery)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: state.batteryService.symbolName)
                        Text(state.batteryService.percentage.map { "\($0)%" } ?? "--")
                            .monospacedDigit()
                        if state.batteryService.isCharging {
                            Text("Charging")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(state.batteryService.isLowBattery ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help(state.batteryService.trayHelpText)
                Spacer()
                Button {
                    state.toggleFlyout(.bluetooth)
                } label: {
                    Label("Bluetooth devices", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func quickTile(
        title: String,
        detail: String,
        symbol: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(isActive ? Color.white.opacity(0.82) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                isActive
                    ? TaskbarTheme.activeIndicator.opacity(0.68)
                    : TaskbarTheme.hoverBackground
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func controlSlider(
        title: String,
        symbol: String,
        value: Binding<Double>,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 20)
                Slider(value: value, in: 0...1)
                    .disabled(!isEnabled)
            }
        }
    }
}

private struct AccessibilityPermissionView: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject var service: AccessibilityService

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Window access required", systemImage: "macwindow.badge.plus")
                .font(.system(size: 17, weight: .semibold))

            Text(
                "Allow Accessibility access once to snap, move, resize, minimize, restore, select, and close windows. This does not require separate access for every application. App launching still works without it."
            )
            .foregroundStyle(.secondary)

            HStack {
                Button("Open Accessibility Settings") {
                    state.accessibilityService.openPrivacySettings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Request Access", action: state.requestAccessibilityPermission)
                    .buttonStyle(.borderedProminent)
            }

            HStack {
                Image(
                    systemName: service.isTrusted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
                )
                .foregroundStyle(
                    service.isTrusted
                        ? TaskbarTheme.activeIndicator
                        : .secondary
                )
                Text(service.isTrusted ? "Access enabled" : "Waiting for access")
                Spacer()
                Button("Check Again", action: state.checkAccessibilityPermission)
                    .buttonStyle(.plain)
            }
            .font(.caption)
        }
    }
}

private struct WindowPreviewView: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject var service: WindowPreviewService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let app = state.previewApp {
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    Text(app.displayName)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("\(state.previewWindows.count) windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if service.permissionRequired {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                    Text("Allow Screen Recording to show live window thumbnails.")
                        .font(.caption)
                    Spacer()
                    Button("Open Settings", action: service.openScreenRecordingSettings)
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: state.previewWindows.count > 3) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(state.previewWindows) { window in
                        VStack(spacing: 7) {
                            Button {
                                state.activatePreviewWindow(window)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.black.opacity(0.28))
                                        if let image = service.image(for: window) {
                                            Image(nsImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .opacity(window.isMinimized ? 0.58 : 1)
                                        } else if let app = state.previewApp {
                                            Image(nsImage: app.icon)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 52, height: 52)
                                                .opacity(0.75)
                                        } else {
                                            Image(systemName: "macwindow")
                                                .font(.system(size: 36))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 205, height: 118)
                                    .clipped()

                                    Text(window.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Label(
                                        window.isMinimized ? "Minimized" : "Open",
                                        systemImage: window.isMinimized
                                            ? "minus.circle.fill"
                                            : "circle.fill"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(
                                        window.isMinimized
                                            ? Color.secondary
                                            : TaskbarTheme.activeIndicator
                                    )
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 8) {
                                previewAction(
                                    window.isMinimized
                                        ? "arrow.up.left.and.arrow.down.right"
                                        : "minus",
                                    help: window.isMinimized ? "Restore" : "Minimize"
                                ) {
                                    state.togglePreviewWindowMinimized(window)
                                }
                                previewAction(
                                    "arrow.up.left.and.arrow.down.right",
                                    help: "Maximize",
                                    isEnabled: !window.isMinimized
                                ) {
                                    state.maximizePreviewWindow(window)
                                }
                                Spacer()
                                previewAction("xmark", help: "Close window") {
                                    state.closePreviewWindow(window)
                                }
                            }
                        }
                        .padding(9)
                        .frame(width: 223)
                        .background(TaskbarTheme.hoverBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func previewAction(
        _ symbol: String,
        help: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 25, height: 22)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }
}

private struct OverflowAppsView: View {
    @ObservedObject var state: TaskbarState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More apps")
                .font(.system(size: 16, weight: .semibold))

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(state.overflowApps) { app in
                        Button {
                            state.launchFromStart(app)
                        } label: {
                            HStack(spacing: 11) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                Text(app.displayName)
                                    .lineLimit(1)
                                Spacer()
                                if state.isRunning(app) {
                                    Circle()
                                        .fill(
                                            state.isActive(app)
                                                ? TaskbarTheme.activeIndicator
                                                : TaskbarTheme.runningIndicator
                                        )
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct BluetoothFlyout: View {
    @ObservedObject var service: BluetoothService

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(
                    "Bluetooth",
                    systemImage: service.isPowered ? "bluetooth" : "bluetooth.slash"
                )
                .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(service.isPowered ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(service.isPowered ? TaskbarTheme.activeIndicator : .secondary)
            }

            if let code = service.pairingConfirmationCode {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Does this code match the device?")
                        .font(.system(size: 13, weight: .semibold))
                    Text(code)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    HStack {
                        Button("Cancel") { service.confirmPairing(false) }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Pair") { service.confirmPairing(true) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(TaskbarTheme.hoverBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !service.isPowered {
                Text("Turn on Bluetooth in macOS to discover and connect devices.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack {
                    Text("Devices")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if service.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(action: service.scan) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isScanning)
                    .help("Scan for devices")
                }

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(service.devices) { device in
                            HStack(spacing: 11) {
                                Image(
                                    systemName: device.isConnected
                                        ? "dot.radiowaves.left.and.right"
                                        : "hifispeaker"
                                )
                                .frame(width: 24)
                                .foregroundStyle(
                                    device.isConnected
                                        ? TaskbarTheme.activeIndicator
                                        : .secondary
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .lineLimit(1)
                                    Text(
                                        device.isConnected
                                            ? "Connected"
                                            : device.isPaired ? "Paired" : "Available"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if service.busyDeviceID == device.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if device.isConnected {
                                    Button("Disconnect") {
                                        service.disconnect(device)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button(device.isPaired ? "Connect" : "Pair") {
                                        service.connect(device)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(10)
                            .background(TaskbarTheme.hoverBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }

                if service.devices.isEmpty && !service.isScanning {
                    Text("No Bluetooth devices found.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }

            if let errorMessage = service.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                Button("Bluetooth Settings", action: service.openSettings)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct NetworkFlyout: View {
    @ObservedObject var service: NetworkService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Wi-Fi", systemImage: service.isPowered ? "wifi" : "wifi.slash")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle(
                    "Wi-Fi",
                    isOn: Binding(
                        get: { service.isPowered },
                        set: { service.setPowered($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if let pendingNetwork = service.pendingNetwork {
                passwordForm(for: pendingNetwork)
            } else if !service.isPowered {
                Text("Turn on Wi-Fi to find nearby networks.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if service.permissionState != .authorized {
                permissionView
            } else {
                if service.isConnected {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.networkName ?? "Connected network")
                                .font(.system(size: 14, weight: .semibold))
                            Text(
                                service.networkName == nil
                                    ? "Network name unavailable"
                                    : "Connected"
                            )
                                .font(.caption)
                                .foregroundStyle(
                                    service.networkName == nil
                                        ? Color.secondary
                                        : TaskbarTheme.activeIndicator
                                )
                        }
                        Spacer()
                        Button("Disconnect", action: service.disconnect)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(10)
                    .background(TaskbarTheme.hoverBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Text("Available networks")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if service.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(action: service.scan) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WindowsTaskbarButtonStyle())
                    .disabled(service.isScanning)
                    .help("Scan again")
                    .accessibilityLabel("Scan for Wi-Fi networks")
                }

                if service.isScanning && service.availableNetworks.isEmpty {
                    VStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching for networks…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                } else if service.scanState == .empty {
                    VStack(spacing: 7) {
                        Image(
                            systemName: service.isConnected
                                ? "wifi"
                                : "wifi.exclamationmark"
                        )
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text(
                            service.isConnected
                                ? "No additional networks found"
                                : "No networks found"
                        )
                            .font(.system(size: 13, weight: .semibold))
                        Text(
                            service.isConnected
                                ? "You are connected. Try scanning again to refresh this list."
                                : "Try scanning again or move closer to the router."
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 72)
                } else if case let .failed(message) = service.scanState {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)
                        Text("Couldn’t scan for networks")
                            .font(.system(size: 13, weight: .semibold))
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Button("Try again", action: service.scan)
                            .buttonStyle(.bordered)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 110)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(service.availableNetworks) { network in
                                Button {
                                    service.select(network)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: network.signalSymbol)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(network.name)
                                                .lineLimit(1)
                                            if network.name == service.networkName {
                                                Text("Connected")
                                                    .font(.caption)
                                                    .foregroundStyle(TaskbarTheme.activeIndicator)
                                            }
                                        }
                                        Spacer()
                                        if service.connectingNetworkName == network.name {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else if network.isSecure {
                                            Image(systemName: "lock.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    service.connectingNetworkName != nil
                                        || network.name == service.networkName
                                )
                                .background(
                                    network.name == service.networkName
                                        ? TaskbarTheme.hoverBackground
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
            }

            if let errorMessage = service.errorMessage,
               !service.scanState.isFailure {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var permissionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location access is required by macOS to reveal nearby Wi-Fi network names.")
                .foregroundStyle(.secondary)

            switch service.permissionState {
            case .notDetermined:
                Button("Allow and scan", action: service.requestPermissionAndScan)
                    .buttonStyle(.borderedProminent)
            case .requesting:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for permission…")
                    }
                    Button(
                        "Open Location Privacy Settings",
                        action: service.openLocationPrivacySettings
                    )
                    .buttonStyle(.bordered)
                }
            case .denied, .restricted:
                Button("Open Location Privacy Settings", action: service.openLocationPrivacySettings)
                    .buttonStyle(.bordered)
            case .authorized:
                EmptyView()
            }
            Spacer()
        }
    }

    private func passwordForm(for network: NetworkService.AvailableNetwork) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: service.cancelPasswordEntry) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Text("Connect to \(network.name)")
                .font(.system(size: 15, weight: .semibold))

            SecureField(
                "Network password",
                text: Binding(
                    get: { service.password },
                    set: { service.password = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(service.connectToPendingNetwork)

            HStack {
                Button("Cancel", action: service.cancelPasswordEntry)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Connect", action: service.connectToPendingNetwork)
                    .buttonStyle(.borderedProminent)
                    .disabled(service.password.isEmpty || service.connectingNetworkName != nil)
            }

            if service.connectingNetworkName != nil {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                }
            }
            Spacer()
        }
    }
}

private extension WiFiScanState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

private struct StartMenuView: View {
    @ObservedObject var state: TaskbarState

    private let columns = [
        GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            StartSearchField(
                text: $state.startQuery,
                onMoveSelection: state.moveStartSelection,
                onSubmit: state.launchSelectedStartResult,
                onEscape: state.handleStartEscape
            )
            .frame(height: 34)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if state.startQuery.isEmpty {
                        sectionHeader("Pinned")
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(state.pinnedApps) { app in
                                appTile(app, isSelected: false)
                            }
                        }

                        Divider()
                        sectionHeader("All apps")
                    } else {
                        sectionHeader("Search results")
                    }

                    if state.startResults.isEmpty {
                        Text("No applications found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(state.startResults.enumerated()), id: \.element.id) { index, app in
                                appTile(
                                    app,
                                    isSelected: index == state.selectedStartResultIndex
                                        && !state.startQuery.isEmpty
                                )
                            }
                        }
                    }
                }
            }

            Divider()
                .padding(.top, 12)

            if let pendingAction = state.pendingPowerAction {
                powerConfirmation(pendingAction)
            } else if state.isPowerMenuVisible {
                powerActions
            }

            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 23))
                Text(NSFullUserName())
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    state.toggleFlyout(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Taskbar settings")
                Button(action: state.togglePowerMenu) {
                    Image(systemName: "power")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Power options")
            }
            .padding(.top, 10)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
    }

    private func appTile(_ app: AppDescriptor, isSelected: Bool) -> some View {
        Button {
            state.launchFromStart(app)
        } label: {
            VStack(spacing: 7) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                Text(app.displayName)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? TaskbarTheme.hoverBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.displayName)
        .contextMenu {
            if state.isPinned(app) {
                Button("Unpin from taskbar") { state.unpin(app) }
            } else {
                Button("Pin to taskbar") { state.pin(app) }
            }
        }
    }

    private var powerActions: some View {
        HStack(spacing: 6) {
            ForEach(PowerAction.allCases) { action in
                Button {
                    state.requestPowerAction(action)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol)
                        Text(action.rawValue)
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity, minHeight: 45)
                }
                .buttonStyle(.plain)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("Exit")
                        .font(.system(size: 9))
                }
                .frame(maxWidth: .infinity, minHeight: 45)
            }
            .buttonStyle(.plain)
            .help("Exit taskbar and restore the macOS Dock")
        }
        .padding(.top, 8)
    }

    private func powerConfirmation(_ action: PowerAction) -> some View {
        HStack {
            Text("Confirm \(action.rawValue.lowercased())?")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Cancel", action: state.cancelPowerAction)
                .buttonStyle(.bordered)
            Button(action.rawValue, action: state.confirmPowerAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 10)
    }
}

private struct VolumeFlyout: View {
    @ObservedObject var service: AudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sound")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(service.outputDevices) { device in
                        Button {
                            service.selectOutputDevice(device)
                        } label: {
                            if device.id == service.selectedOutputDeviceID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    Label("Output", systemImage: "hifispeaker.fill")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(service.outputDevices.isEmpty)
            }

            HStack(spacing: 14) {
                Button(action: service.toggleMute) {
                    Image(systemName: service.isMuted ? "speaker.slash.fill" : volumeSymbol)
                        .font(.system(size: 19))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(service.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { service.volume },
                        set: { service.setVolume($0) }
                    ),
                    in: 0...1
                )
                .disabled(!service.isAvailable)

                Text("\(Int((service.volume * 100).rounded()))")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }

            Text(service.selectedOutputName ?? "No controllable audio output")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var volumeSymbol: String {
        switch service.volume {
        case 0: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

private struct BatteryFlyout: View {
    @ObservedObject var service: BatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: service.symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(service.isLowBattery ? .red : .white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.percentage.map { "\($0)%" } ?? "Battery")
                        .font(.system(size: 22, weight: .semibold))
                    Text(service.statusText)
                        .foregroundStyle(.secondary)
                    if let timing = service.isCharging
                        ? service.timeToFullText
                        : service.timeRemainingText {
                        Text(timing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let percentage = service.percentage {
                ProgressView(value: Double(percentage), total: 100)
                    .tint(service.isLowBattery ? .red : TaskbarTheme.activeIndicator)
            }

            VStack(alignment: .leading, spacing: 8) {
                batteryDetail(
                    service.powerSourceText,
                    symbol: service.isOnACPower ? "powerplug.fill" : "bolt.fill"
                )
                if service.lowPowerModeEnabled {
                    batteryDetail("Low Power Mode enabled", symbol: "leaf.fill")
                }
                if let health = service.healthPercentage {
                    batteryDetail("Battery health \(health)%", symbol: "heart.text.square")
                } else if let healthStatus = service.healthStatus {
                    batteryDetail("Battery health: \(healthStatus)", symbol: "heart.text.square")
                }
                if service.isFinishingCharge {
                    batteryDetail("Finishing charge", symbol: "bolt.badge.clock.fill")
                }
            }
            .font(.caption)

        }
    }

    private func batteryDetail(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.secondary)
    }
}

private struct CalendarFlyout: View {
    @ObservedObject var state: TaskbarState
    private let calendar = Calendar.current
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    private var days: [CalendarDay] {
        CalendarMonthGrid.days(
            for: state.calendarDisplayedMonth,
            calendar: calendar
        )
    }

    private var weekdaySymbols: [String] {
        CalendarMonthGrid.weekdaySymbols(calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date.formatted(date: .complete, time: .omitted))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text(
                    state.calendarDisplayedMonth.formatted(
                        .dateTime.month(.wide).year()
                    )
                )
                .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    state.moveCalendarMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Previous month")
                Button {
                    state.moveCalendarMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Next month")
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                }

                ForEach(days) { day in
                    calendarDayButton(day)
                }
            }

            HStack {
                Button("Today", action: state.selectTodayInCalendar)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Date & Time Settings") {
                    SystemActions.openDateAndTimeSettings()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func calendarDayButton(_ day: CalendarDay) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: state.calendarSelection)
        let isToday = calendar.isDateInToday(day.date)

        return Button {
            state.selectCalendarDate(day.date)
        } label: {
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : day.isInDisplayedMonth
                            ? TaskbarTheme.foreground
                            : Color.secondary.opacity(0.6)
                )
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    Circle()
                        .fill(
                            isSelected
                                ? TaskbarTheme.activeIndicator
                                : Color.clear
                        )
                        .frame(width: 30, height: 30)
                )
                .overlay {
                    if isToday && !isSelected {
                        Circle()
                            .stroke(TaskbarTheme.activeIndicator, lineWidth: 1.5)
                            .frame(width: 29, height: 29)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            day.date.formatted(date: .complete, time: .omitted)
        )
    }
}
