import AppKit
import Combine

@main
final class WindowsTaskbarApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: WindowsTaskbarApp?
    private var taskbarCoordinator: TaskbarCoordinator?
    private let dockVisibilityController = DockVisibilityController()
    private var dockPreferenceCancellable: AnyCancellable?
    private var terminationSignalSources: [DispatchSourceSignal] = []

    static func main() {
        let application = NSApplication.shared
        let delegate = WindowsTaskbarApp()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignalHandlers()
        let preferencesService = PreferencesService()
        let state = TaskbarState(preferencesService: preferencesService)
        if preferencesService.hideMacDock {
            dockVisibilityController.hideDock()
        }
        dockPreferenceCancellable = preferencesService.$hideMacDock
            .dropFirst()
            .sink { [weak self] shouldHide in
                if shouldHide {
                    self?.dockVisibilityController.hideDock()
                } else {
                    self?.dockVisibilityController.restoreDock()
                }
            }
        taskbarCoordinator = TaskbarCoordinator(state: state)
        taskbarCoordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskbarCoordinator?.stop()
        dockVisibilityController.restoreDock()
        dockPreferenceCancellable = nil
    }

    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                NSApplication.shared.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }
}
