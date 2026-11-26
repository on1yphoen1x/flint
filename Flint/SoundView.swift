import SwiftUI

struct SoundView: View {
    @ObservedObject var router: AudioRouter

    var body: some View {
        Group {
            if router.apps.isEmpty {
                Text("Nothing is playing sound right now.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        if let failure = router.failure {
                            Text(failure)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(router.apps) { app in
                            SoundRow(app: app, router: router)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                router.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct SoundRow: View {
    let app: AudioApp
    @ObservedObject var router: AudioRouter

    var body: some View {
        let setting = router.setting(for: app)
        HStack(spacing: 10) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.fill").foregroundStyle(.ink.opacity(0.5))
                }
            }
            .frame(width: 20, height: 20)

            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.ink.opacity(app.isPlaying ? 1 : 0.5))
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)

            Image(systemName: setting.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.ink.opacity(0.6))
                .frame(width: 16)
                .onTapGesture {
                    router.setVolume(setting.volume < 0.01 ? 1 : 0, for: app)
                }

            Slider(
                value: Binding(get: { Double(setting.volume) }, set: { router.setVolume(Float($0), for: app) }),
                in: 0...1
            )
            .controlSize(.mini)

            Menu {
                Button {
                    router.setOutput(nil, for: app)
                } label: {
                    if setting.deviceUID == nil { Image(systemName: "checkmark") }
                    Text("Follow System Output")
                }
                Divider()
                ForEach(router.outputs) { device in
                    Button {
                        router.setOutput(device.uid, for: app)
                    } label: {
                        if setting.deviceUID == device.uid { Image(systemName: "checkmark") }
                        Text(device.name)
                    }
                }
                if !setting.isDefault {
                    Divider()
                    Button("Reset") { router.reset(app) }
                }
            } label: {
                Image(systemName: setting.deviceUID == nil ? "hifispeaker" : "hifispeaker.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.ink)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(router.outputs.first { $0.uid == setting.deviceUID }?.name ?? "System output")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
