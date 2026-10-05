import AppKit
import ApplicationServices
import Combine

struct AccessibilityWindow: Identifiable {
    let id: Int
    let title: String
    let isMinimized: Bool
    let isFocused: Bool
    fileprivate let element: AXUIElement
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

        return elements.compactMap { element in
            let role: String? = attribute(kAXRoleAttribute, from: element)
            guard role == kAXWindowRole as String else { return nil }
            let title: String = attribute(kAXTitleAttribute, from: element) ?? "Untitled Window"
            let minimized: Bool = attribute(kAXMinimizedAttribute, from: element) ?? false
            let focused: Bool = attribute(kAXFocusedAttribute, from: element)
                ?? attribute(kAXMainAttribute, from: element)
                ?? false
            return AccessibilityWindow(
                id: Int(truncatingIfNeeded: CFHash(element)),
                title: title.isEmpty ? "Untitled Window" : title,
                isMinimized: minimized,
                isFocused: focused,
                element: element
            )
        }
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

        let displayFrames = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let id = screen.displayID else { return nil }
            if let displayIDs, !displayIDs.contains(id) { return nil }
            return CGDisplayBounds(id)
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
                      let screen = displayFrames.first(where: {
                          $0.contains(CGPoint(x: position.x + 2, y: position.y + 2))
                      })
                else { continue }

                let isFullScreen = abs(position.x - screen.minX) <= 2
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
                AXUIElementSetAttributeValue(
                    window,
                    kAXSizeAttribute as CFString,
                    sizeValue
                )
            }
        }
    }

    private func setMinimized(_ minimized: Bool, for window: AccessibilityWindow) {
        AXUIElementSetAttributeValue(
            window.element,
            kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse
        )
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
