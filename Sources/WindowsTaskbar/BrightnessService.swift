import Combine
import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics

@MainActor
final class BrightnessService: ObservableObject {
    @Published private(set) var brightness: Double = 0.5
    @Published private(set) var isAvailable = false

    private var refreshTimer: Timer?
    private let displayServices = DisplayServicesBrightnessBackend()

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    func refresh() {
        if let value = displayServices.currentBrightness() {
            brightness = Double(value)
            isAvailable = true
            return
        }

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
        let value = Float(max(0, min(1, newValue)))
        var changed = displayServices.setBrightness(value)
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

/// The public IOKit display API works for many external monitors but not for
/// the built-in panel on Apple-silicon Macs. DisplayServices is the backend
/// used by macOS itself, so use it when present and retain IOKit as a fallback.
private final class DisplayServicesBrightnessBackend {
    private typealias GetBrightness = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let handle,
           let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
           let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") {
            getBrightness = unsafeBitCast(getSymbol, to: GetBrightness.self)
            setBrightness = unsafeBitCast(setSymbol, to: SetBrightness.self)
        } else {
            getBrightness = nil
            setBrightness = nil
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func currentBrightness() -> Float? {
        guard let getBrightness else { return nil }
        for displayID in onlineDisplayIDs() {
            var value: Float = 0
            if getBrightness(displayID, &value) == 0 {
                return min(max(value, 0), 1)
            }
        }
        return nil
    }

    func setBrightness(_ value: Float) -> Bool {
        guard let setBrightness else { return false }
        var changed = false
        for displayID in onlineDisplayIDs() {
            if setBrightness(displayID, value) == 0 {
                changed = true
            }
        }
        return changed
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return []
        }
        return Array(displays.prefix(Int(count))).sorted {
            CGDisplayIsBuiltin($0) > CGDisplayIsBuiltin($1)
        }
    }
}
