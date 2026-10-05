import AppKit
import Combine

@MainActor
final class TaskbarState: ObservableObject {
    static let finderBundleIdentifier = "com.apple.finder"
    @Published private(set) var pinnedApps: [AppDescriptor]
    @Published private(set) var taskbarApps: [AppDescriptor] = []
    @Published private(set) var installedApps: [AppDescriptor] = []
    @Published private(set) var overflowApps: [AppDescriptor] = []
    @Published private(set) var runningBundleIdentifiers: Set<String> = []
    @Published private(set) var activeBundleIdentifier: String?
    @Published private(set) var windowCounts: [String: Int] = [:]
    @Published private(set) var previewApp: AppDescriptor?
    @Published private(set) var previewWindows: [AccessibilityWindow] = []
    @Published var activeFlyout: TaskbarFlyout?
    @Published var startQuery = "" {
        didSet { selectedStartResultIndex = 0 }
    }
    @Published private(set) var selectedStartResultIndex = 0
    @Published private(set) var isPowerMenuVisible = false
    @Published private(set) var pendingPowerAction: PowerAction?
    @Published var draggedPinnedAppIdentifier: String?
    @Published var calendarSelection = Date()
    @Published private(set) var calendarDisplayedMonth = CalendarMonthGrid.monthStart(
        containing: Date()
    )

    let networkService = NetworkService()
    let audioService = AudioService()
    let batteryService = BatteryService()
    let accessibilityService = AccessibilityService()
    let brightnessService = BrightnessService()
    let bluetoothService = BluetoothService()
    let appearanceService = AppearanceService()
    let preferencesService: PreferencesService
    lazy var notificationService = TaskbarNotificationService(
        networkService: networkService,
        batteryService: batteryService,
        bluetoothService: bluetoothService
    )

    private let workspace = NSWorkspace.shared
    private let pinnedAppsStore: PinnedAppsStore
    private var observers: [NSObjectProtocol] = []

    init(
        pinnedApps: [AppDescriptor]? = nil,
        pinnedAppsStore: PinnedAppsStore = PinnedAppsStore(),
        preferencesService: PreferencesService? = nil
    ) {
        self.pinnedAppsStore = pinnedAppsStore
        self.preferencesService = preferencesService ?? PreferencesService()
        if let pinnedApps {
            self.pinnedApps = pinnedApps
        } else if let storedIdentifiers = pinnedAppsStore.load() {
            self.pinnedApps = storedIdentifiers.compactMap(ApplicationCatalog.descriptor(for:))
        } else {
            self.pinnedApps = ApplicationCatalog.defaultPinnedApps()
        }
        self.installedApps = ApplicationCatalog.installedApplications()
        refreshRunningApplications()
        observeWorkspace()
    }

    deinit {
        let notificationCenter = workspace.notificationCenter
        observers.forEach(notificationCenter.removeObserver)
    }

    func isRunning(_ app: AppDescriptor) -> Bool {
        runningBundleIdentifiers.contains(app.bundleIdentifier)
    }

    func isActive(_ app: AppDescriptor) -> Bool {
        activeBundleIdentifier == app.bundleIdentifier
    }

    func isPinned(_ app: AppDescriptor) -> Bool {
        pinnedApps.contains { $0.bundleIdentifier == app.bundleIdentifier }
    }

    func windowCount(for app: AppDescriptor) -> Int {
        windowCounts[app.bundleIdentifier] ?? 0
    }

