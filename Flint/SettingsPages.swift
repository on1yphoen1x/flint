import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    let weather: Weather

    @AppStorage("showsMenuBarIcon") private var showsMenuBarIcon = true
    @AppStorage(SettingsKey.showsWeather) private var showsWeather = true
    @AppStorage(SettingsKey.roundedCorners) private var roundedCorners = true
    @AppStorage(SettingsKey.showsAlerts) private var showsAlerts = true
    @AppStorage(SettingsKey.hasWelcomed) private var hasWelcomed = true
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Open Flint when you log in", isOn: $launchesAtLogin)
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
                Toggle("Show Flint in the menu bar", isOn: $showsMenuBarIcon)
            } footer: {
                Text("Closing this window takes Flint out of the Dock. The notch and menu bar keep running until you choose Quit.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show the weather", isOn: $showsWeather)
                    .onChange(of: showsWeather) { _, _ in weather.refresh() }
                Toggle("Note charging and headphones in the notch", isOn: $showsAlerts)
                Toggle("Round the bottom corners of the screen", isOn: $roundedCorners)
            } header: {
                Text("Your Mac")
            } footer: {
                Text("Weather comes from Open-Meteo using your approximate location, which macOS asks you to allow.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Show the welcome again") { hasWelcomed = false }
            } footer: {
                Text("It appears in the notch next time Flint opens.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

struct MediaSettings: View {
    @ObservedObject var nowPlaying: NowPlaying
    @AppStorage(SettingsKey.mediaSource) private var source = SourcePreference.automatic
    @AppStorage(SettingsKey.showsMedia) private var showsMedia = true
    @AppStorage(SettingsKey.showsIslandLyrics) private var showsIslandLyrics = true
    @AppStorage(SettingsKey.lyricsEnabled) private var lyricsEnabled = true
    @AppStorage(SettingsKey.showsMiniPlayer) private var showsMiniPlayer = true

    var body: some View {
        Form {
            Section {
                Toggle("Show music in the notch", isOn: $showsMedia)
                Toggle("Show the mini player", isOn: $showsMiniPlayer)
            } footer: {
                Text("The mini player floats above your windows while music plays. Drag it wherever you like.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show lyrics", isOn: $lyricsEnabled)
                Toggle("Show the current lyric line in the notch", isOn: $showsIslandLyrics)
                    .disabled(!lyricsEnabled)
            } footer: {
                Text("Turning lyrics off hides them everywhere: the notch, the window and the lock screen. Flint stops looking them up.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 10) {
                    ForEach(SourcePreference.allCases) { option in
                        SourceCard(option: option, isSelected: source == option) {
                            source = option
                            nowPlaying.reload()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Player")
            } footer: {
                Text("Automatic follows whichever app is playing. Choose Spotify or Music to only ever show that one.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Media")
    }
}

private struct SourceCard: View {
    let option: SourcePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon
                    .frame(width: 40, height: 40)
                Text(option.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        if let source = option.source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: option.source == nil ? "wand.and.stars" : "questionmark.app")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

struct NotchSettings: View {
    @AppStorage(SettingsKey.islandStyle) private var style = IslandStyle.solid

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ForEach(IslandStyle.allCases) { option in
                        Button {
                            style = option
                        } label: {
                            VStack(spacing: 8) {
                                StylePreview(style: option)
                                    .frame(height: 74)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(style == option ? Color.accentColor : .clear, lineWidth: 2)
                                    )
                                Text(option.title)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Look")
            } footer: {
                Text("Glass lets your wallpaper show through the open notch, and Light does the same with a pale tint. The part beside the camera stays black either way.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notch")
    }
}

private struct StylePreview: View {
    let style: IslandStyle

    private var fill: AnyShapeStyle {
        switch style {
        case .solid: AnyShapeStyle(Color.black)
        case .glass: AnyShapeStyle(.ultraThinMaterial)
        case .light: AnyShapeStyle(Color.white.opacity(0.75))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.indigo, .teal, .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
                .fill(fill)
                .overlay(alignment: .top) {
                    Capsule().fill(.black).frame(width: 34, height: 8)
                }
                .frame(width: 110, height: 44)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

struct LockScreenSettings: View {
    let lockScreen: LockScreenLyrics

    @AppStorage(SettingsKey.lockScreen) private var isEnabled = false
    @AppStorage(SettingsKey.lockScreenBackdrop) private var showsBackdrop = true
    @AppStorage(SettingsKey.lockScreenClock) private var showsClock = true
    @AppStorage(SettingsKey.lockScreenBattery) private var showsBattery = true
    @AppStorage(SettingsKey.wordByWord) private var wordByWord = true

    var body: some View {
        Form {
            Section {
                Toggle("Show what's playing on the lock screen", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, enabled in lockScreen.isEnabled = enabled }
            } footer: {
                Text("This uses a part of macOS that Apple doesn't officially open to apps, so it may stop working after a macOS update.")
                    .foregroundStyle(.secondary)
            }

            Section("Layout") {
                Toggle("Fill the screen with the album artwork", isOn: $showsBackdrop)
                Toggle("Show the clock and date", isOn: $showsClock)
                    .disabled(!showsBackdrop)
                Toggle("Show battery level", isOn: $showsBattery)
                    .disabled(!showsBackdrop || !showsClock)
                Toggle("Light up lyrics word by word", isOn: $wordByWord)
            }
            .disabled(!isEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Lock Screen")
    }
}

struct EmberSettings: View {
    @AppStorage(SettingsKey.showsEmber) private var showsEmber = true

    var body: some View {
        Form {
            Section {
                Toggle("Show the clipping timer beside the notch", isOn: $showsEmber)
            } footer: {
                Text("Recordings always show in the notch. Ember's controls are in the notch's Ember tab while Ember is open.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ember")
    }
}

struct UpdateSettings: View {
    @ObservedObject var updater: Updater
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed", value: "Build \(updater.currentBuild)")
                if let release = updater.available {
                    Button(updater.isInstalling ? "Installing..." : "Install build \(release.build)") {
                        Task {
                            do {
                                try await updater.install()
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                    .disabled(updater.isInstalling)
                } else {
                    Button("Check for Updates") {
                        Task {
                            let reached = await updater.check()
                            message = !reached ? "Couldn't reach GitHub." : updater.available == nil ? "You're on the latest build." : nil
                        }
                    }
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
    }
}
