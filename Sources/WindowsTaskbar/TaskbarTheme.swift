import SwiftUI

enum TaskbarTheme {
    private static let referenceIconSize: CGFloat = 36
    private static let referenceTaskbarHeight: CGFloat = 56
    private static let referenceButtonSize: CGFloat = 48

    static let horizontalPadding: CGFloat = 8
    static let flyoutCornerRadius: CGFloat = 8
    static let systemTrayIconSize: CGFloat = 20

    static let hoverBackground = Color.white.opacity(0.10)
    static let pressedBackground = Color.white.opacity(0.06)
    static let activeIndicator = Color(red: 0.38, green: 0.72, blue: 1.0)
    static let runningIndicator = Color.white.opacity(0.72)
    static let foreground = Color.white.opacity(0.95)

    static func height(for iconSize: CGFloat) -> CGFloat {
        iconSize * (referenceTaskbarHeight / referenceIconSize)
    }

    static func buttonSize(for iconSize: CGFloat) -> CGFloat {
        iconSize * (referenceButtonSize / referenceIconSize)
    }

    static func buttonSpacing(for iconSize: CGFloat) -> CGFloat {
        iconSize * 0.12
    }

    static func navigationIconSize(for appIconSize: CGFloat) -> CGFloat {
        min(48, max(21, appIconSize * 0.79))
    }

    static func startIconSize(for appIconSize: CGFloat) -> CGFloat {
        min(52, max(24, appIconSize * 0.92))
    }

    static func trayIconSize(for appIconSize: CGFloat) -> CGFloat {
        min(30, max(16, appIconSize * 0.58))
    }
}
