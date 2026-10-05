import CoreGraphics

struct FlyoutLayoutContext {
    let availableSize: CGSize
    var overflowAppCount = 0
    var previewWindowCount = 0
    var networkCount = 0
    var hasConnectedNetwork = false
    var networkIsPowered = true
    var networkIsAuthorized = true
    var hasPendingNetwork = false
    var hasNetworkError = false
    var bluetoothDeviceCount = 0
    var bluetoothIsPowered = true
    var hasPairingConfirmation = false
    var hasBluetoothError = false
    var batteryDetailCount = 1
    var hasConnectedBluetoothDevices = false
    var notificationCount = 0
}

enum FlyoutLayoutPolicy {
    static func preferredSize(
        for flyout: TaskbarFlyout,
        context: FlyoutLayoutContext
    ) -> CGSize {
        let proposed: CGSize

        switch flyout {
        case .start:
            proposed = CGSize(
                width: min(620, max(480, context.availableSize.width * 0.58)),
                height: min(600, max(440, context.availableSize.height * 0.68))
            )
        case .overflow:
            proposed = CGSize(
                width: 320,
                height: min(420, max(150, CGFloat(context.overflowAppCount * 45) + 60))
            )
        case .accessibility:
            proposed = CGSize(width: 440, height: 230)
        case .windowPreview:
            proposed = CGSize(
                width: 430,
                height: min(430, max(170, CGFloat(context.previewWindowCount * 65) + 70))
            )
        case .network:
            proposed = CGSize(width: 380, height: networkHeight(context))
        case .bluetooth:
            proposed = CGSize(width: 400, height: bluetoothHeight(context))
        case .volume:
            proposed = CGSize(width: 360, height: 165)
        case .battery:
            proposed = CGSize(
                width: 360,
                height: min(245, max(175, 150 + CGFloat(context.batteryDetailCount * 19)))
            )
        case .calendar:
            proposed = CGSize(width: 380, height: 500)
        case .quickSettings:
            proposed = CGSize(
                width: 420,
                height: context.hasConnectedBluetoothDevices ? 420 : 375
            )
        case .notificationCenter:
            let notificationArea = min(
                245,
                max(105, CGFloat(context.notificationCount * 61))
            )
            proposed = CGSize(width: 450, height: 335 + notificationArea)
        case .settings:
            proposed = CGSize(width: 480, height: 440)
        case .onboarding:
            proposed = CGSize(width: 560, height: 520)
        }

        return CGSize(
            width: min(proposed.width, context.availableSize.width),
            height: min(proposed.height, context.availableSize.height)
        )
    }

    private static func networkHeight(_ context: FlyoutLayoutContext) -> CGFloat {
        if context.hasPendingNetwork { return 320 }
        if !context.networkIsPowered { return 190 }
        if !context.networkIsAuthorized { return 300 }

        let rows = context.networkCount == 0
            ? 54
            : min(6, CGFloat(context.networkCount)) * 48
        let connected = context.hasConnectedNetwork ? 64 : 0
        let error = context.hasNetworkError ? 24 : 0
        return min(470, max(220, 116 + rows + connected + error))
    }

    private static func bluetoothHeight(_ context: FlyoutLayoutContext) -> CGFloat {
        if context.hasPairingConfirmation { return 310 }
        if !context.bluetoothIsPowered { return 210 }

        let rows = context.bluetoothDeviceCount == 0
            ? 80
            : min(5, CGFloat(context.bluetoothDeviceCount)) * 58
        let error = context.hasBluetoothError ? 28 : 0
        return min(470, max(260, 150 + rows + error))
    }
}
