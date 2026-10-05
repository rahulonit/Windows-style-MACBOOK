import CoreGraphics

struct TaskbarLayoutResult: Equatable {
    let visibleAppCount: Int
    let overflowCount: Int
}

enum TaskbarLayoutPolicy {
    private static let controlCount = 3

    static func calculate(
        screenWidth: CGFloat,
        appCount: Int,
        iconSize: CGFloat = 36,
        leadingRegionWidth: CGFloat = 250,
        trailingRegionWidth: CGFloat = 250,
        horizontalPadding: CGFloat = TaskbarTheme.horizontalPadding
    ) -> TaskbarLayoutResult {
        let itemStride = TaskbarTheme.buttonSize(for: iconSize)
            + TaskbarTheme.buttonSpacing(for: iconSize)
        // The app strip is centered on the display, so both sides must reserve
        // the width of the larger edge region. This prevents the centered strip
        // from colliding with either weather or the system tray.
        let sideReservation = max(leadingRegionWidth, trailingRegionWidth)
            + horizontalPadding
        let centeredWidth = max(0, screenWidth - (sideReservation * 2))
        let totalSlots = max(0, Int(centeredWidth / itemStride))
        let appSlotsWithoutOverflow = max(0, totalSlots - controlCount)

        guard appCount > appSlotsWithoutOverflow else {
            return TaskbarLayoutResult(visibleAppCount: appCount, overflowCount: 0)
        }

        let visibleCount = max(0, appSlotsWithoutOverflow - 1)
        return TaskbarLayoutResult(
            visibleAppCount: visibleCount,
            overflowCount: appCount - visibleCount
        )
    }
}