    var startResults: [AppDescriptor] {
        let query = startQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return installedApps }
        return installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    func activate(_ app: AppDescriptor) {
        activeFlyout = nil
        if let runningApplication = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == app.bundleIdentifier
        }) {
            accessibilityService.refreshAuthorization()
            guard accessibilityService.isTrusted else {
                if app.bundleIdentifier == Self.finderBundleIdentifier {
                    if runningApplication.isActive {
                        openFinderWindow(for: app)
                    } else {
                        runningApplication.activate(options: [.activateAllWindows])
                    }
                } else {
                    reopenApplication(runningApplication, descriptor: app)
                }
                return
            }

            let windows = accessibilityService.windows(for: runningApplication)
            windowCounts[app.bundleIdentifier] = windows.count
            if windows.count > 1 {
                previewApp = app
                previewWindows = windows
                activeFlyout = .windowPreview
            } else if let window = windows.first {
                accessibilityService.toggle(window, application: runningApplication)
                refreshWindowInformation(for: app)
            } else {
                if app.bundleIdentifier == Self.finderBundleIdentifier {
                    openFinderWindow(for: app)
                } else {
                    reopenApplication(runningApplication, descriptor: app)
                }
            }
            return
        }

        openApplication(app)
    }

    private func openApplication(_ app: AppDescriptor) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: app.applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Unable to launch \(app.displayName): \(error.localizedDescription)")
            }
        }
    }

    private func reopenApplication(
        _ application: NSRunningApplication,
        descriptor: AppDescriptor
    ) {
        application.unhide()
        let target = NSAppleEventDescriptor(
            processIdentifier: application.processIdentifier
        )
        let reopenEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        reopenEvent.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: AEKeyword(kAEApplicationActivationExpected)
        )

        // Route the reopen event through Launch Services. Sending Apple events
        // directly would make macOS request Automation access separately for
        // every application controlled by the taskbar.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.appleEvent = reopenEvent
        workspace.openApplication(
            at: descriptor.applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    NSLog(
                        "Unable to reopen \(descriptor.displayName): \(error.localizedDescription)"
                    )
                    self?.openApplication(descriptor)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshWindowInformation(for: descriptor)
        }
    }

    func toggleFlyout(_ flyout: TaskbarFlyout) {
        if activeFlyout == flyout {
            activeFlyout = nil
            return
        }

        switch flyout {
        case .start:
            startQuery = ""
            selectedStartResultIndex = 0
            isPowerMenuVisible = false
            pendingPowerAction = nil
        case .overflow: break
        case .accessibility:
            accessibilityService.refreshAuthorization()
        case .windowPreview: break
        case .network: networkService.scan()
        case .bluetooth:
            bluetoothService.refresh()
            bluetoothService.scan()
        case .volume: audioService.refresh()
        case .battery: batteryService.refresh()
        case .calendar:
            calendarDisplayedMonth = CalendarMonthGrid.monthStart(
                containing: calendarSelection
            )
        case .quickSettings:
            networkService.refresh()
            audioService.refresh()
            brightnessService.refresh()
            bluetoothService.refresh()
            appearanceService.refresh()
        case .notificationCenter:
            notificationService.markAllRead()
        case .settings:
            preferencesService.refreshLaunchAtLogin()
        case .onboarding: break
        }
        activeFlyout = flyout
    }

    func launchFromStart(_ app: AppDescriptor) {
        activeFlyout = nil
        activate(app)
    }

    func showOverflow(_ apps: [AppDescriptor]) {
        overflowApps = apps
        toggleFlyout(.overflow)
    }

    func dismissFlyout() {
        activeFlyout = nil
        pendingPowerAction = nil
        isPowerMenuVisible = false
    }

    func showOnboardingIfNeeded() {
        guard !preferencesService.hasCompletedOnboarding else { return }
        activeFlyout = .onboarding
    }

    func completeOnboarding() {
        preferencesService.completeOnboarding()
        activeFlyout = nil
    }

    func moveCalendarMonth(by offset: Int) {
        guard let month = Calendar.current.date(
            byAdding: .month,
            value: offset,
            to: calendarDisplayedMonth
        ) else { return }
        calendarDisplayedMonth = CalendarMonthGrid.monthStart(containing: month)
    }

    func selectCalendarDate(_ date: Date) {
        calendarSelection = date
        calendarDisplayedMonth = CalendarMonthGrid.monthStart(containing: date)
    }

    func selectTodayInCalendar() {
        selectCalendarDate(Date())
    }

    func perform(_ action: () -> Void) {
        activeFlyout = nil
        action()
    }

    func pin(_ app: AppDescriptor) {
        guard !isPinned(app) else { return }
        pinnedApps.append(app)
        persistPinnedApps()
        rebuildTaskbarApps()
    }

    func unpin(_ app: AppDescriptor) {
        pinnedApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        persistPinnedApps()
        rebuildTaskbarApps()
    }

    func movePinnedApp(_ app: AppDescriptor, offset: Int) {
        guard
            let currentIndex = pinnedApps.firstIndex(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            })
        else { return }
        let targetIndex = min(max(0, currentIndex + offset), pinnedApps.count - 1)
        guard targetIndex != currentIndex else { return }
        let moved = pinnedApps.remove(at: currentIndex)
        pinnedApps.insert(moved, at: targetIndex)
        persistPinnedApps()
        rebuildTaskbarApps()
    }

    func beginDragging(_ app: AppDescriptor) {
        if !isPinned(app) { pin(app) }
        draggedPinnedAppIdentifier = app.bundleIdentifier
    }

    func moveDraggedPinnedApp(over target: AppDescriptor) {
        guard
            let sourceIdentifier = draggedPinnedAppIdentifier,
            sourceIdentifier != target.bundleIdentifier,
            let sourceIndex = pinnedApps.firstIndex(where: { $0.bundleIdentifier == sourceIdentifier }),
            let targetIndex = pinnedApps.firstIndex(where: {
                $0.bundleIdentifier == target.bundleIdentifier
            })
        else { return }
        let moved = pinnedApps.remove(at: sourceIndex)
        pinnedApps.insert(moved, at: targetIndex)
        persistPinnedApps()
        rebuildTaskbarApps()
    }

    func endDragging() {
        draggedPinnedAppIdentifier = nil
    }

    func quit(_ app: AppDescriptor) {
        activeFlyout = nil
        guard app.bundleIdentifier != Self.finderBundleIdentifier else { return }
        workspace.runningApplications
            .filter { $0.bundleIdentifier == app.bundleIdentifier }
            .forEach { $0.terminate() }
    }

    func showWindows(for app: AppDescriptor) {
        accessibilityService.refreshAuthorization()
        guard accessibilityService.isTrusted else {
            activeFlyout = .accessibility
            return
        }
        guard let runningApplication = runningApplication(for: app) else { return }
        previewApp = app
        previewWindows = accessibilityService.windows(for: runningApplication)
        windowCounts[app.bundleIdentifier] = previewWindows.count
        activeFlyout = .windowPreview
    }

    func activatePreviewWindow(_ window: AccessibilityWindow) {
        guard
            let app = previewApp,
            let runningApplication = runningApplication(for: app)
        else { return }
        activeFlyout = nil
        accessibilityService.activate(window, application: runningApplication)
        refreshWindowInformation(for: app)
    }

    func togglePreviewWindowMinimized(_ window: AccessibilityWindow) {
        guard
            let app = previewApp,
            let runningApplication = runningApplication(for: app)
        else { return }
        if window.isMinimized {
            accessibilityService.restore(window, application: runningApplication)
        } else {
            accessibilityService.minimize(window)
        }
        refreshPreviewWindows()
    }

    func closePreviewWindow(_ window: AccessibilityWindow) {
        accessibilityService.close(window)
        DispatchQueue.main.async { [weak self] in
            self?.refreshPreviewWindows()
        }
    }

    func requestAccessibilityPermission() {
        accessibilityService.requestAuthorization()
    }

    func showAccessibilityOnboarding() {
        accessibilityService.refreshAuthorization()
        activeFlyout = .accessibility
    }

    func checkAccessibilityPermission() {
        accessibilityService.refreshAuthorization()
        if accessibilityService.isTrusted {
            activeFlyout = nil
            refreshWindowCounts()
        }
    }

    func moveStartSelection(_ direction: Int) {
        guard !startQuery.isEmpty, !startResults.isEmpty else {
            selectedStartResultIndex = 0
            return
        }
        selectedStartResultIndex = min(
            max(0, selectedStartResultIndex + direction),
            startResults.count - 1
        )
    }

    func launchSelectedStartResult() {
        guard
            !startQuery.isEmpty,
            startResults.indices.contains(selectedStartResultIndex)
        else { return }
        launchFromStart(startResults[selectedStartResultIndex])
    }

    func handleStartEscape() {
        if !startQuery.isEmpty {
            startQuery = ""
        } else {
            dismissFlyout()
        }
    }

    func togglePowerMenu() {
        pendingPowerAction = nil
        isPowerMenuVisible.toggle()
    }

    func requestPowerAction(_ action: PowerAction) {
        pendingPowerAction = action
    }

    func cancelPowerAction() {
        pendingPowerAction = nil
    }

    func confirmPowerAction() {
        guard let action = pendingPowerAction else { return }
        pendingPowerAction = nil
        activeFlyout = nil
        SystemActions.performPowerAction(action)
    }

    private func observeWorkspace() {
        let center = workspace.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        observers = names.map { name in
            center.addObserver(forName: name, object: workspace, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.refreshRunningApplications()
                    if name == NSWorkspace.didLaunchApplicationNotification
                        || name == NSWorkspace.didTerminateApplicationNotification,
                       let application = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                       ] as? NSRunningApplication,
                       application.activationPolicy == .regular {
                        self?.notificationService.postApplicationEvent(
                            name: application.localizedName ?? "Application",
                            launched: name == NSWorkspace.didLaunchApplicationNotification
                        )
                    }
                }
            }
        }
    }

    private func refreshRunningApplications() {
        let applications = workspace.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        runningBundleIdentifiers = Set(applications.compactMap(\.bundleIdentifier))
        activeBundleIdentifier = applications.first(where: \.isActive)?.bundleIdentifier

        rebuildTaskbarApps(using: applications)
        refreshWindowCounts(using: applications)
    }

    private func rebuildTaskbarApps() {
        let applications = workspace.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        rebuildTaskbarApps(using: applications)
    }

    private func rebuildTaskbarApps(using applications: [NSRunningApplication]) {
        let pinnedIdentifiers = Set(pinnedApps.map(\.bundleIdentifier))
        let unpinnedRunningApps = applications
            .compactMap(ApplicationCatalog.descriptor(for:))
            .filter { !pinnedIdentifiers.contains($0.bundleIdentifier) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        taskbarApps = pinnedApps + unpinnedRunningApps
    }

    private func persistPinnedApps() {
        pinnedAppsStore.save(pinnedApps.map(\.bundleIdentifier))
    }

    private func runningApplication(for app: AppDescriptor) -> NSRunningApplication? {
        workspace.runningApplications.first { $0.bundleIdentifier == app.bundleIdentifier }
    }

    private func openFinderWindow(for app: AppDescriptor) {
        workspace.open(FileManager.default.homeDirectoryForCurrentUser)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshWindowInformation(for: app)
        }
    }

    private func refreshWindowCounts() {
        let applications = workspace.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        refreshWindowCounts(using: applications)
    }

    private func refreshWindowCounts(using applications: [NSRunningApplication]) {
        accessibilityService.refreshAuthorization()
        guard accessibilityService.isTrusted else {
            windowCounts = [:]
            return
        }
        windowCounts = Dictionary(uniqueKeysWithValues: applications.compactMap { application in
            guard let identifier = application.bundleIdentifier else { return nil }
            return (identifier, accessibilityService.windows(for: application).count)
        })
    }

    private func refreshWindowInformation(for app: AppDescriptor) {
        guard let runningApplication = runningApplication(for: app) else { return }
        windowCounts[app.bundleIdentifier] = accessibilityService.windows(for: runningApplication).count
    }

    private func refreshPreviewWindows() {
        guard
            let app = previewApp,
            let runningApplication = runningApplication(for: app)
        else { return }
        previewWindows = accessibilityService.windows(for: runningApplication)
        windowCounts[app.bundleIdentifier] = previewWindows.count
        if previewWindows.isEmpty {
            activeFlyout = nil
        }
    }
}
