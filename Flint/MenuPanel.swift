import ServiceManagement
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var ember: EmberLink
    @ObservedObject var updater: Updater

    @AppStorage(SettingsKey.lockScreen) private var lockScreen = false
    @AppStorage(SettingsKey.showsMiniPlayer) private var showsMiniPlayer = true
    @AppStorage(SettingsKey.islandStyle) private var style = IslandStyle.solid
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var updateMessage: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            MenuNowPlaying(nowPlaying: nowPlaying)

            if ember.isRunning {
                MenuEmberRow(ember: ember)
            }

            HStack(spacing: 8) {
                QuickToggle(title: "Lock Screen", symbol: "lock.rectangle", isOn: $lockScreen)
                QuickToggle(title: "Mini Player", symbol: "pip", isOn: $showsMiniPlayer)
                QuickToggle(title: "Glass", symbol: "drop", isOn: Binding(
                    get: { style == .glass },
                    set: { style = $0 ? .glass : .solid }
                ))
                QuickToggle(title: "At Login", symbol: "power", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchesAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            if let release = updater.available {
                Button {
                    Task {
                        do {
                            try await updater.install()
                        } catch {
                            updateMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label(updater.isInstalling ? "Installing..." : "Install build \(release.build)", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(updater.isInstalling)
            }

            if let updateMessage {
                Text(updateMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                FooterButton(title: "Open Flint", symbol: "macwindow") {
                    openWindow(id: "main")
                    MainWindowOpener.open()
                }
                FooterButton(title: "Updates", symbol: "arrow.triangle.2.circlepath") {
                    Task {
                        let reached = await updater.check()
                        updateMessage = !reached ? "Couldn't reach GitHub." : updater.available == nil ? "You're on build \(updater.currentBuild), the latest." : nil
                    }
                }
                Spacer(minLength: 0)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .help("Quit Flint")
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct MenuNowPlaying: View {
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        Group {
            if let track = nowPlaying.track {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ArtworkView(image: nowPlaying.artwork, cornerRadius: 9)
                            .frame(width: 52, height: 52)
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(track.artist)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Scrubber(nowPlaying: nowPlaying, duration: track.duration)
                    HStack(spacing: 30) {
                        TransportButton(symbol: "backward.fill", size: 13) { nowPlaying.previousTrack() }
                        TransportButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 19) { nowPlaying.togglePlayPause() }
                        TransportButton(symbol: "forward.fill", size: 13) { nowPlaying.nextTrack() }
                    }
                }
                .padding(12)
            } else {
                IdleView(nowPlaying: nowPlaying)
                    .frame(height: 96)
            }
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                Color.black
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30)
                        .opacity(0.75)
                }
                Color.black.opacity(0.35)
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MenuEmberRow: View {
    @ObservedObject var ember: EmberLink

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                Circle()
                    .fill(ember.isActive ? Color.red : ember.isClipping ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ember.isActive ? "Recording" : ember.isClipping ? "Clipping" : "Ember")
                        .font(.system(size: 12, weight: .semibold))
                    Text(ember.isActive
                         ? RecordingClock.format(ember.elapsed(at: context.date))
                         : ember.isClipping ? RecordingClock.format(ember.clippingElapsed(at: context.date)) : "Clipping is off")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if ember.isActive {
                    SmallAction(symbol: "stop.fill", help: "Stop recording") { ember.stop() }
                } else if ember.isClipping {
                    SmallAction(symbol: "film.stack", help: "Save clip") { ember.saveClip() }
                    SmallAction(symbol: "stop.fill", help: "Stop clipping") { ember.stopClipping() }
                } else {
                    SmallAction(symbol: "play.fill", help: "Start clipping") { ember.startClipping() }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct SmallAction: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct QuickToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(isOn ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
                    .foregroundStyle(isOn ? .white : .primary)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

private struct FooterButton: View {
    let title: String
    let symbol: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
