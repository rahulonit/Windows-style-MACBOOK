import Combine
import Foundation

struct TaskbarNotification: Identifiable, Equatable {
    enum Category {
        case network
        case battery
        case bluetooth
        case application
        case system
    }

    let id: UUID
    let title: String
    let message: String
    let date: Date
    let symbolName: String
    let category: Category

    init(
        title: String,
        message: String,
        symbolName: String,
        category: Category,
        date: Date = Date()
    ) {
        id = UUID()
        self.title = title
        self.message = message
        self.date = date
        self.symbolName = symbolName
        self.category = category
    }
}

@MainActor
final class TaskbarNotificationService: ObservableObject {
    @Published private(set) var notifications: [TaskbarNotification] = []
    @Published private(set) var unreadCount = 0

    private var cancellables: Set<AnyCancellable> = []
    private var lastLowBatteryLevel: Int?
    private let duplicateSuppressionInterval: TimeInterval

    init(
        networkService: NetworkService,
        batteryService: BatteryService,
        bluetoothService: BluetoothService,
        duplicateSuppressionInterval: TimeInterval = 5 * 60
    ) {
        self.duplicateSuppressionInterval = duplicateSuppressionInterval
        post(
            title: "Windows Taskbar",
            message: "Notification Center is ready.",
            symbolName: "checkmark.circle.fill",
            category: .system,
            unread: false
        )

        networkService.$networkName
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] networkName in
                if let networkName {
                    self?.post(
                        title: "Wi-Fi connected",
                        message: networkName,
                        symbolName: "wifi",
                        category: .network
                    )
                } else {
                    self?.post(
                        title: "Wi-Fi disconnected",
                        message: "No wireless network is connected.",
                        symbolName: "wifi.slash",
                        category: .network
                    )
                }
            }
            .store(in: &cancellables)

        batteryService.$percentage
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] percentage in
                guard let self else { return }
                if percentage <= 20, lastLowBatteryLevel == nil || percentage <= 10 {
                    lastLowBatteryLevel = percentage
                    post(
                        title: percentage <= 10 ? "Battery critically low" : "Battery low",
                        message: "\(percentage)% remaining",
                        symbolName: "battery.25percent",
                        category: .battery
                    )
                } else if percentage > 20 {
                    lastLowBatteryLevel = nil
                }
            }
            .store(in: &cancellables)

        batteryService.$isCharging
            .dropFirst()
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.post(
                    title: "Power connected",
                    message: "The battery is charging.",
                    symbolName: "bolt.fill",
                    category: .battery
                )
            }
            .store(in: &cancellables)

        bluetoothService.$connectedDeviceNames
            .dropFirst()
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .sink { [weak self] devices in
                self?.post(
                    title: "Bluetooth connected",
                    message: devices.joined(separator: ", "),
                    symbolName: "bluetooth",
                    category: .bluetooth
                )
            }
            .store(in: &cancellables)
    }

    func postApplicationEvent(name: String, launched: Bool) {
        post(
            title: launched ? "Application started" : "Application closed",
            message: name,
            symbolName: launched ? "app.badge.checkmark" : "app.badge",
            category: .application
        )
    }

    func dismiss(_ notification: TaskbarNotification) {
        notifications.removeAll { $0.id == notification.id }
    }

    func clearAll() {
        notifications.removeAll()
        unreadCount = 0
    }

    func markAllRead() {
        unreadCount = 0
    }

    private func post(
        title: String,
        message: String,
        symbolName: String,
        category: TaskbarNotification.Category,
        unread: Bool = true
    ) {
        let now = Date()
        let notification = TaskbarNotification(
            title: title,
            message: message,
            symbolName: symbolName,
            category: category,
            date: now
        )

        if shouldCoalesce(category),
           let duplicateIndex = notifications.firstIndex(where: {
               $0.title == title
                   && $0.message == message
                   && $0.category == category
                   && now.timeIntervalSince($0.date) <= duplicateSuppressionInterval
           }) {
            // Refresh the existing event's timestamp and position without
            // increasing its unread count or filling the panel with duplicates.
            notifications.remove(at: duplicateIndex)
            notifications.insert(notification, at: 0)
            return
        }

        notifications.insert(notification, at: 0)
        if notifications.count > 30 {
            notifications.removeLast(notifications.count - 30)
        }
        if unread { unreadCount += 1 }
    }

    private func shouldCoalesce(_ category: TaskbarNotification.Category) -> Bool {
        switch category {
        case .network, .battery, .bluetooth, .system:
            return true
        case .application:
            return false
        }
    }
}
