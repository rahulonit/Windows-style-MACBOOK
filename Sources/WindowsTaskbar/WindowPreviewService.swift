import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class WindowPreviewService: ObservableObject {
    @Published private(set) var images: [Int: NSImage] = [:]
    @Published private(set) var permissionRequired = false
    @Published private(set) var isRefreshing = false

    private var refreshGeneration = 0
    private var hasRequestedPermission = false

    func image(for window: AccessibilityWindow) -> NSImage? {
        images[window.id]
    }

    func refresh(windows: [AccessibilityWindow]) {
        refreshGeneration += 1
        let generation = refreshGeneration
        images = images.filter { image in windows.contains { $0.id == image.key } }
        guard !windows.isEmpty else {
            isRefreshing = false
            return
        }
        guard #available(macOS 14.0, *) else {
            permissionRequired = true
            return
        }

        var authorized = CGPreflightScreenCaptureAccess()
        if !authorized, !hasRequestedPermission {
            hasRequestedPermission = true
            authorized = CGRequestScreenCaptureAccess()
        }
        guard authorized else {
            permissionRequired = true
            isRefreshing = false
            return
        }

        permissionRequired = false
        isRefreshing = true
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                var captured: [Int: NSImage] = [:]
                for window in windows {
                    guard let shareableWindow = Self.match(window, in: content.windows),
                          let image = try await Self.capture(shareableWindow)
                    else { continue }
                    captured[window.id] = image
                }
                guard let self, generation == self.refreshGeneration else { return }
                self.images = captured
                self.isRefreshing = false
            } catch {
                guard let self, generation == self.refreshGeneration else { return }
                self.permissionRequired = true
                self.isRefreshing = false
                NSLog("Unable to capture window previews: \(error.localizedDescription)")
            }
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @available(macOS 14.0, *)
    private static func match(
        _ window: AccessibilityWindow,
        in candidates: [SCWindow]
    ) -> SCWindow? {
        let sameProcess = candidates.filter {
            $0.owningApplication?.processID == window.processIdentifier
        }
        if let exactTitle = sameProcess.first(where: {
            guard let title = $0.title else { return false }
            return !title.isEmpty && title == window.title
        }) {
            return exactTitle
        }
        return sameProcess.first
    }

    @available(macOS 14.0, *)
    private static func capture(_ window: SCWindow) async throws -> NSImage? {
        let configuration = SCStreamConfiguration()
        let aspectRatio = max(0.35, window.frame.width / max(window.frame.height, 1))
        configuration.width = 420
        configuration.height = Int(420 / aspectRatio)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
