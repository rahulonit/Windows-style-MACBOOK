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
                    WindowPreviewView(state: state)
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
                    : "Required to minimize, restore, and close windows",
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

private struct SettingsFlyout: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject var service: PreferencesService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Taskbar settings", systemImage: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("Windows Taskbar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    iconSizeSetting

                    settingRow(
                        title: "Hide the macOS Dock",
                        detail: "The original Dock is restored when this app exits.",
                        isOn: $service.hideMacDock
                    )
                    settingRow(
                        title: "Show on all displays",
                        detail: "Display a taskbar at the bottom of every connected screen.",
                        isOn: $service.showOnAllDisplays
                    )
                    settingRow(
                        title: "Launch at login",
                        detail: "Start automatically when you sign in.",
                        isOn: Binding(
                            get: { service.launchAtLogin },
                            set: { service.setLaunchAtLogin($0) }
                        )
                    )

                    Divider()

                    HStack {
                        permissionStatus(
                            "Accessibility",
                            enabled: state.accessibilityService.isTrusted
                        )
                        Spacer()
                        Button("Review Permissions") {
                            state.accessibilityService.openPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        permissionStatus(
                            "Wi-Fi location",
                            enabled: state.networkService.permissionState == .authorized
                        )
                        Spacer()
                        Button("Request Access") {
                            state.networkService.requestPermissionAndScan()
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.networkService.permissionState == .authorized)
                    }

                    if let error = service.loginItemError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("Run setup again") {
                            service.resetOnboarding()
                            state.toggleFlyout(.onboarding)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text("Version 0.3.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 4)
            }
        }
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
                Text(service.taskbarIconSize.formatted(.number.precision(.fractionLength(0...1))) + " pt")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Image(systemName: "app.fill")
                    .font(.system(size: 14))
                    .frame(width: 20)
                Slider(
                    value: $service.taskbarIconSize,
                    in: PreferencesService.minimumTaskbarIconSize...PreferencesService.maximumTaskbarIconSize,
                    step: 0.5
                )
                Image(systemName: "app.fill")
                    .font(.system(size: 32))
                    .frame(width: 36)
            }

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: TaskbarTheme.startIconSize(
                            for: CGFloat(service.taskbarIconSize)
                        )))
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: TaskbarTheme.navigationIconSize(
                            for: CGFloat(service.taskbarIconSize)
                        )))
                    Image(systemName: "wifi")
                        .font(.system(size: TaskbarTheme.systemTrayIconSize))
                }
                .frame(height: 34)
                Spacer()
                Button("Reset", action: service.resetTaskbarIconSize)
                    .buttonStyle(.bordered)
                    .disabled(
                        service.taskbarIconSize
                            == PreferencesService.defaultTaskbarIconSize
                    )
            }
        }
        .padding(11)
        .background(TaskbarTheme.hoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .padding(10)
        .background(TaskbarTheme.hoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    value: state.networkService.networkName
                        ?? (state.networkService.isPowered ? "Not connected" : "Off"),
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
                    detail: state.networkService.networkName
                        ?? (state.networkService.isPowered ? "Available" : "Off"),
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
                "Allow Accessibility access to minimize, restore, select, and close windows from the taskbar. App launching still works without it."
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

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(state.previewWindows) { window in
                        HStack(spacing: 10) {
                            Button {
                                state.activatePreviewWindow(window)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: window.isMinimized ? "macwindow.badge.minus" : "macwindow")
                                        .font(.system(size: 23))
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(window.title)
                                            .lineLimit(1)
                                        Text(window.isMinimized ? "Minimized" : "Open")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                state.togglePreviewWindowMinimized(window)
                            } label: {
                                Image(systemName: window.isMinimized ? "arrow.up.left.and.arrow.down.right" : "minus")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help(window.isMinimized ? "Restore" : "Minimize")

                            Button {
                                state.closePreviewWindow(window)
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Close window")
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 58)
                        .background(TaskbarTheme.hoverBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
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
                if let networkName = service.networkName {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(networkName)
                                .font(.system(size: 14, weight: .semibold))
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(TaskbarTheme.activeIndicator)
                        }
                        Spacer()
                        Button("Disconnect", action: service.disconnect)
                            .buttonStyle(.bordered)
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
                    }
                    .buttonStyle(.plain)
                    .help("Scan again")
                }

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

            if let errorMessage = service.errorMessage {
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
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permission…")
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
