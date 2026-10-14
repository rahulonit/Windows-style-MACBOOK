import Combine
import CoreFoundation
import Foundation

@MainActor
final class DockGeometryService: ObservableObject {
    @Published private(set) var tileSize: CGFloat

    private var refreshTimer: Timer?
    private var dockObserver: NSObjectProtocol?

    init() {
        tileSize = Self.readTileSize()
        dockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        if let dockObserver {
            DistributedNotificationCenter.default().removeObserver(dockObserver)
        }
    }

    func taskbarHeight(for iconSize: CGFloat) -> CGFloat {
        DockGeometryPolicy.taskbarHeight(
            iconSize: iconSize,
            dockTileSize: tileSize
        )
    }

    private func refresh() {
        let updated = Self.readTileSize()
        guard abs(updated - tileSize) > 0.1 else { return }
        tileSize = updated
    }

    private static func readTileSize() -> CGFloat {
        let value = CFPreferencesCopyAppValue(
            "tilesize" as CFString,
            "com.apple.dock" as CFString
        ) as? NSNumber
        let size = CGFloat(value?.doubleValue ?? 36)
        return min(max(size, 24), 80)
    }
}

enum DockGeometryPolicy {
    static func taskbarHeight(iconSize: CGFloat, dockTileSize: CGFloat) -> CGFloat {
        // The Dock adds roughly ten points of vertical inset above and below
        // its tile size. Preserve the taskbar's proportional scaling when it
        // needs more room, but never make it shorter than the user's Dock.
        max(
            TaskbarTheme.height(for: iconSize),
            min(max(dockTileSize + 20, 44), 100)
        )
    }
}
