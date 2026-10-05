import AppKit
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
    private var globalKeyboardMonitor: Any?
    private var hoverWorkItem: DispatchWorkItem?
    private var hoverIdentity: WindowIdentity?
    private var layoutWindow: AccessibilityWindow?
    private var dragCandidate: AccessibilityWindow?
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
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            Task { @MainActor in self?.handleKeyboard(event) }
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
        if let globalKeyboardMonitor { NSEvent.removeMonitor(globalKeyboardMonitor) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        localMonitor = nil
        globalMouseMonitor = nil
        globalKeyboardMonitor = nil
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
        case .keyDown:
            handleKeyboard(event)
        default:
            break
        }
    }

    private func handleKeyboard(_ event: NSEvent) {
        guard isAvailable, preferences.keyboardSnappingEnabled else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains([.control, .option]) else { return }

        if modifiers.contains(.shift) {
            if event.keyCode == 123 { moveFocusedWindowToAdjacentDisplay(direction: -1) }
            if event.keyCode == 124 { moveFocusedWindowToAdjacentDisplay(direction: 1) }
            return
        }

        switch event.keyCode {
        case 123:
            _ = snapFocusedWindow(to: .leftHalf)
        case 124:
            _ = snapFocusedWindow(to: .rightHalf)
        case 126:
            _ = snapFocusedWindow(to: .maximize)
        case 125:
            guard let window = accessibility.focusedWindow() else { return }
            if restoreStore.state(for: window) != nil {
                _ = restore(window)
            } else {
                accessibility.minimize(window)
            }
        default:
            return
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
            return
        }
        dragCandidate = window
    }

    private func handleMouseDragged() {
        guard isAvailable, preferences.edgeSnappingEnabled,
              var window = draggedWindow ?? dragCandidate,
              let point = currentQuartzPoint()
        else { return }

        if draggedWindow == nil {
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

    private func snap(
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

    private func restore(_ window: AccessibilityWindow) -> WindowOperationResult {
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
}
