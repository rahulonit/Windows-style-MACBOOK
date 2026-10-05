import AppKit
import Combine
import CoreLocation
@preconcurrency import CoreWLAN
import Foundation

enum WiFiPermissionState: Equatable {
    case notDetermined
    case requesting
    case authorized
    case denied
    case restricted
}

enum WiFiScanState: Equatable {
    case idle
    case scanning
    case results
    case empty
    case failed(String)
}

private final class LocationAuthorizationDelegate: NSObject, CLLocationManagerDelegate {
    var onChange: ((CLAuthorizationStatus) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange?(manager.authorizationStatus)
    }
}

private final class WiFiEventDelegate: NSObject, CWEventDelegate {
    var onChange: (() -> Void)?

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { onChange?() }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { onChange?() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { onChange?() }
    func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) { onChange?() }
}

@MainActor
final class NetworkService: NSObject, ObservableObject {
    struct AvailableNetwork: Identifiable, Hashable {
        let name: String
        let signalStrength: Int
        let isSecure: Bool

        var id: String { name }

        var signalSymbol: String {
            signalStrength >= -72 ? "wifi" : "wifi.exclamationmark"
        }
    }

    @Published private(set) var permissionState: WiFiPermissionState = .notDetermined
    @Published private(set) var isPowered = false
    @Published private(set) var isConnected = false
    @Published private(set) var networkName: String?
    @Published private(set) var availableNetworks: [AvailableNetwork] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanState: WiFiScanState = .idle
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var connectingNetworkName: String?
    @Published private(set) var pendingNetwork: AvailableNetwork?
    @Published var password = ""
    @Published private(set) var errorMessage: String?

