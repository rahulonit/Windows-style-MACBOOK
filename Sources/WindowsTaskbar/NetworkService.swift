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
    @Published private(set) var networkName: String?
    @Published private(set) var availableNetworks: [AvailableNetwork] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectingNetworkName: String?
    @Published private(set) var pendingNetwork: AvailableNetwork?
    @Published var password = ""
    @Published private(set) var errorMessage: String?

    private let client = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let authorizationDelegate = LocationAuthorizationDelegate()
    private let eventDelegate = WiFiEventDelegate()
    private var scannedNetworksByName: [String: CWNetwork] = [:]

    override init() {
        super.init()
        authorizationDelegate.onChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationChanged(to: status)
            }
        }
        locationManager.delegate = authorizationDelegate
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
    }

    func refresh() {
        guard let interface = client.interface() else {
            isPowered = false
            networkName = nil
            errorMessage = "No Wi-Fi interface is available."
            return
        }

        isPowered = interface.powerOn()
        networkName = interface.ssid()
    }

    func requestPermissionAndScan() {
        updatePermissionState(locationManager.authorizationStatus)
        switch permissionState {
        case .notDetermined:
            permissionState = .requesting
            locationManager.requestWhenInUseAuthorization()
        case .requesting:
            break
        case .authorized:
            scanAuthorizedNetworks()
        case .denied, .restricted:
            errorMessage = "Location access is required to display nearby Wi-Fi network names."
        }
    }

    func setPowered(_ powered: Bool) {
        guard let interface = client.interface() else {
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
            return
        }
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
        client.interface()?.disassociate()
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
        updatePermissionState(status)
        if permissionState == .authorized {
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

    private func scanAuthorizedNetworks() {
        guard permissionState == .authorized else { return }
        guard isPowered, let interface = client.interface() else {
            availableNetworks = []
            return
        }

        isScanning = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let scanned = try interface.scanForNetworks(withSSID: nil)
                var strongestByName: [String: CWNetwork] = [:]
                for network in scanned {
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
                    self?.scannedNetworksByName = strongestByName
                    self?.availableNetworks = models
                    self?.isScanning = false
                    self?.errorMessage = models.isEmpty ? "No nearby networks were found." : nil
                    self?.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.availableNetworks = []
                    self?.scannedNetworksByName = [:]
                    self?.isScanning = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func connect(to network: AvailableNetwork, password: String?) {
        guard
            connectingNetworkName == nil,
            let interface = client.interface(),
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
}
