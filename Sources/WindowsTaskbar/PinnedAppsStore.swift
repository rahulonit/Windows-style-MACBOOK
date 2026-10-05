import Foundation

final class PinnedAppsStore {
    private let defaults: UserDefaults
    private let key = "WindowsTaskbar.PinnedBundleIdentifiers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String]? {
        defaults.stringArray(forKey: key)
    }

    func save(_ bundleIdentifiers: [String]) {
        defaults.set(bundleIdentifiers, forKey: key)
    }
}
