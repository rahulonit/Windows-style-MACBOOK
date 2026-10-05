import AudioToolbox
import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
final class AudioService: ObservableObject {
    @Published private(set) var volume: Double = 0
    @Published private(set) var isMuted = false
    @Published private(set) var isAvailable = false
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var selectedOutputDeviceID: AudioDeviceID?

    private var refreshTimer: Timer?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    var selectedOutputName: String? {
        outputDevices.first { $0.id == selectedOutputDeviceID }?.name
    }

    func refresh() {
        outputDevices = availableOutputDevices()
        guard let device = defaultOutputDevice() else {
            selectedOutputDeviceID = nil
            isAvailable = false
            return
        }
        selectedOutputDeviceID = device

        var scalar = Float32.zero
        var scalarSize = UInt32(MemoryLayout<Float32>.size)
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let volumeStatus = AudioObjectGetPropertyData(
            device, &volumeAddress, 0, nil, &scalarSize, &scalar
        )

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let muteStatus = AudioObjectGetPropertyData(
            device, &muteAddress, 0, nil, &muteSize, &muted
        )

        isAvailable = volumeStatus == noErr
        if volumeStatus == noErr { volume = Double(scalar) }
        if muteStatus == noErr { isMuted = muted != 0 }
    }

    func selectOutputDevice(_ device: AudioOutputDevice) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id
        ) == noErr {
            selectedOutputDeviceID = id
            refresh()
        }
    }

    func setVolume(_ newValue: Double) {
        guard let device = defaultOutputDevice() else { return }
        var scalar = Float32(max(0, min(1, newValue)))
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectSetPropertyData(device, &address, 0, nil, size, &scalar) == noErr {
            volume = Double(scalar)
            if scalar > 0, isMuted { setMuted(false) }
        }
    }

    func toggleMute() { setMuted(!isMuted) }

    private func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
            isMuted = muted
        }
    }

    private func availableOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = deviceName(id) else { return nil }
            return AudioOutputDevice(id: id, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(_ device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name?.takeUnretainedValue() as String?
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
