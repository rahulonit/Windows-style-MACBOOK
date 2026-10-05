import AppKit

struct AppDescriptor: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL

    var id: String { bundleIdentifier }

    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}
