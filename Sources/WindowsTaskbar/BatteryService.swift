import Combine
import Foundation
import IOKit.ps

@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var percentage: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isOnACPower = false
    @Published private(set) var isFullyCharged = false
    @Published private(set) var isFinishingCharge = false
    @Published private(set) var timeRemainingMinutes: Int?
    @Published private(set) var timeToFullMinutes: Int?
    @Published private(set) var healthPercentage: Int?
    @Published private(set) var healthStatus: String?
    @Published private(set) var lowPowerModeEnabled = false
    @Published private(set) var adapterWatts: Int?

    private var notificationSource: CFRunLoopSource?
    private var refreshTimer: AnyCancellable?

    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        notificationSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.refresh() }
        }, context)?.takeRetainedValue()
        if let notificationSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), notificationSource, .commonModes)
        }
        refreshTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let notificationSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), notificationSource, .commonModes)
        }
    }

    var statusText: String {
        if percentage == nil { return "Battery information unavailable" }
        if isFullyCharged { return "Fully charged" }
        if isCharging { return "Charging" }
        if isOnACPower { return "Connected to power, not charging" }
        if let percentage, percentage <= 10 { return "Battery critically low" }
        if let percentage, percentage <= 20 { return "Battery low" }
        return "On battery power"
    }

    var timeRemainingText: String? {
        durationText(minutes: timeRemainingMinutes, suffix: "remaining")
    }

    var timeToFullText: String? {
        durationText(minutes: timeToFullMinutes, suffix: "until full")
    }

    var powerSourceText: String {
        if isOnACPower {
            return adapterWatts.map { "Power adapter · \($0)W" } ?? "Power adapter"
        }
        return "Battery"
    }

    var trayHelpText: String {
        let level = percentage.map { "\($0)%" } ?? "Battery"
        let timing = isCharging ? timeToFullText : timeRemainingText
        return [level, statusText, timing].compactMap { $0 }.joined(separator: " · ")
    }

    var isLowBattery: Bool {
        !isOnACPower && (percentage ?? 100) <= 20
    }

    private func durationText(minutes: Int?, suffix: String) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0
            ? "\(hours)h \(remainder)m \(suffix)"
            : "\(remainder)m \(suffix)"
    }

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        guard let percentage else { return "battery.0percent" }
        switch percentage {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 6...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            clear()
            return
        }

        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue()
                as? [String: Any]
        }
        guard let description = descriptions.first(where: {
            ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
                || ($0[kIOPSTransportTypeKey] as? String) == kIOPSInternalType
        }) ?? descriptions.first else {
            clear()
            return
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int
        let maximum = description[kIOPSMaxCapacityKey] as? Int
        if let current, let maximum, maximum > 0 {
            percentage = min(100, max(0, Int(
                (Double(current) / Double(maximum) * 100).rounded()
            )))
        } else {
            percentage = nil
        }

        if let maximum, let design = description[kIOPSDesignCapacityKey] as? Int, design > 0 {
            healthPercentage = min(100, Int((Double(maximum) / Double(design) * 100).rounded()))
        } else {
            healthPercentage = nil
        }

        isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        isOnACPower = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        isFullyCharged = description[kIOPSIsChargedKey] as? Bool
            ?? (percentage == 100 && isOnACPower && !isCharging)
        isFinishingCharge = description[kIOPSIsFinishingChargeKey] as? Bool ?? false
        lowPowerModeEnabled = description["LPM Active"] as? Bool ?? false
        healthStatus = description[kIOPSBatteryHealthConditionKey] as? String
            ?? description[kIOPSBatteryHealthKey] as? String

        if isOnACPower,
           let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()
                as? [String: Any] {
            adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        } else {
            adapterWatts = nil
        }

        let directTimeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
        let estimate = IOPSGetTimeRemainingEstimate()
        if !isOnACPower, let directTimeToEmpty, directTimeToEmpty > 0 {
            timeRemainingMinutes = directTimeToEmpty
        } else if !isOnACPower, estimate > 0, estimate.isFinite {
            timeRemainingMinutes = max(1, Int((estimate / 60).rounded()))
        } else {
            timeRemainingMinutes = nil
        }
        let directTimeToFull = description[kIOPSTimeToFullChargeKey] as? Int
        timeToFullMinutes = isCharging && (directTimeToFull ?? 0) > 0
            ? directTimeToFull
            : nil
    }

    private func clear() {
        percentage = nil
        isCharging = false
        isOnACPower = false
        isFullyCharged = false
        isFinishingCharge = false
        timeRemainingMinutes = nil
        timeToFullMinutes = nil
        healthPercentage = nil
        healthStatus = nil
        lowPowerModeEnabled = false
        adapterWatts = nil
    }
}
