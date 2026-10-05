import AppKit
import Combine
import Foundation
@preconcurrency import IOBluetooth

struct BluetoothDeviceDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let isPaired: Bool
    let isConnected: Bool
}

@MainActor
final class BluetoothService: NSObject, ObservableObject {
    @Published private(set) var isPowered = false
    @Published private(set) var devices: [BluetoothDeviceDescriptor] = []
    @Published private(set) var connectedDeviceNames: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var busyDeviceID: String?
    @Published private(set) var pairingConfirmationCode: String?
    @Published private(set) var errorMessage: String?

    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairing: IOBluetoothDevicePair?
    private var devicesByID: [String: IOBluetoothDevice] = [:]

    override init() {
        super.init()
        let center = NotificationCenter.default
        for name in [
            NSNotification.Name.IOBluetoothHostControllerPoweredOn,
            NSNotification.Name.IOBluetoothHostControllerPoweredOff
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
            )
        }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        refreshTimer?.invalidate()
        inquiry?.stop()
        pairing?.stop()
    }

    var statusText: String {
        guard isPowered else { return "Off" }
        if connectedDeviceNames.isEmpty { return "On" }
        return connectedDeviceNames.joined(separator: ", ")
    }

    func refresh() {
        isPowered = IOBluetoothHostController.default()?.powerState
            == kBluetoothHCIPowerStateON
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        paired.forEach { devicesByID[$0.addressString] = $0 }
        rebuildDevices()
    }

    func scan() {
        guard isPowered, !isScanning else { return }
        errorMessage = nil
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
            errorMessage = "Bluetooth discovery is unavailable."
            return
        }
        inquiry.inquiryLength = 8
        inquiry.updateNewDeviceNames = true
        self.inquiry = inquiry
        let result = inquiry.start()
        if result != kIOReturnSuccess {
            errorMessage = "Unable to start Bluetooth scan (error \(result))."
            self.inquiry = nil
        }
    }

    func connect(_ descriptor: BluetoothDeviceDescriptor) {
        guard busyDeviceID == nil, let device = devicesByID[descriptor.id] else { return }
        if !descriptor.isPaired {
            pair(device, id: descriptor.id)
            return
        }
        busyDeviceID = descriptor.id
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = device.openConnection()
            DispatchQueue.main.async {
                self?.busyDeviceID = nil
                if result != kIOReturnSuccess {
                    self?.errorMessage = "Unable to connect to \(descriptor.name) (error \(result))."
                }
                self?.refresh()
            }
        }
    }

    func disconnect(_ descriptor: BluetoothDeviceDescriptor) {
        guard busyDeviceID == nil, let device = devicesByID[descriptor.id] else { return }
        busyDeviceID = descriptor.id
        let result = device.closeConnection()
        busyDeviceID = nil
        if result != kIOReturnSuccess {
            errorMessage = "Unable to disconnect \(descriptor.name) (error \(result))."
        }
        refresh()
    }

    func confirmPairing(_ confirmed: Bool) {
        pairing?.replyUserConfirmation(confirmed)
        pairingConfirmationCode = nil
        if !confirmed {
            pairing?.stop()
            pairing = nil
            busyDeviceID = nil
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func pair(_ device: IOBluetoothDevice, id: String) {
        guard let pairing = IOBluetoothDevicePair(device: device) else {
            errorMessage = "Bluetooth pairing is unavailable."
            return
        }
        pairing.delegate = self
        self.pairing = pairing
        busyDeviceID = id
        errorMessage = nil
        let result = pairing.start()
        if result != kIOReturnSuccess {
            errorMessage = "Unable to start pairing (error \(result))."
            busyDeviceID = nil
            self.pairing = nil
        }
    }

    private func rebuildDevices() {
        devices = devicesByID.values.map { device in
            BluetoothDeviceDescriptor(
                id: device.addressString,
                name: device.nameOrAddress,
                isPaired: device.isPaired(),
                isConnected: device.isConnected()
            )
        }.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.isPaired != $1.isPaired { return $0.isPaired }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        connectedDeviceNames = devices.filter(\.isConnected).map(\.name)
    }
}

extension BluetoothService: @preconcurrency IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry) {
        Task { @MainActor in self.isScanning = true }
    }

    func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry,
        device: IOBluetoothDevice
    ) {
        Task { @MainActor in
            self.devicesByID[device.addressString] = device
            self.rebuildDevices()
        }
    }

    func deviceInquiryDeviceNameUpdated(
        _ sender: IOBluetoothDeviceInquiry,
        device: IOBluetoothDevice,
        devicesRemaining: UInt32
    ) {
        Task { @MainActor in
            self.devicesByID[device.addressString] = device
            self.rebuildDevices()
        }
    }

    func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry,
        error: IOReturn,
        aborted: Bool
    ) {
        Task { @MainActor in
            self.isScanning = false
            self.inquiry = nil
            if error != kIOReturnSuccess && !aborted {
                self.errorMessage = "Bluetooth scan failed (error \(error))."
            }
            self.refresh()
        }
    }
}

extension BluetoothService: @preconcurrency IOBluetoothDevicePairDelegate {
    func devicePairingUserConfirmationRequest(
        _ sender: Any,
        numericValue: BluetoothNumericValue
    ) {
        Task { @MainActor in
            self.pairingConfirmationCode = String(format: "%06u", numericValue)
        }
    }

    func devicePairingFinished(_ sender: Any, error: IOReturn) {
        Task { @MainActor in
            self.busyDeviceID = nil
            self.pairingConfirmationCode = nil
            self.pairing = nil
            if error != kIOReturnSuccess {
                self.errorMessage = "Bluetooth pairing failed (error \(error))."
            }
            self.refresh()
        }
    }
}
