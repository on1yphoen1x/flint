import AppKit
import AudioToolbox
import CoreAudio

struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

struct AudioApp: Identifiable, Equatable {
    let id: String
    let processes: [AudioObjectID]
    let name: String
    let icon: NSImage?
    let isPlaying: Bool
}

/// Per-app volume and output device, built on Core Audio process taps.
///
/// An app with its own settings gets a private tap that silences it on the
/// normal output and a private aggregate device that plays the tapped audio
/// out of the chosen speakers at the chosen volume. Apps left at full volume
/// on the default output are never touched.
@MainActor
final class AudioRouter: ObservableObject {
    struct Setting: Codable, Equatable {
        var volume: Float = 1
        var deviceUID: String?

        var isDefault: Bool { volume >= 0.999 && deviceUID == nil }
    }

    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var outputs: [OutputDevice] = []
    @Published private(set) var settings: [String: Setting] = [:]
    @Published private(set) var failure: String?

    private var routes: [String: ProcessRoute] = [:]
    private static let defaultsKey = "audioRoutes"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Setting].self, from: data) {
            settings = saved
        }
        refresh()
    }

    func setting(for app: AudioApp) -> Setting {
        settings[app.id] ?? Setting()
    }

    func setVolume(_ volume: Float, for app: AudioApp) {
        var setting = setting(for: app)
        setting.volume = volume
        update(setting, for: app)
    }

    func setOutput(_ uid: String?, for app: AudioApp) {
        var setting = setting(for: app)
        setting.deviceUID = uid
        update(setting, for: app)
    }

    func reset(_ app: AudioApp) {
        update(Setting(), for: app)
    }

    func refresh() {
        outputs = Self.outputDevices()
        apps = Self.audioApps(keeping: Set(settings.keys))
        for app in apps {
            apply(setting(for: app), to: app)
        }
    }

    private func update(_ setting: Setting, for app: AudioApp) {
        settings[app.id] = setting.isDefault ? nil : setting
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        apply(setting, to: app)
    }

    private func apply(_ setting: Setting, to app: AudioApp) {
        if setting.isDefault || app.processes.isEmpty {
            routes.removeValue(forKey: app.id)?.stop()
            return
        }
        let deviceUID = setting.deviceUID.flatMap { uid in outputs.contains { $0.uid == uid } ? uid : nil } ?? Self.defaultOutputUID()
        guard let deviceUID else { return }

        if let route = routes[app.id], route.deviceUID == deviceUID, route.processes == app.processes {
            route.gain.value = setting.volume
            return
        }
        routes.removeValue(forKey: app.id)?.stop()
        do {
            let route = try ProcessRoute(processes: app.processes, deviceUID: deviceUID, name: app.name)
            route.gain.value = setting.volume
            routes[app.id] = route
            failure = nil
        } catch {
            failure = "Couldn't take over \(app.name)'s sound. Check that Flint is allowed under Privacy & Security > Screen & System Audio Recording."
        }
    }

    // MARK: - Reading Core Audio

    private static func audioApps(keeping saved: Set<String>) -> [AudioApp] {
        let objects: [AudioObjectID] = array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        var grouped: [String: (processes: [AudioObjectID], playing: Bool, pid: pid_t)] = [:]
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for object in objects {
            let pid: pid_t = value(object, kAudioProcessPropertyPID) ?? 0
            guard pid != ownPID, let bundleID = string(object, kAudioProcessPropertyBundleID), !bundleID.isEmpty else { continue }
            let running: UInt32 = value(object, kAudioProcessPropertyIsRunningOutput) ?? 0
            // Helper processes (such as a browser's audio service) are grouped under their app.
            let appID = owningAppID(for: bundleID)
            var entry = grouped[appID] ?? ([], false, pid)
            entry.processes.append(object)
            entry.playing = entry.playing || running != 0
            grouped[appID] = entry
        }

        return grouped.compactMap { appID, entry in
            guard entry.playing || saved.contains(appID) else { return nil }
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first
                ?? NSRunningApplication(processIdentifier: entry.pid)
            let name = app?.localizedName ?? appID.components(separatedBy: ".").last ?? appID
            return AudioApp(id: appID, processes: entry.processes.sorted(), name: name, icon: app?.icon, isPlaying: entry.playing)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// "com.google.Chrome.helper" belongs to "com.google.Chrome", and so on.
    private static func owningAppID(for bundleID: String) -> String {
        var parts = bundleID.components(separatedBy: ".")
        while parts.count > 2 {
            let candidate = parts.joined(separator: ".")
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil,
               !NSRunningApplication.runningApplications(withBundleIdentifier: candidate).isEmpty {
                return candidate
            }
            parts.removeLast()
        }
        return bundleID
    }

    private static func outputDevices() -> [OutputDevice] {
        let devices: [AudioObjectID] = array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return devices.compactMap { device in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
            )
            var size = UInt32(0)
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0,
                  let uid = string(device, kAudioDevicePropertyDeviceUID),
                  let name = string(device, kAudioObjectPropertyName),
                  !uid.hasPrefix(ProcessRoute.uidPrefix) else { return nil }
            return OutputDevice(id: device, uid: uid, name: name)
        }
    }

    private static func defaultOutputUID() -> String? {
        let device: AudioObjectID = value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        return device == 0 ? nil : string(device, kAudioDevicePropertyDeviceUID)
    }

    private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = propertyAddress(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func array(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = propertyAddress(selector)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var items = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &items) == noErr else { return [] }
        return items
    }

    fileprivate static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector)
        var text: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &text) == noErr else { return nil }
        return text?.takeRetainedValue() as String?
    }
}

