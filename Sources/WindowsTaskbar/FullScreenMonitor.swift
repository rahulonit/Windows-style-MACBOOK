import AppKit
import ApplicationServices
import ColorSync
import CoreGraphics
import Darwin

enum FullScreenMonitor {
    static func fullScreenDisplayIDs() -> Set<CGDirectDisplayID> {
        let spaceDisplayIDs = fullScreenSpaceDisplayIDs()
        let regularApplications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        let regularApplicationIDs = Set(regularApplications.map(\.processIdentifier))
        guard !regularApplicationIDs.isEmpty,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else { return [] }

        let displayFrames = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let id = screen.displayID else { return nil }
            return (id, CGDisplayBounds(id))
        }

        var onScreenBoundsByProcess: [pid_t: [CGRect]] = [:]
        for info in windowInfo {
            guard
                let ownerProcessID = info[kCGWindowOwnerPID as String] as? Int32,
                regularApplicationIDs.contains(ownerProcessID),
                (info[kCGWindowLayer as String] as? Int) == 0,
                let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }
            onScreenBoundsByProcess[ownerProcessID, default: []].append(bounds)
        }

        var result = spaceDisplayIDs
        result.formUnion(displayIDsFilled(
            by: onScreenBoundsByProcess.values.flatMap { $0 },
            displayFrames: displayFrames
        ))

        // AXFullScreen is not consistently exposed by every application, so it
        // supplements rather than replaces the geometry fallback above.
        for application in regularApplications {
            guard let visibleBounds = onScreenBoundsByProcess[application.processIdentifier],
                  !visibleBounds.isEmpty
            else { continue }

            let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows: [AXUIElement] = accessibilityAttribute(
                kAXWindowsAttribute as String,
                from: applicationElement
            ) else { continue }

            for window in windows {
                let isFullScreen: Bool = accessibilityAttribute("AXFullScreen", from: window) ?? false
                guard isFullScreen,
                      let position = accessibilityPoint(kAXPositionAttribute as String, from: window),
                      let size = accessibilitySize(kAXSizeAttribute as String, from: window)
                else { continue }

                let bounds = CGRect(origin: position, size: size)
                for (displayID, displayFrame) in displayFrames {
                    let hasVisibleWindowOnDisplay = visibleBounds.contains {
                        intersectionCoverage(of: $0, in: displayFrame) > 0.5
                    }
                    if hasVisibleWindowOnDisplay,
                       intersectionCoverage(of: bounds, in: displayFrame) > 0.5 {
                        result.insert(displayID)
                    }
                }
            }
        }
        return result
    }

    /// Native macOS full-screen and Split View run in non-user Spaces. Window
    /// bounds are not reliable for browser/video full-screen modes, so inspect
    /// the current Space for each display first and use bounds only as fallback.
    private static func fullScreenSpaceDisplayIDs() -> Set<CGDirectDisplayID> {
        typealias MainConnectionFunction = @convention(c) () -> UInt32
        typealias CopySpacesFunction = @convention(c) (UInt32) -> Unmanaged<CFArray>?

        guard let framework = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ) else { return [] }
        defer { dlclose(framework) }

        guard let mainSymbol = dlsym(framework, "CGSMainConnectionID"),
              let spacesSymbol = dlsym(framework, "CGSCopyManagedDisplaySpaces")
        else { return [] }

        let mainConnection = unsafeBitCast(
            mainSymbol,
            to: MainConnectionFunction.self
        )
        let copySpaces = unsafeBitCast(
            spacesSymbol,
            to: CopySpacesFunction.self
        )
        guard let managedSpaces = copySpaces(mainConnection())?.takeRetainedValue()
            as? [[String: Any]]
        else { return [] }

        let fullScreenDisplayIdentifiers = fullScreenDisplayIdentifiers(
            in: managedSpaces
        )
        guard !fullScreenDisplayIdentifiers.isEmpty else { return [] }

        return Set(NSScreen.screens.compactMap { screen in
            guard let displayID = screen.displayID,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
                  let uuidString = CFUUIDCreateString(nil, uuid) as String?,
                  fullScreenDisplayIdentifiers.contains(uuidString.uppercased())
            else { return nil }
            return displayID
        })
    }

    static func fullScreenDisplayIdentifiers(
        in managedSpaces: [[String: Any]]
    ) -> Set<String> {
        Set(managedSpaces.compactMap { display in
            guard let identifier = display["Display Identifier"] as? String,
                  let currentSpace = display["Current Space"] as? [String: Any],
                  let type = currentSpace["type"] as? Int,
                  type != 0
            else { return nil }
            return identifier.uppercased()
        })
    }

    static func displayIDsFilled(
        by windowBounds: [CGRect],
        displayFrames: [(CGDirectDisplayID, CGRect)]
    ) -> Set<CGDirectDisplayID> {
        var result: Set<CGDirectDisplayID> = []
        for bounds in windowBounds {
            for (displayID, displayFrame) in displayFrames {
                let widthCoverage = bounds.width / displayFrame.width
                let heightCoverage = bounds.height / displayFrame.height
                let areaCoverage = intersectionCoverage(of: bounds, in: displayFrame)
                let fillsByCoverage = widthCoverage >= 0.98
                    && heightCoverage >= 0.98
                    && areaCoverage >= 0.975
                let fillsFromTopEdge = abs(bounds.minX - displayFrame.minX) <= 3
                    && abs(bounds.maxX - displayFrame.maxX) <= 3
                    && abs(bounds.minY - displayFrame.minY) <= 3
                    && heightCoverage >= 0.95
                    && areaCoverage >= 0.95
                if fillsByCoverage || fillsFromTopEdge {
                    result.insert(displayID)
                }
            }
        }
        return result
    }

    private static func intersectionCoverage(of bounds: CGRect, in displayFrame: CGRect) -> CGFloat {
        guard displayFrame.width > 0, displayFrame.height > 0 else { return 0 }
        let intersection = bounds.intersection(displayFrame)
        guard !intersection.isNull else { return 0 }
        return (intersection.width * intersection.height)
            / (displayFrame.width * displayFrame.height)
    }

    private static func accessibilityAttribute<T>(
        _ name: String,
        from element: AXUIElement
    ) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else { return nil }
        return value as? T
    }

    private static func accessibilityPoint(
        _ name: String,
        from element: AXUIElement
    ) -> CGPoint? {
        guard let value: AXValue = accessibilityAttribute(name, from: element) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func accessibilitySize(
        _ name: String,
        from element: AXUIElement
    ) -> CGSize? {
        guard let value: AXValue = accessibilityAttribute(name, from: element) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
