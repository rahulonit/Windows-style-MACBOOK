import SwiftUI

struct NotificationTrayButton: View {
    @ObservedObject var service: TaskbarNotificationService
    let iconSize: CGFloat
    let controlHeight: CGFloat
    let action: () -> Void

    private var unreadCount: Int { service.unreadCount }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: iconSize))
                    .frame(width: max(22, iconSize + 6), height: controlHeight)
                if unreadCount > 0 {
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 3, y: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .help(unreadCount > 0 ? "\(unreadCount) unread notifications" : "Notifications")
        .accessibilityLabel("Notifications")
    }
}

struct NetworkTrayButton: View {
    @ObservedObject var service: NetworkService
    let iconSize: CGFloat
    let controlHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: service.isPowered ? "wifi" : "wifi.slash")
                .font(.system(size: iconSize))
                .frame(width: max(20, iconSize + 6), height: controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .help(service.networkName ?? (service.isPowered ? "Wi-Fi" : "Wi-Fi off"))
        .accessibilityLabel("Wi-Fi controls")
    }
}

struct AudioTrayButton: View {
    @ObservedObject var service: AudioService
    let iconSize: CGFloat
    let controlHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: iconSize))
                .frame(width: max(20, iconSize + 6), height: controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .help(service.isMuted ? "Muted" : "Volume \(Int(service.volume * 100))%")
        .accessibilityLabel("Volume controls")
    }

    private var symbolName: String {
        if service.isMuted { return "speaker.slash.fill" }
        switch service.volume {
        case 0: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

struct BatteryTrayButton: View {
    @ObservedObject var service: BatteryService
    let iconSize: CGFloat
    let controlHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: service.symbolName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(service.isLowBattery ? .red : .primary)
                Text(service.percentage.map { "\($0)%" } ?? "--")
                    .font(.system(size: 10, weight: service.isLowBattery ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(service.isLowBattery ? .red : .primary)
            }
            .frame(height: controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .help(service.trayHelpText)
        .accessibilityLabel("Battery status")
        .accessibilityValue(service.trayHelpText)
    }
}
