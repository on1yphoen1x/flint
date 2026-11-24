import SwiftUI

struct ConnectedDevice: Identifiable, Equatable {
    enum Kind: Equatable {
        case mac, headphones, mouse, keyboard, trackpad, other
    }

    let id: String
    let name: String
    let kind: Kind
    let percent: Int
    var detail: String?
    var isCharging = false

    var symbol: String {
        switch kind {
        case .mac: "laptopcomputer"
        case .headphones: name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones"
        case .mouse: "magicmouse.fill"
        case .keyboard: "keyboard.fill"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

/// Battery levels for the Mac and anything connected over Bluetooth.
///
/// macOS keeps Bluetooth battery levels in System Information, which takes a
/// moment to answer, so this only asks while the Devices tab is on screen.
@MainActor
final class Devices: ObservableObject {
    @Published private(set) var list: [ConnectedDevice] = []
    @Published private(set) var isLoading = false

    private var lastRefresh = Date.distantPast

    func refresh(force: Bool = false) {
        guard !isLoading, force || Date().timeIntervalSince(lastRefresh) > 30 else { return }
        isLoading = true
        Task {
            let bluetooth = await Self.bluetoothDevices()
            var devices: [ConnectedDevice] = []
            if let battery = Battery.readNow() {
                devices.append(ConnectedDevice(id: "mac", name: "This Mac", kind: .mac, percent: battery.percent, isCharging: battery.isCharging))
            }
            list = devices + bluetooth
            lastRefresh = Date()
            isLoading = false
        }
    }

    private nonisolated static func bluetoothDevices() async -> [ConnectedDevice] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

            var devices: [ConnectedDevice] = []
            for controller in controllers {
                for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                    for (name, value) in entry {
                        guard let details = value as? [String: Any] else { continue }
                        func level(_ key: String) -> Int? {
                            (details[key] as? String)
                                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "% ")) }
                                .flatMap(Int.init)
                        }
                        let buds = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
                        guard let percent = level("device_batteryLevelMain") ?? buds.min() else { continue }
                        let caseLevel = level("device_batteryLevelCase")

                        let type = (details["device_minorType"] as? String ?? "").lowercased()
                        let kind: ConnectedDevice.Kind = switch true {
                        case type.contains("headphone") || type.contains("headset"): .headphones
                        case type.contains("mouse"): .mouse
                        case type.contains("keyboard"): .keyboard
                        case type.contains("trackpad"): .trackpad
                        default: .other
                        }
                        let address = details["device_address"] as? String ?? name
                        devices.append(ConnectedDevice(
                            id: address,
                            name: name,
                            kind: kind,
                            percent: percent,
                            detail: caseLevel.map { "Case \($0)%" }
                        ))
                    }
                }
            }
            return devices.sorted { $0.name < $1.name }
        }.value
    }
}

struct DevicesView: View {
    @ObservedObject var devices: Devices

    var body: some View {
        Group {
            if devices.list.isEmpty {
                Text(devices.isLoading ? "Checking devices..." : "No battery devices connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(devices.list) { DeviceGauge(device: $0) }
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: 400)
                }
            }
        }
        .task {
            devices.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                devices.refresh()
            }
        }
    }
}

private struct DeviceGauge: View {
    let device: ConnectedDevice

    private var tint: Color {
        if device.isCharging { return .green }
        return device.percent <= 20 ? .red : device.percent <= 40 ? .orange : .green
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.ink.opacity(0.14), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(device.percent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: device.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.ink)
                if device.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 18, y: -18)
                }
            }
            .frame(width: 46, height: 46)

            VStack(spacing: 1) {
                Text("\(device.percent)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.ink)
                Text(device.detail ?? device.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.ink.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(width: 72)
        .help(device.name)
    }
}
