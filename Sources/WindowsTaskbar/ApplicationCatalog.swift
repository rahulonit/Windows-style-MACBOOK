import AppKit

enum ApplicationCatalog {
    private static let defaultBundleIdentifiers = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.MobileSMS",
        "com.apple.systempreferences"
    ]

    static func defaultPinnedApps() -> [AppDescriptor] {
        defaultBundleIdentifiers.compactMap(descriptor(for:))
    }

    static func installedApplications() -> [AppDescriptor] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
        var applicationsByIdentifier: [String: AppDescriptor] = [:]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard
                    let bundle = Bundle(url: url),
                    let identifier = bundle.bundleIdentifier
                else { continue }

                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                guard isUserFacingApplication(
                    displayName: displayName,
                    infoDictionary: bundle.infoDictionary ?? [:]
                ) else { continue }
                applicationsByIdentifier[identifier] = AppDescriptor(
                    bundleIdentifier: identifier,
                    displayName: displayName,
                    applicationURL: url
                )
            }
        }

        return applicationsByIdentifier.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func isUserFacingApplication(
        displayName: String,
        infoDictionary: [String: Any]
    ) -> Bool {
        if (infoDictionary["LSUIElement"] as? Bool) == true
            || (infoDictionary["LSBackgroundOnly"] as? Bool) == true {
            return false
        }

        let normalizedName = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let internalToolMarkers = [
            " helper",
            "helper ",
            "diagnostic",
            "crash reporter",
            "content synchronizer",
            "content manager",
            "uninstaller",
            " uninstall",
            "installer",
            "update service",
            " updater"
        ]
        return !internalToolMarkers.contains { normalizedName.contains($0) }
    }

    static func descriptor(for bundleIdentifier: String) -> AppDescriptor? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }

        let bundle = Bundle(url: applicationURL)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? applicationURL.deletingPathExtension().lastPathComponent

        return AppDescriptor(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationURL: applicationURL
        )
    }

    static func descriptor(for application: NSRunningApplication) -> AppDescriptor? {
        guard
            let bundleIdentifier = application.bundleIdentifier,
            let applicationURL = application.bundleURL
        else {
            return nil
        }

        return AppDescriptor(
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName
                ?? applicationURL.deletingPathExtension().lastPathComponent,
            applicationURL: applicationURL
        )
    }
}
