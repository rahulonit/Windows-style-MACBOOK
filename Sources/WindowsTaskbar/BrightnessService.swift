import Combine
import Foundation
import IOKit
import IOKit.graphics

@MainActor
final class BrightnessService: ObservableObject {
    @Published private(set) var brightness: Double = 0.5
    @Published private(set) var isAvailable = false

    private var refreshTimer: Timer?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    func refresh() {
        var foundValue: Float?
        forEachDisplayService { service in
            var value: Float = 0
            if IODisplayGetFloatParameter(
                service, 0, "brightness" as CFString, &value
            ) == kIOReturnSuccess, foundValue == nil {
                foundValue = value
            }
        }
        if let foundValue {
            brightness = Double(foundValue)
            isAvailable = true
        } else {
            isAvailable = false
        }
    }

    func setBrightness(_ newValue: Double) {
        let value = Float(max(0.05, min(1, newValue)))
        var changed = false
        forEachDisplayService { service in
            if IODisplaySetFloatParameter(
                service, 0, "brightness" as CFString, value
            ) == kIOReturnSuccess {
                changed = true
            }
        }
        if changed {
            brightness = Double(value)
            isAvailable = true
        } else {
            refresh()
        }
    }

    private func forEachDisplayService(_ operation: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            operation(service)
            IOObjectRelease(service)
        }
    }
}
