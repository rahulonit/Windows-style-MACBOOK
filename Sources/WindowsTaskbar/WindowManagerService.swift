import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class WindowManagerService: ObservableObject {
    @Published private(set) var activeZone: SnapZone?

    var isDraggingWindow: Bool { draggedWindow != nil }

    private let accessibility: AccessibilityService
    private let preferences: PreferencesService
    private let restoreStore = WindowRestoreStore()
    private var previewPanel: SnapOverlayPanel?
    private var layoutPanel: SnapOverlayPanel?
    private var localMonitor: Any?
    private var globalMouseMonitor: Any?
    private var hotKeyReferences: [EventHotKeyRef?] = []
    private var hotKeyEventHandler: EventHandlerRef?
    private var keyboardSettingsCancellable: AnyCancellable?
    private var hoverWorkItem: DispatchWorkItem?
    private var hoverIdentity: WindowIdentity?
    private var layoutWindow: AccessibilityWindow?
    private var dragCandidate: AccessibilityWindow?
    private var dragCandidateInitialFrame: CGRect?
    private var draggedWindow: AccessibilityWindow?
    private var draggedWorkArea: ScreenWorkArea?
    private var taskbarHeightProvider: (() -> CGFloat)?
    private var taskbarDisplayIDsProvider: (() -> Set<CGDirectDisplayID>)?
    private var fullScreenDisplayIDsProvider: (() -> Set<CGDirectDisplayID>)?
    private var workspaceObserver: NSObjectProtocol?

    init(
        accessibility: AccessibilityService,
        preferences: PreferencesService
    ) {
        self.accessibility = accessibility
        self.preferences = preferences
    }

    func start(
        taskbarHeight: @escaping () -> CGFloat,
        taskbarDisplayIDs: @escaping () -> Set<CGDirectDisplayID>,
        fullScreenDisplayIDs: @escaping () -> Set<CGDirectDisplayID>
    ) {
        stop()
        taskbarHeightProvider = taskbarHeight
        taskbarDisplayIDsProvider = taskbarDisplayIDs
        fullScreenDisplayIDsProvider = fullScreenDisplayIDs

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        keyboardSettingsCancellable = Publishers.CombineLatest3(
            preferences.$windowManagementEnabled,
            preferences.$keyboardSnappingEnabled,
            accessibility.$isTrusted
        )
        .removeDuplicates { $0 == $1 }
        .sink { [weak self] enabled, keyboardEnabled, trusted in
            guard let self else { return }
            if enabled && keyboardEnabled && trusted {
                self.installKeyboardHotKeys()
            } else {
                self.removeKeyboardHotKeys()
            }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.restoreStore.remove(processIdentifier: application.processIdentifier)
            }
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        localMonitor = nil
        globalMouseMonitor = nil
        keyboardSettingsCancellable = nil
        removeKeyboardHotKeys()
        workspaceObserver = nil
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hideOverlays()
        restoreStore.removeAll()
    }

    func snapFocusedWindow(to zone: SnapZone) -> WindowOperationResult {
        guard isAvailable else { return .accessibilityUnavailable }
        guard let window = accessibility.focusedWindow() else { return .windowClosed }
        return snap(window, to: zone)
    }

    func snap(
        application: NSRunningApplication,
        to zone: SnapZone
    ) -> WindowOperationResult {
        guard isAvailable else { return .accessibilityUnavailable }
        guard let window = accessibility.focusedWindow(for: application) else {
            return .windowClosed
        }
        return snap(window, to: zone)
    }

    func restore(application: NSRunningApplication) -> WindowOperationResult {
        guard isAvailable else { return .accessibilityUnavailable }
        guard let window = accessibility.focusedWindow(for: application) else {
            return .windowClosed
        }
        return restore(window)
    }

    func minimize(application: NSRunningApplication) {
        guard isAvailable,
              let window = accessibility.focusedWindow(for: application)
        else { return }
        accessibility.minimize(window)
    }

    func toggleMaximize(_ window: AccessibilityWindow) -> WindowOperationResult {
        guard isAvailable else { return .accessibilityUnavailable }
        if restoreStore.state(for: window) != nil {
            return restore(window)
        }
        return snap(window, to: .maximize)
    }

    func showSnapLayouts(for window: AccessibilityWindow) {
        guard isAvailable,
              preferences.snapLayoutsEnabled,
              let windowFrame = accessibility.frame(of: window)
        else { return }
        let anchor = CGRect(
            x: windowFrame.maxX - 84,
            y: windowFrame.minY + 4,
            width: 42,
            height: 28
        )
        showLayoutPanel(for: window, zoomButtonFrame: anchor)
    }

    private var isAvailable: Bool {
        preferences.windowManagementEnabled && accessibility.isTrusted
    }

    private var workAreas: [ScreenWorkArea] {
        let height = taskbarHeightProvider?() ?? 0
        let taskbarDisplayIDs = taskbarDisplayIDsProvider?() ?? []
        return ScreenWorkArea.current(
            taskbarHeight: height,
            taskbarDisplayIDs: taskbarDisplayIDs
        )
    }

    private func handle(_ event: NSEvent) {
        guard preferences.windowManagementEnabled else {
            hideOverlays()
            return
        }
        switch event.type {
        case .mouseMoved:
            handleMouseMoved()
        case .leftMouseDown:
            handleMouseDown()
        case .leftMouseDragged:
            handleMouseDragged()
        case .leftMouseUp:
            handleMouseUp()
        default:
            break
        }
    }

    private func handleKeyboardHotKey(identifier: UInt32) {
        guard isAvailable, preferences.keyboardSnappingEnabled else { return }
        switch identifier {
        case 1:
            _ = snapFocusedWindow(to: .leftHalf)
        case 2:
            _ = snapFocusedWindow(to: .rightHalf)
        case 3:
            _ = snapFocusedWindow(to: .maximize)
        case 4:
            guard let window = accessibility.focusedWindow() else { return }
            if restoreStore.state(for: window) != nil {
                _ = restore(window)
            } else {
                accessibility.minimize(window)
            }
        case 5:
            moveFocusedWindowToAdjacentDisplay(direction: -1)
        case 6:
            moveFocusedWindowToAdjacentDisplay(direction: 1)
        default:
            return
        }
    }

    private func installKeyboardHotKeys() {
        guard hotKeyEventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let service = Unmanaged<WindowManagerService>
                .fromOpaque(userData)
                .takeUnretainedValue()
            Task { @MainActor in
                service.handleKeyboardHotKey(identifier: hotKeyID.id)
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyEventHandler
        )

        let signature = OSType(0x57544252) // WTBR
        let shortcuts: [(UInt32, UInt32, UInt32)] = [
            (1, UInt32(kVK_LeftArrow), UInt32(controlKey | optionKey)),
            (2, UInt32(kVK_RightArrow), UInt32(controlKey | optionKey)),
            (3, UInt32(kVK_UpArrow), UInt32(controlKey | optionKey)),
            (4, UInt32(kVK_DownArrow), UInt32(controlKey | optionKey)),
            (5, UInt32(kVK_LeftArrow), UInt32(controlKey | optionKey | shiftKey)),
            (6, UInt32(kVK_RightArrow), UInt32(controlKey | optionKey | shiftKey))
        ]
        for (identifier, keyCode, modifiers) in shortcuts {
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
            if RegisterEventHotKey(
                keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            ) == noErr {
                hotKeyReferences.append(reference)
            }
        }
    }

    private func removeKeyboardHotKeys() {
        hotKeyReferences.compactMap { $0 }.forEach { reference in
            _ = UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
            self.hotKeyEventHandler = nil
        }
    }

    private func handleMouseDown() {
        hideLayoutPanel()
        guard isAvailable, preferences.edgeSnappingEnabled,
              let point = currentQuartzPoint(),
              let window = accessibility.window(atQuartzPoint: point),
              let frame = accessibility.frame(of: window),
              accessibility.isMovable(window),
              point.y >= frame.minY - 3,
              point.y <= frame.minY + min(54, frame.height)
        else {
            dragCandidate = nil
            dragCandidateInitialFrame = nil
            return
        }
        dragCandidate = window
        dragCandidateInitialFrame = frame
    }

    private func handleMouseDragged() {
        guard isAvailable, preferences.edgeSnappingEnabled,
              var window = draggedWindow ?? dragCandidate,
              let point = currentQuartzPoint()
        else { return }

        if draggedWindow == nil {
            guard let initialFrame = dragCandidateInitialFrame,
                  let currentFrame = accessibility.frame(of: window),
                  Self.frameMoved(currentFrame, from: initialFrame)
            else { return }
            if restoreStore.state(for: window) != nil {
                _ = restore(window)
                if let refreshed = accessibility.window(atQuartzPoint: point) {
                    window = refreshed
                }
            }
            draggedWindow = window
        }

        guard let workArea = ScreenWorkArea.containing(
            quartzPoint: point,
            in: workAreas
        ), !(fullScreenDisplayIDsProvider?() ?? []).contains(workArea.displayID)
        else {
            activeZone = nil
            hidePreviewPanel()
            return
        }
        draggedWorkArea = workArea
        let zone = SnapLayoutPolicy.edgeZone(
            at: point,
            in: workArea.frame,
            activationDistance: CGFloat(preferences.snapActivationDistance)
        )
        activeZone = zone
        if let zone {
            showPreview(for: zone, window: window, workArea: workArea)
        } else {
            hidePreviewPanel()
        }
    }

    private func handleMouseUp() {
        defer {
            dragCandidate = nil
            dragCandidateInitialFrame = nil
            draggedWindow = nil
            draggedWorkArea = nil
            activeZone = nil
            hidePreviewPanel()
        }
        guard let window = draggedWindow,
              let workArea = draggedWorkArea,
              let zone = activeZone
        else { return }
        _ = snap(window, to: zone, preferredWorkArea: workArea)
    }

    private func handleMouseMoved() {
        guard isAvailable, preferences.snapLayoutsEnabled,
              let point = currentQuartzPoint()
        else {
            hideLayoutPanel()
            return
        }

        if layoutPanel?.frame.contains(NSEvent.mouseLocation) == true { return }
        guard let window = accessibility.focusedWindow(),
              !accessibility.isFullScreen(window),
              let zoomFrame = accessibility.zoomButtonFrame(of: window),
              zoomFrame.insetBy(dx: -5, dy: -5).contains(point)
        else {
            cancelHover()
            hideLayoutPanel()
            return
        }

        guard hoverIdentity != window.identity else { return }
        cancelHover()
        hoverIdentity = window.identity
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      let currentPoint = self.currentQuartzPoint(),
                      zoomFrame.insetBy(dx: -6, dy: -6).contains(currentPoint)
                else { return }
                self.showLayoutPanel(for: window, zoomButtonFrame: zoomFrame)
            }
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    func snap(
        _ window: AccessibilityWindow,
        to zone: SnapZone,
        preferredWorkArea: ScreenWorkArea? = nil
    ) -> WindowOperationResult {
        guard let currentFrame = accessibility.frame(of: window),
              !accessibility.isFullScreen(window)
        else { return .windowClosed }
        let workArea = preferredWorkArea
            ?? AccessibilityService.bestDisplayFrame(for: currentFrame, among: workAreas.map(\.displayFrame))
                .flatMap { displayFrame in
                    workAreas.first(where: { $0.displayFrame == displayFrame })
                }
        guard let workArea,
              !(fullScreenDisplayIDsProvider?() ?? []).contains(workArea.displayID)
        else { return .applicationRejectedFrame }

        restoreStore.record(
            window,
            frame: currentFrame,
            displayID: workArea.displayID,
            zone: zone
        )
        let result = accessibility.setFrame(
            SnapLayoutPolicy.frame(for: zone, in: workArea.frame),
            for: window
        )
        if result != .success, restoreStore.state(for: window)?.frame == currentFrame {
            restoreStore.remove(for: window)
        }
        hideOverlays()
        return result
    }

    func restore(_ window: AccessibilityWindow) -> WindowOperationResult {
        guard let state = restoreStore.remove(for: window) else {
            return .applicationRejectedFrame
        }
        let result = accessibility.setFrame(state.frame, for: window)
        if result != .success {
            restoreStore.record(
                window,
                frame: state.frame,
                displayID: state.displayID,
                zone: state.zone
            )
        }
        return result
    }

    private func moveFocusedWindowToAdjacentDisplay(direction: Int) {
        guard let window = accessibility.focusedWindow(),
              let frame = accessibility.frame(of: window),
              let current = ScreenWorkArea.containing(
                quartzPoint: CGPoint(x: frame.midX, y: frame.midY),
                in: workAreas
              )
        else { return }
        let ordered = workAreas.sorted { $0.displayFrame.midX < $1.displayFrame.midX }
        guard let index = ordered.firstIndex(where: { $0.displayID == current.displayID })
        else { return }
        let destinationIndex = min(max(0, index + direction), ordered.count - 1)
        guard destinationIndex != index else { return }
        let destination = ordered[destinationIndex]
        restoreStore.record(
            window,
            frame: frame,
            displayID: current.displayID,
            zone: .maximize
        )
        let width = min(frame.width, destination.frame.width)
        let height = min(frame.height, destination.frame.height)
        let target = CGRect(
            x: destination.frame.midX - width / 2,
            y: destination.frame.midY - height / 2,
            width: width,
            height: height
        )
        _ = accessibility.setFrame(target, for: window)
    }

    private func showPreview(
        for zone: SnapZone,
        window: AccessibilityWindow,
        workArea: ScreenWorkArea
    ) {
        let quartzFrame = SnapLayoutPolicy.frame(for: zone, in: workArea.frame)
        let appKitFrame = workArea.appKitRect(fromQuartz: quartzFrame)
        let panel = previewPanel ?? makeOverlayPanel(interactive: false)
        panel.contentView = NSHostingView(rootView: SnapPreviewView(zone: zone))
        panel.setFrame(appKitFrame, display: true, animate: previewPanel != nil)
        panel.orderFrontRegardless()
        previewPanel = panel
    }

    private func showLayoutPanel(
        for window: AccessibilityWindow,
        zoomButtonFrame: CGRect
    ) {
        guard let workArea = ScreenWorkArea.containing(
            quartzPoint: CGPoint(x: zoomButtonFrame.midX, y: zoomButtonFrame.midY),
            in: workAreas
        ) else { return }
        layoutWindow = window
        let size = CGSize(width: 420, height: workArea.frame.width >= 1_100 ? 245 : 185)
        let zoomAppKit = workArea.appKitRect(fromQuartz: zoomButtonFrame)
        var frame = CGRect(
            x: zoomAppKit.midX - size.width / 2,
            y: zoomAppKit.minY - size.height - 8,
            width: size.width,
            height: size.height
        )
        frame.origin.x = min(max(frame.minX, workArea.screenFrame.minX + 8), workArea.screenFrame.maxX - size.width - 8)
        frame.origin.y = min(max(frame.minY, workArea.screenFrame.minY + 8), workArea.screenFrame.maxY - size.height - 8)

        let panel = layoutPanel ?? makeOverlayPanel(interactive: true)
        panel.contentView = NSHostingView(rootView: SnapLayoutView(
            layouts: SnapLayoutPolicy.layouts(for: workArea.frame.width),
            onHover: { [weak self] zone in
                guard let self else { return }
                if let zone {
                    self.showPreview(for: zone, window: window, workArea: workArea)
                } else {
                    self.hidePreviewPanel()
                }
            },
            onSelect: { [weak self] zone in
                _ = self?.snap(window, to: zone, preferredWorkArea: workArea)
            }
        ))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        layoutPanel = panel
    }

    private func makeOverlayPanel(interactive: Bool) -> SnapOverlayPanel {
        let panel = SnapOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = interactive
        panel.ignoresMouseEvents = !interactive
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }

    private func hidePreviewPanel() {
        previewPanel?.orderOut(nil)
    }

    private func hideLayoutPanel() {
        layoutPanel?.orderOut(nil)
        layoutWindow = nil
        hoverIdentity = nil
    }

    private func hideOverlays() {
        hidePreviewPanel()
        hideLayoutPanel()
        activeZone = nil
    }

    private func cancelHover() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hoverIdentity = nil
    }

    private func currentQuartzPoint() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func frameMoved(_ current: CGRect, from initial: CGRect) -> Bool {
        abs(current.minX - initial.minX) > 2 || abs(current.minY - initial.minY) > 2
    }
}
