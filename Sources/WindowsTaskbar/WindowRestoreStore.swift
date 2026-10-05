import CoreGraphics

struct WindowIdentity: Hashable {
    let processIdentifier: pid_t
    let elementIdentifier: Int
}

struct WindowRestoreState {
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    var zone: SnapZone
}

@MainActor
final class WindowRestoreStore {
    private var states: [WindowIdentity: WindowRestoreState] = [:]

    func record(
        _ window: AccessibilityWindow,
        frame: CGRect,
        displayID: CGDirectDisplayID?,
        zone: SnapZone
    ) {
        let identity = window.identity
        if var existing = states[identity] {
            existing.zone = zone
            states[identity] = existing
        } else {
            states[identity] = WindowRestoreState(
                frame: frame,
                displayID: displayID,
                zone: zone
            )
        }
    }

    func state(for window: AccessibilityWindow) -> WindowRestoreState? {
        states[window.identity]
    }

    @discardableResult
    func remove(for window: AccessibilityWindow) -> WindowRestoreState? {
        states.removeValue(forKey: window.identity)
    }

    func remove(processIdentifier: pid_t) {
        states = states.filter { $0.key.processIdentifier != processIdentifier }
    }

    func removeAll() {
        states.removeAll()
    }
}
