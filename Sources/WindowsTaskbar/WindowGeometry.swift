import AppKit
import CoreGraphics

enum SnapZone: String, CaseIterable, Identifiable {
    case maximize
    case leftHalf
    case rightHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .maximize: return "Maximize window"
        case .leftHalf: return "Snap window to left half"
        case .rightHalf: return "Snap window to right half"
        case .topLeft: return "Snap window to top-left quarter"
        case .topRight: return "Snap window to top-right quarter"
        case .bottomLeft: return "Snap window to bottom-left quarter"
        case .bottomRight: return "Snap window to bottom-right quarter"
        case .leftThird: return "Snap window to left third"
        case .centerThird: return "Snap window to center third"
        case .rightThird: return "Snap window to right third"
        case .leftTwoThirds: return "Snap window to left two-thirds"
        case .rightTwoThirds: return "Snap window to right two-thirds"
        }
    }
}

struct ScreenWorkArea: Identifiable, Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let displayFrame: CGRect
    let frame: CGRect

    var id: CGDirectDisplayID { displayID }

    static func current(
        taskbarHeight: CGFloat,
        taskbarDisplayIDs: Set<CGDirectDisplayID>
    ) -> [ScreenWorkArea] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = screen.displayID else { return nil }
            let displayFrame = CGDisplayBounds(displayID)
            let topInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let bottomInset = taskbarDisplayIDs.contains(displayID) ? taskbarHeight : 0
            let height = max(180, displayFrame.height - topInset - bottomInset)
            return ScreenWorkArea(
                displayID: displayID,
                screenFrame: screen.frame,
                displayFrame: displayFrame,
                frame: CGRect(
                    x: displayFrame.minX,
                    y: displayFrame.minY + topInset,
                    width: displayFrame.width,
                    height: height
                )
            )
        }
    }

    static func containing(
        quartzPoint: CGPoint,
        in workAreas: [ScreenWorkArea]
    ) -> ScreenWorkArea? {
        workAreas.first(where: { $0.displayFrame.contains(quartzPoint) })
            ?? workAreas.min(by: {
                distance(from: quartzPoint, to: $0.displayFrame)
                    < distance(from: quartzPoint, to: $1.displayFrame)
            })
    }

    func appKitRect(fromQuartz rect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX - displayFrame.minX,
            y: screenFrame.maxY - (rect.maxY - displayFrame.minY),
            width: rect.width,
            height: rect.height
        )
    }

    func appKitPoint(fromQuartz point: CGPoint) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + point.x - displayFrame.minX,
            y: screenFrame.maxY - (point.y - displayFrame.minY)
        )
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

enum SnapLayoutPolicy {
    static func frame(for zone: SnapZone, in workArea: CGRect) -> CGRect {
        let halfWidth = floor(workArea.width / 2)
        let halfHeight = floor(workArea.height / 2)
        let thirdWidth = floor(workArea.width / 3)

        switch zone {
        case .maximize:
            return workArea
        case .leftHalf:
            return CGRect(
                x: workArea.minX,
                y: workArea.minY,
                width: halfWidth,
                height: workArea.height
            )
        case .rightHalf:
            return CGRect(
                x: workArea.minX + halfWidth,
                y: workArea.minY,
                width: workArea.width - halfWidth,
                height: workArea.height
            )
        case .topLeft:
            return CGRect(
                x: workArea.minX,
                y: workArea.minY,
                width: halfWidth,
                height: halfHeight
            )
        case .topRight:
            return CGRect(
                x: workArea.minX + halfWidth,
                y: workArea.minY,
                width: workArea.width - halfWidth,
                height: halfHeight
            )
        case .bottomLeft:
            return CGRect(
                x: workArea.minX,
                y: workArea.minY + halfHeight,
                width: halfWidth,
                height: workArea.height - halfHeight
            )
        case .bottomRight:
            return CGRect(
                x: workArea.minX + halfWidth,
                y: workArea.minY + halfHeight,
                width: workArea.width - halfWidth,
                height: workArea.height - halfHeight
            )
        case .leftThird:
            return CGRect(
                x: workArea.minX,
                y: workArea.minY,
                width: thirdWidth,
                height: workArea.height
            )
        case .centerThird:
            return CGRect(
                x: workArea.minX + thirdWidth,
                y: workArea.minY,
                width: thirdWidth,
                height: workArea.height
            )
        case .rightThird:
            return CGRect(
                x: workArea.minX + thirdWidth * 2,
                y: workArea.minY,
                width: workArea.width - thirdWidth * 2,
                height: workArea.height
            )
        case .leftTwoThirds:
            return CGRect(
                x: workArea.minX,
                y: workArea.minY,
                width: thirdWidth * 2,
                height: workArea.height
            )
        case .rightTwoThirds:
            return CGRect(
                x: workArea.minX + thirdWidth,
                y: workArea.minY,
                width: workArea.width - thirdWidth,
                height: workArea.height
            )
        }
    }

    static func layouts(for width: CGFloat) -> [[SnapZone]] {
        var result: [[SnapZone]] = [
            [.leftHalf, .rightHalf],
            [.maximize],
            [.topLeft, .topRight, .bottomLeft, .bottomRight]
        ]
        if width >= 1_100 {
            result.append([.leftTwoThirds, .rightThird])
            result.append([.leftThird, .centerThird, .rightThird])
        }
        return result
    }

    static func edgeZone(
        at point: CGPoint,
        in workArea: CGRect,
        activationDistance: CGFloat
    ) -> SnapZone? {
        let edge = max(4, activationDistance)
        let corner = edge * 2.2
        let nearLeft = point.x <= workArea.minX + edge
        let nearRight = point.x >= workArea.maxX - edge
        let nearTop = point.y <= workArea.minY + edge
        let nearBottom = point.y >= workArea.maxY - edge

        if nearLeft && point.y <= workArea.minY + corner { return .topLeft }
        if nearRight && point.y <= workArea.minY + corner { return .topRight }
        if nearLeft && point.y >= workArea.maxY - corner { return .bottomLeft }
        if nearRight && point.y >= workArea.maxY - corner { return .bottomRight }
        if nearTop { return .maximize }
        if nearBottom {
            return point.x < workArea.midX ? .bottomLeft : .bottomRight
        }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        return nil
    }
}
