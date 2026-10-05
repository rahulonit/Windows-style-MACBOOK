import Foundation

final class DockVisibilityController {
    private struct Snapshot: Codable {
        let autoHide: Bool?
        let autoHideDelay: Double?
        let autoHideTimeModifier: Double?
    }

    private let backupKey = "WindowsTaskbar.DockPreferenceSnapshot"

    func hideDock() {
        if UserDefaults.standard.data(forKey: backupKey) == nil {
            let snapshot = Snapshot(
                autoHide: readBool("autohide"),
                autoHideDelay: readDouble("autohide-delay"),
                autoHideTimeModifier: readDouble("autohide-time-modifier")
            )
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: backupKey)
            }
        }

        write("autohide", type: "-bool", value: "true")
        write("autohide-delay", type: "-float", value: "1000")
        write("autohide-time-modifier", type: "-float", value: "0")
        restartDock()
    }

    func restoreDock() {
        guard
            let data = UserDefaults.standard.data(forKey: backupKey),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return
        }

        restore("autohide", bool: snapshot.autoHide)
        restore("autohide-delay", double: snapshot.autoHideDelay)
        restore("autohide-time-modifier", double: snapshot.autoHideTimeModifier)
        UserDefaults.standard.removeObject(forKey: backupKey)
        restartDock()
    }

    private func readBool(_ key: String) -> Bool? {
        guard let value = read(key)?.lowercased() else { return nil }
        if value == "1" || value == "true" { return true }
        if value == "0" || value == "false" { return false }
        return nil
    }

    private func readDouble(_ key: String) -> Double? {
        guard let value = read(key) else { return nil }
        return Double(value)
    }

    private func read(_ key: String) -> String? {
        let result = run("/usr/bin/defaults", ["read", "com.apple.dock", key])
        guard result.status == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ key: String, type: String, value: String) {
        _ = run("/usr/bin/defaults", ["write", "com.apple.dock", key, type, value])
    }

    private func restore(_ key: String, bool value: Bool?) {
        if let value {
            write(key, type: "-bool", value: value ? "true" : "false")
        } else {
            delete(key)
        }
    }

    private func restore(_ key: String, double value: Double?) {
        if let value {
            write(key, type: "-float", value: String(value))
        } else {
            delete(key)
        }
    }

    private func delete(_ key: String) {
        _ = run("/usr/bin/defaults", ["delete", "com.apple.dock", key])
    }

    private func restartDock() {
        _ = run("/usr/bin/killall", ["Dock"])
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, "")
        }
    }
}