/// Shared with the audio thread, which only ever reads it. A torn read of one
/// float can't happen on Apple silicon or Intel, so it isn't locked.
final class Gain: @unchecked Sendable {
    var value: Float = 1
}

/// One app's tap, the aggregate device that plays it, and the callback that applies the volume.
@MainActor
final class ProcessRoute {
    nonisolated static let uidPrefix = "app.phoenixclips.FlintNotch.route."

    let processes: [AudioObjectID]
    let deviceUID: String
    let gain = Gain()

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    struct Failure: Error {}

    init(processes: [AudioObjectID], deviceUID: String, name: String) throws {
        self.processes = processes
        self.deviceUID = deviceUID

        let description = CATapDescription(stereoMixdownOfProcesses: processes.map { NSNumber(value: $0) })
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "Flint \(name)"
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { throw Failure() }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Flint \(name)",
            kAudioAggregateDeviceUIDKey: Self.uidPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate) == noErr else {
            stop()
            throw Failure()
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil, Self.renderBlock(gain: gain))
        guard status == noErr, let procID, AudioDeviceStart(aggregate, procID) == noErr else {
            stop()
            throw Failure()
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregate, procID)
            AudioDeviceDestroyIOProcID(aggregate, procID)
            self.procID = nil
        }
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = AudioObjectID(kAudioObjectUnknown)
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Built outside the main actor so the audio thread can call it directly.
    private nonisolated static func renderBlock(gain: Gain) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            copy(input, to: output, gain: gain.value)
        }
    }

    /// Runs on Core Audio's real-time thread: no allocation, no locks.
    private nonisolated static func copy(
        _ input: UnsafePointer<AudioBufferList>,
        to output: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        // A headset's microphone streams come first, so the tap's buffers are the last ones.
        let offset = max(inputs.count - outputs.count, 0)
        for index in 0..<outputs.count {
            guard let target = outputs[index].mData else { continue }
            let targetBytes = Int(outputs[index].mDataByteSize)
            guard index + offset < inputs.count, let source = inputs[index + offset].mData else {
                memset(target, 0, targetBytes)
                continue
            }
            let bytes = min(targetBytes, Int(inputs[index + offset].mDataByteSize))
            let samples = bytes / MemoryLayout<Float>.size
            let from = source.assumingMemoryBound(to: Float.self)
            let to = target.assumingMemoryBound(to: Float.self)
            for sample in 0..<samples {
                to[sample] = from[sample] * gain
            }
            if bytes < targetBytes {
                memset(target + bytes, 0, targetBytes - bytes)
            }
        }
    }
}