    private let client = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let authorizationDelegate = LocationAuthorizationDelegate()
    private let eventDelegate = WiFiEventDelegate()
    private var scannedNetworksByName: [String: CWNetwork] = [:]
    private var scanGeneration = 0
    private var permissionRequestWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        authorizationDelegate.onChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationChanged(to: status)
            }
        }
        locationManager.delegate = authorizationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        eventDelegate.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        client.delegate = eventDelegate
        startMonitoringEvents()
        updatePermissionState(locationManager.authorizationStatus)
        refresh()
    }

    deinit {
        try? client.stopMonitoringAllEvents()
        locationManager.stopUpdatingLocation()
        permissionRequestWorkItem?.cancel()
    }

    var statusText: String {
        guard isPowered else { return "Off" }
        if let networkName { return networkName }
        return isConnected ? "Connected" : "Not connected"
    }

    func refresh() {
        guard let interface = preferredInterface() else {
            isPowered = false
            isConnected = false
            networkName = nil
            errorMessage = "No Wi-Fi interface is available."
            return
        }

        isPowered = interface.powerOn()
        isConnected = isPowered && interface.serviceActive()
        networkName = isConnected ? interface.ssid() : nil
        if isPowered, errorMessage == "No Wi-Fi interface is available." {
            errorMessage = nil
        }
    }

    func requestPermissionAndScan() {
        updatePermissionState(locationManager.authorizationStatus)
        switch permissionState {
        case .notDetermined:
            permissionState = .requesting
            // A menu-bar-style app can own a non-activating panel. Core
            // Location only presents its when-in-use prompt while the app is
            // active, so briefly activate before requesting permission.
            NSApplication.shared.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.locationManager.requestWhenInUseAuthorization()
                self.schedulePermissionRequestTimeout()
            }
        case .requesting:
            break
        case .authorized:
            beginLocationSession()
            scanAuthorizedNetworks()
        case .denied, .restricted:
            errorMessage = "Location access is required to display nearby Wi-Fi network names."
        }
    }

    func setPowered(_ powered: Bool) {
        guard let interface = preferredInterface() else {
            errorMessage = "No Wi-Fi interface is available."
            return
        }

        do {
            try interface.setPower(powered)
            refresh()
            if powered {
                requestPermissionAndScan()
            } else {
                availableNetworks = []
                scannedNetworksByName = [:]
                scanState = .idle
            }
        } catch {
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    func scan() {
        refresh()
        guard isPowered else {
            availableNetworks = []
            scanState = .idle
            return
        }
        guard !isScanning else { return }
        requestPermissionAndScan()
    }

    func select(_ network: AvailableNetwork) {
        errorMessage = nil
        guard network.name != networkName else { return }
        if network.isSecure {
            pendingNetwork = network
            password = ""
        } else {
            connect(to: network, password: nil)
        }
    }

    func connectToPendingNetwork() {
        guard let pendingNetwork else { return }
        let suppliedPassword = password
        password = ""
        connect(to: pendingNetwork, password: suppliedPassword)
    }

    func cancelPasswordEntry() {
        password = ""
        pendingNetwork = nil
        errorMessage = nil
    }

    func disconnect() {
        preferredInterface()?.disassociate()
        pendingNetwork = nil
        password = ""
        refresh()
        scanAuthorizedNetworks()
    }

    func openLocationPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func authorizationChanged(to status: CLAuthorizationStatus) {
        permissionRequestWorkItem?.cancel()
        permissionRequestWorkItem = nil
        updatePermissionState(status)
        if permissionState == .authorized {
            beginLocationSession()
            scanAuthorizedNetworks()
        }
    }

    private func startMonitoringEvents() {
        for event in [
            CWEventType.powerDidChange,
            .ssidDidChange,
            .linkDidChange,
            .scanCacheUpdated
        ] {
            do {
                try client.startMonitoringEvent(with: event)
            } catch {
                NSLog("Unable to monitor Wi-Fi event: \(error.localizedDescription)")
            }
        }
    }

    private func updatePermissionState(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            permissionState = .notDetermined
        case .restricted:
            permissionState = .restricted
        case .denied:
            permissionState = .denied
        case .authorized, .authorizedAlways:
            permissionState = .authorized
        @unknown default:
            permissionState = .restricted
        }
    }

    private func scanAuthorizedNetworks(retryIfEmpty: Bool = true) {
        guard permissionState == .authorized else { return }
        guard isPowered, let interface = preferredInterface() else {
            availableNetworks = []
            scanState = .idle
            return
        }

        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        scanState = .scanning
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let scanned = try interface.scanForNetworks(withSSID: nil)
                let candidates = scanned.isEmpty
                    ? (interface.cachedScanResults() ?? [])
                    : scanned
                var strongestByName: [String: CWNetwork] = [:]
                for network in candidates {
                    guard let name = network.ssid, !name.isEmpty else { continue }
                    if network.rssiValue > (strongestByName[name]?.rssiValue ?? Int.min) {
                        strongestByName[name] = network
                    }
                }
                let models = strongestByName.map { name, network in
                    AvailableNetwork(
                        name: name,
                        signalStrength: network.rssiValue,
                        isSecure: !network.supportsSecurity(.none)
                    )
                }
                .sorted { $0.signalStrength > $1.signalStrength }

                DispatchQueue.main.async {
                    guard let self, generation == self.scanGeneration else { return }
                    if models.isEmpty, retryIfEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                            guard let self, generation == self.scanGeneration else { return }
                            self.scanAuthorizedNetworks(retryIfEmpty: false)
                        }
                        return
                    }
                    self.scannedNetworksByName = strongestByName
                    self.availableNetworks = models
                    self.isScanning = false
                    self.lastScanDate = Date()
                    self.scanState = models.isEmpty ? .empty : .results
                    self.locationManager.stopUpdatingLocation()
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, generation == self.scanGeneration else { return }
                    self.availableNetworks = []
                    self.scannedNetworksByName = [:]
                    self.isScanning = false
                    self.lastScanDate = Date()
                    self.scanState = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.locationManager.stopUpdatingLocation()
                }
            }
        }
    }

    private func connect(to network: AvailableNetwork, password: String?) {
        guard
            connectingNetworkName == nil,
            let interface = preferredInterface(),
            let scannedNetwork = scannedNetworksByName[network.name]
        else { return }

        connectingNetworkName = network.name
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try interface.associate(to: scannedNetwork, password: password)
                DispatchQueue.main.async {
                    self?.connectingNetworkName = nil
                    self?.pendingNetwork = nil
                    self?.password = ""
                    self?.refresh()
                    self?.scanAuthorizedNetworks()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.connectingNetworkName = nil
                    self?.password = ""
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func beginLocationSession() {
        guard permissionState == .authorized else { return }
        locationManager.startUpdatingLocation()
    }

    private func schedulePermissionRequestTimeout() {
        permissionRequestWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.updatePermissionState(self.locationManager.authorizationStatus)
            if self.permissionState == .requesting {
                self.permissionState = .notDetermined
            }
        }
        permissionRequestWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func preferredInterface() -> CWInterface? {
        let interfaces = client.interfaces() ?? []
        return interfaces.first(where: { $0.serviceActive() })
            ?? interfaces.first(where: { $0.powerOn() })
            ?? client.interface()
    }
}
