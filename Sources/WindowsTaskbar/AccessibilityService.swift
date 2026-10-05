import AppKit
import ApplicationServices
import Combine

struct AccessibilityWindow: Identifiable {
    let id: Int
    let processIdentifier: pid_t
    let title: String
    let isMinimized: Bool
    let isFocused: Bool
    let element: AXUIElement

    var identity: WindowIdentity {
        WindowIdentity(processIdentifier: processIdentifier, elementIdentifier: id)
    }
}

enum WindowOperationResult: Equatable {
    case success
    case accessibilityUnavailable
    case windowNotResizable
    case windowNotMovable
    case applicationRejectedFrame
    case windowClosed
}

@MainActor
final class AccessibilityService: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    func refreshAuthorization() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestAuthorization() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func windows(for application: NSRunningApplication) -> [AccessibilityWindow] {
        guard isTrusted else { return [] }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let elements: [AXUIElement] = attribute(kAXWindowsAttribute, from: applicationElement) else {
            return []
        }

        return elements.compactMap {
            windowDescriptor(for: $0, processIdentifier: application.processIdentifier)
        }
    }

    func focusedWindow() -> AccessibilityWindow? {
        refreshAuthorization()
        guard isTrusted,
              let application = NSWorkspace.shared.frontmostApplication,
              application.activationPolicy == .regular
        else { return nil }
        return focusedWindow(for: application)
    }

    func focusedWindow(for application: NSRunningApplication) -> AccessibilityWindow? {
        guard isTrusted else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        if let element: AXUIElement = attribute(
            kAXFocusedWindowAttribute,
            from: applicationElement
        ), let descriptor = windowDescriptor(
            for: element,
            processIdentifier: application.processIdentifier
        ) {
            return descriptor
        }
        return windows(for: application).first(where: { !$0.isMinimized })
    }

    func window(atQuartzPoint point: CGPoint) -> AccessibilityWindow? {
        refreshAuthorization()
        guard isTrusted else { return nil }
        var candidate: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &candidate
        ) == .success, var element = candidate else { return nil }

        for _ in 0..<8 {
            let role: String? = attribute(kAXRoleAttribute, from: element)
            if role == kAXWindowRole as String {
                var processIdentifier: pid_t = 0
                AXUIElementGetPid(element, &processIdentifier)
                return windowDescriptor(
                    for: element,
                    processIdentifier: processIdentifier
                )
            }
            guard let parent: AXUIElement = attribute(kAXParentAttribute, from: element)
            else { return nil }
            element = parent
        }
        return nil
    }

    func frame(of window: AccessibilityWindow) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: window.element),
              let size = sizeAttribute(kAXSizeAttribute, from: window.element)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    func zoomButtonFrame(of window: AccessibilityWindow) -> CGRect? {
        guard let button: AXUIElement = attribute(
            kAXZoomButtonAttribute,
            from: window.element
        ), let position = pointAttribute(kAXPositionAttribute, from: button),
           let size = sizeAttribute(kAXSizeAttribute, from: button)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    func isMovable(_ window: AccessibilityWindow) -> Bool {
        isAttributeSettable(kAXPositionAttribute, on: window.element)
    }

    func isResizable(_ window: AccessibilityWindow) -> Bool {
        isAttributeSettable(kAXSizeAttribute, on: window.element)
    }

    func setFrame(
        _ requestedFrame: CGRect,
        for window: AccessibilityWindow
    ) -> WindowOperationResult {
        refreshAuthorization()
        guard isTrusted else { return .accessibilityUnavailable }
        guard frame(of: window) != nil else { return .windowClosed }
        guard isMovable(window) else { return .windowNotMovable }
        guard isResizable(window) else { return .windowNotResizable }

        var position = requestedFrame.origin
        var size = requestedFrame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return .applicationRejectedFrame }

        let positionResult = AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            window.element,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        // A size constraint can shift a window, so re-apply its position.
        AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard positionResult == .success, sizeResult == .success,
              let resultingFrame = frame(of: window),
              framesApproximatelyEqual(resultingFrame, requestedFrame)
        else { return .applicationRejectedFrame }
        return .success
    }

    func isFullScreen(_ window: AccessibilityWindow) -> Bool {
        let fullScreen: Bool = attribute("AXFullScreen", from: window.element) ?? false
        return fullScreen
    }

    func toggle(_ window: AccessibilityWindow, application: NSRunningApplication) {
        if window.isMinimized {
            restore(window, application: application)
        } else if window.isFocused {
            setMinimized(true, for: window)
        } else {
            activate(window, application: application)
        }
    }

    func activate(_ window: AccessibilityWindow, application: NSRunningApplication) {
        setMinimized(false, for: window)
        application.activate(options: [.activateAllWindows])
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    func restore(_ window: AccessibilityWindow, application: NSRunningApplication) {
        setMinimized(false, for: window)
        activate(window, application: application)
    }

    func minimize(_ window: AccessibilityWindow) {
        setMinimized(true, for: window)
    }

    func close(_ window: AccessibilityWindow) {
        guard let closeButton: AXUIElement = attribute(
            kAXCloseButtonAttribute,
            from: window.element
        ) else { return }
        AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
    }

    func adaptApplicationWindows(
        from oldTaskbarHeight: CGFloat,
        to newTaskbarHeight: CGFloat,
        on displayIDs: Set<CGDirectDisplayID>? = nil
    ) {
        refreshAuthorization()
        guard isTrusted else { return }

        let displayFrames = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let id = screen.displayID else { return nil }
            if let displayIDs, !displayIDs.contains(id) { return nil }
            return (id, CGDisplayBounds(id))
        }

        for application in NSWorkspace.shared.runningApplications
        where application.activationPolicy == .regular {
            let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows: [AXUIElement] = attribute(
                kAXWindowsAttribute,
                from: applicationElement
            ) else { continue }

            for window in windows {
                let minimized: Bool = attribute(kAXMinimizedAttribute, from: window) ?? false
                let subrole: String? = attribute(kAXSubroleAttribute, from: window)
                guard !minimized,
                      subrole == kAXStandardWindowSubrole as String,
                      let position = pointAttribute(kAXPositionAttribute, from: window),
                      let size = sizeAttribute(kAXSizeAttribute, from: window),
                      let screen = Self.bestDisplayFrame(
                        for: CGRect(origin: position, size: size),
                        among: displayFrames.map(\.1)
                      )
                else { continue }

                let accessibilityFullScreen: Bool = attribute("AXFullScreen", from: window)
                    ?? false
                let isFullScreen = accessibilityFullScreen
                    || abs(position.x - screen.minX) <= 2
                    && abs(position.y - screen.minY) <= 2
                    && abs(size.width - screen.width) <= 3
                    && abs(size.height - screen.height) <= 3
                if isFullScreen { continue }

                let currentBottom = position.y + size.height
                let oldAllowedBottom = screen.maxY - oldTaskbarHeight
                let newAllowedBottom = screen.maxY - newTaskbarHeight
                let overlapsNewTaskbar = currentBottom > newAllowedBottom + 1
                let wasAlignedToOldTaskbar = abs(currentBottom - oldAllowedBottom) <= 4
                let taskbarHeightChanged = abs(oldTaskbarHeight - newTaskbarHeight) > 0.01
                guard overlapsNewTaskbar || (taskbarHeightChanged && wasAlignedToOldTaskbar)
                else { continue }

                let availableHeight = max(180, newAllowedBottom - position.y)
                var newSize = CGSize(width: size.width, height: availableHeight)
                guard let sizeValue = AXValueCreate(.cgSize, &newSize) else { continue }
                let sizeResult = AXUIElementSetAttributeValue(
                    window,
                    kAXSizeAttribute as CFString,
                    sizeValue
                )

                // Some applications constrain or ignore direct size changes.
                // Re-read their frame and move any remaining overlap above the
                // taskbar while keeping the title bar on its display.
                let adjustedPosition = pointAttribute(kAXPositionAttribute, from: window)
                    ?? position
                let adjustedSize = sizeAttribute(kAXSizeAttribute, from: window)
                    ?? (sizeResult == .success ? newSize : size)
                let remainingOverlap = adjustedPosition.y
                    + adjustedSize.height
                    - newAllowedBottom
                if remainingOverlap > 1 {
                    var newPosition = CGPoint(
                        x: adjustedPosition.x,
                        y: max(screen.minY, adjustedPosition.y - remainingOverlap)
                    )
                    if let positionValue = AXValueCreate(.cgPoint, &newPosition) {
                        AXUIElementSetAttributeValue(
                            window,
                            kAXPositionAttribute as CFString,
                            positionValue
                        )
                    }
                }
            }
        }
    }

    static func bestDisplayFrame(
        for windowFrame: CGRect,
        among displayFrames: [CGRect]
    ) -> CGRect? {
        guard let bestMatch = displayFrames.max(by: { lhs, rhs in
            intersectionArea(windowFrame, lhs) < intersectionArea(windowFrame, rhs)
        }) else { return nil }
        return intersectionArea(windowFrame, bestMatch) > 0 ? bestMatch : nil
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func setMinimized(_ minimized: Bool, for window: AccessibilityWindow) {
        AXUIElementSetAttributeValue(
            window.element,
            kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse
        )
    }

    private func windowDescriptor(
        for element: AXUIElement,
        processIdentifier: pid_t
    ) -> AccessibilityWindow? {
        let role: String? = attribute(kAXRoleAttribute, from: element)
        guard role == kAXWindowRole as String else { return nil }
        let subrole: String? = attribute(kAXSubroleAttribute, from: element)
        guard subrole == nil || subrole == kAXStandardWindowSubrole as String
                || subrole == kAXDialogSubrole as String
        else { return nil }
        let title: String = attribute(kAXTitleAttribute, from: element) ?? "Untitled Window"
        let minimized: Bool = attribute(kAXMinimizedAttribute, from: element) ?? false
        let focused: Bool = attribute(kAXFocusedAttribute, from: element)
            ?? attribute(kAXMainAttribute, from: element)
            ?? false
        return AccessibilityWindow(
            id: Int(truncatingIfNeeded: CFHash(element)),
            processIdentifier: processIdentifier,
            title: title.isEmpty ? "Untitled Window" : title,
            isMinimized: minimized,
            isFocused: focused,
            element: element
        )
    }

    private func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            name as CFString,
            &settable
        ) == .success else { return false }
        return settable.boolValue
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 3
            && abs(lhs.minY - rhs.minY) <= 3
            && abs(lhs.width - rhs.width) <= 4
            && abs(lhs.height - rhs.height) <= 4
    }

    private func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func pointAttribute(_ name: String, from element: AXUIElement) -> CGPoint? {
        guard let value: AXValue = attribute(name, from: element) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
        guard let value: AXValue = attribute(name, from: element) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }
}
