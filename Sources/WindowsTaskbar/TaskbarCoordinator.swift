import AppKit
import Combine
import SwiftUI

@MainActor
final class TaskbarCoordinator {
    private let state: TaskbarState
    private var panelsByScreenNumber: [NSNumber: TaskbarPanel] = [:]
    private var flyoutPanel: TaskbarPanel?
    private var flyoutCancellable: AnyCancellable?
    private var flyoutContentCancellable: AnyCancellable?
    private var displayPreferenceCancellable: AnyCancellable?
    private var iconSizeCancellable: AnyCancellable?
    private var windowAdaptationCancellable: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var fullScreenTimer: Timer?
    private var windowLayoutTimer: Timer?
    private var fullScreenDisplayIDs: Set<CGDirectDisplayID> = []
    private var previousTaskbarHeight: CGFloat

    init(state: TaskbarState) {
        self.state = state
        previousTaskbarHeight = TaskbarTheme.height(
            for: CGFloat(state.preferencesService.taskbarIconSize)
        )
    }

    func start() {
        fullScreenDisplayIDs = FullScreenMonitor.fullScreenDisplayIDs()
        rebuildPanels()
        state.accessibilityService.adaptApplicationWindows(
            from: 0,
            to: previousTaskbarHeight,
            on: visibleTaskbarDisplayIDs
        )
        flyoutCancellable = state.$activeFlyout
            .dropFirst()
            .sink { [weak self] flyout in
                self?.updateFlyout(flyout)
            }
        flyoutContentCancellable = Publishers.MergeMany([
            state.networkService.objectWillChange.eraseToAnyPublisher(),
            state.bluetoothService.objectWillChange.eraseToAnyPublisher(),
            state.batteryService.objectWillChange.eraseToAnyPublisher(),
            state.notificationService.objectWillChange.eraseToAnyPublisher()
        ])
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.resizeActiveFlyoutToFitContent()
        }
        displayPreferenceCancellable = state.preferencesService.$showOnAllDisplays
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildPanels()
            }
        iconSizeCancellable = state.preferencesService.$taskbarIconSize
            .dropFirst()
            .sink { [weak self] iconSize in
                guard let self else { return }
                updatePanelGeometry(for: CGFloat(iconSize))
            }
        windowAdaptationCancellable = state.preferencesService.$taskbarIconSize
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] iconSize in
                self?.commitApplicationWindowHeight(for: CGFloat(iconSize))
            }
        fullScreenTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFullScreenState() }
        }
        windowLayoutTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.enforceAvailableWindowArea() }
        }
        installDismissalMonitors()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildPanels()
                }
            }
        )
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ] {
            workspaceObservers.append(
                workspaceCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.refreshFullScreenState() }
                }
            )
        }
        DispatchQueue.main.async { [weak self] in
            self?.state.showOnboardingIfNeeded()
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        panelsByScreenNumber.values.forEach { $0.close() }
        panelsByScreenNumber.removeAll()
        flyoutPanel?.close()
        flyoutPanel = nil
        flyoutCancellable = nil
        flyoutContentCancellable = nil
        displayPreferenceCancellable = nil
        iconSizeCancellable = nil
        windowAdaptationCancellable = nil
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        windowLayoutTimer?.invalidate()
        windowLayoutTimer = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    private func rebuildPanels() {
        let targetScreens: [NSScreen]
        if state.preferencesService.showOnAllDisplays {
            targetScreens = NSScreen.screens
        } else {
            targetScreens = [NSScreen.main ?? NSScreen.screens[0]]
        }
        let connectedScreenNumbers = Set(targetScreens.compactMap(\.screenNumber))
        let disconnectedScreenNumbers = panelsByScreenNumber.keys.filter {
            !connectedScreenNumbers.contains($0)
        }

        for screenNumber in disconnectedScreenNumbers {
            panelsByScreenNumber[screenNumber]?.close()
            panelsByScreenNumber.removeValue(forKey: screenNumber)
        }

        for screen in targetScreens {
            guard let screenNumber = screen.screenNumber else { continue }
            let panel = panelsByScreenNumber[screenNumber] ?? makePanel(for: screen)
            panel.setFrame(taskbarFrame(for: screen), display: true)
            setPanel(panel, hidden: fullScreenDisplayIDs.contains(
                CGDirectDisplayID(screenNumber.uint32Value)
            ))
            panelsByScreenNumber[screenNumber] = panel
        }


        if let activeFlyout = state.activeFlyout {
            updateFlyout(activeFlyout)
        }
    }

    private func updatePanelGeometry(for iconSize: CGFloat) {
        for (screenNumber, panel) in panelsByScreenNumber {
            guard let screen = NSScreen.screens.first(where: {
                $0.screenNumber == screenNumber
            }) else { continue }
            panel.setFrame(taskbarFrame(for: screen, iconSize: iconSize), display: true)
        }

        guard let flyoutPanel,
              let screen = flyoutPanel.screen ?? NSScreen.main
        else { return }
        var frame = flyoutPanel.frame
        frame.origin.y = screen.frame.minY + TaskbarTheme.height(for: iconSize) + 8
        flyoutPanel.setFrame(frame, display: true)
        resizeActiveFlyoutToFitContent()
    }

    private func commitApplicationWindowHeight(for iconSize: CGFloat) {
        let newHeight = TaskbarTheme.height(for: iconSize)
        guard abs(newHeight - previousTaskbarHeight) > 0.01 else { return }
        state.accessibilityService.adaptApplicationWindows(
            from: previousTaskbarHeight,
            to: newHeight,
            on: visibleTaskbarDisplayIDs
        )
        previousTaskbarHeight = newHeight
    }

    private func refreshFullScreenState() {
        let previouslyFullScreen = fullScreenDisplayIDs
        let updated = FullScreenMonitor.fullScreenDisplayIDs()
        guard updated != fullScreenDisplayIDs else { return }
        fullScreenDisplayIDs = updated

        for (screenNumber, panel) in panelsByScreenNumber {
            setPanel(
                panel,
                hidden: updated.contains(CGDirectDisplayID(screenNumber.uint32Value))
            )
        }

        if let flyoutPanel,
           let screenID = flyoutPanel.screen?.displayID,
           updated.contains(screenID) {
            state.dismissFlyout()
        }

        if !previouslyFullScreen.subtracting(updated).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.enforceAvailableWindowArea()
            }
        }
    }

    private var visibleTaskbarDisplayIDs: Set<CGDirectDisplayID> {
        Set(panelsByScreenNumber.keys.map {
            CGDirectDisplayID($0.uint32Value)
        }).subtracting(fullScreenDisplayIDs)
    }

    private func enforceAvailableWindowArea() {
        let height = TaskbarTheme.height(
            for: CGFloat(state.preferencesService.taskbarIconSize)
        )
        state.accessibilityService.adaptApplicationWindows(
            from: height,
            to: height,
            on: visibleTaskbarDisplayIDs
        )
    }

    private func setPanel(_ panel: TaskbarPanel, hidden: Bool) {
        panel.ignoresMouseEvents = hidden
        panel.alphaValue = hidden ? 0 : 1
        if !hidden {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel(for screen: NSScreen) -> TaskbarPanel {
        let panel = TaskbarPanel(
            contentRect: taskbarFrame(for: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        // Do not opt into full-screen Spaces. `.fullScreenAuxiliary` explicitly
        // carries the panel over full-screen apps, which is the opposite of the
        // taskbar's hide-in-full-screen behavior.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSHostingView(rootView: TaskbarView(state: state))
        return panel
    }

    private func taskbarFrame(for screen: NSScreen) -> NSRect {
        taskbarFrame(
            for: screen,
            iconSize: CGFloat(state.preferencesService.taskbarIconSize)
        )
    }

    private func taskbarFrame(for screen: NSScreen, iconSize: CGFloat) -> NSRect {
        let height = TaskbarTheme.height(for: iconSize)
        return NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: height
        )
    }

    private func updateFlyout(_ flyout: TaskbarFlyout?) {
        guard let flyout else {
            flyoutPanel?.orderOut(nil)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let taskbarHeight = TaskbarTheme.height(
            for: CGFloat(state.preferencesService.taskbarIconSize)
        )
        let originY = screen.frame.minY + taskbarHeight + 8
        let availableSize = CGSize(
            width: max(280, screen.frame.width - 16),
            height: max(160, screen.visibleFrame.maxY - originY - 8)
        )
        let size = FlyoutLayoutPolicy.preferredSize(
            for: flyout,
            context: flyoutLayoutContext(availableSize: availableSize)
        )
        let minimumX = screen.frame.minX + 8
        let maximumX = screen.frame.maxX - size.width - 8
        let desiredX = flyout == .start
            ? screen.frame.midX - size.width / 2
            : mouseLocation.x - size.width / 2
        let originX = min(max(desiredX, minimumX), maximumX)
        let frame = NSRect(
            x: originX,
            y: originY,
            width: size.width,
            height: size.height
        )

        let panel = flyoutPanel ?? makeFlyoutPanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(rootView: SystemFlyoutView(kind: flyout, state: state))
        panel.orderFrontRegardless()
        panel.makeKey()
        flyoutPanel = panel
    }

    private func flyoutLayoutContext(availableSize: CGSize) -> FlyoutLayoutContext {
        let battery = state.batteryService
        var batteryDetailCount = 1
        if battery.lowPowerModeEnabled { batteryDetailCount += 1 }
        if battery.healthPercentage != nil || battery.healthStatus != nil {
            batteryDetailCount += 1
        }
        if battery.isFinishingCharge { batteryDetailCount += 1 }

        return FlyoutLayoutContext(
            availableSize: availableSize,
            overflowAppCount: state.overflowApps.count,
            previewWindowCount: state.previewWindows.count,
            networkCount: state.networkService.availableNetworks.count,
            hasConnectedNetwork: state.networkService.networkName != nil,
            networkIsPowered: state.networkService.isPowered,
            networkIsAuthorized: state.networkService.permissionState == .authorized,
            hasPendingNetwork: state.networkService.pendingNetwork != nil,
            hasNetworkError: state.networkService.errorMessage != nil,
            bluetoothDeviceCount: state.bluetoothService.devices.count,
            bluetoothIsPowered: state.bluetoothService.isPowered,
            hasPairingConfirmation: state.bluetoothService.pairingConfirmationCode != nil,
            hasBluetoothError: state.bluetoothService.errorMessage != nil,
            batteryDetailCount: batteryDetailCount,
            hasConnectedBluetoothDevices: !state.bluetoothService.connectedDeviceNames.isEmpty,
            notificationCount: state.notificationService.notifications.count
        )
    }

    private func resizeActiveFlyoutToFitContent() {
        guard let flyout = state.activeFlyout,
              let panel = flyoutPanel,
              let screen = panel.screen ?? NSScreen.main
        else { return }

        let taskbarHeight = TaskbarTheme.height(
            for: CGFloat(state.preferencesService.taskbarIconSize)
        )
        let originY = screen.frame.minY + taskbarHeight + 8
        let availableSize = CGSize(
            width: max(280, screen.frame.width - 16),
            height: max(160, screen.visibleFrame.maxY - originY - 8)
        )
        let size = FlyoutLayoutPolicy.preferredSize(
            for: flyout,
            context: flyoutLayoutContext(availableSize: availableSize)
        )
        let previousMidX = panel.frame.midX
        let minimumX = screen.frame.minX + 8
        let maximumX = screen.frame.maxX - size.width - 8
        let originX = min(
            max(previousMidX - size.width / 2, minimumX),
            maximumX
        )
        panel.setFrame(
            NSRect(x: originX, y: originY, width: size.width, height: size.height),
            display: true,
            animate: true
        )
    }

    private func makeFlyoutPanel(frame: NSRect) -> TaskbarPanel {
        let panel = TaskbarPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.onCancel = { [weak self] in
            self?.state.dismissFlyout()
        }
        return panel
    }

    private func installDismissalMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.state.activeFlyout != nil else { return event }
            let location = NSEvent.mouseLocation
            let isInsideFlyout = self.flyoutPanel?.frame.contains(location) == true
            let isInsideTaskbar = self.panelsByScreenNumber.values.contains {
                $0.frame.contains(location)
            }
            if !isInsideFlyout && !isInsideTaskbar {
                self.state.dismissFlyout()
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state.dismissFlyout()
            }
        }
    }
}

private extension NSScreen {
    var screenNumber: NSNumber? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }
}
