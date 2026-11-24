import AppKit
import SwiftUI

/// Shows what's playing on the lock screen: the artwork, a clock and the lyrics.
///
/// macOS has no public way for apps to draw there. This moves a window into a
/// private SkyLight space that sits at the lock screen's level, which is the same
/// approach other notch apps use. If Apple removes these functions the feature
/// quietly does nothing.
@MainActor
final class LockScreenLyrics {
    private let lyrics: Lyrics
    private let nowPlaying: NowPlaying
    private let weather: Weather
    private var window: NSWindow?
    private var controls: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var space: Int32?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.lockScreen) }
        set {
            UserDefaults.standard.set(newValue, forKey: SettingsKey.lockScreen)
            if !newValue { hide() }
        }
    }

    init(lyrics: Lyrics, nowPlaying: NowPlaying, weather: Weather) {
        self.lyrics = lyrics
        self.nowPlaying = nowPlaying
        self.weather = weather

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
    }

    private func screenLocked() {
        guard isEnabled, nowPlaying.track != nil, let screen = NSScreen.main else { return }

        let window = self.window ?? makeWindow()
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        moveToLockScreen(window)

        // The buttons live in their own small window so everything else lets clicks through to the password field.
        let controls = self.controls ?? makeControls()
        let size = LockPlayerCard.size
        controls.setFrame(CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * LockScreenView.reservedFraction + 8,
            width: size.width,
            height: size.height
        ), display: true)
        controls.orderFrontRegardless()
        self.controls = controls
        moveToLockScreen(controls)
    }

    private func hide() {
        window?.orderOut(nil)
        controls?.orderOut(nil)
    }

    private func makeControls() -> NSWindow {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = IslandHostingView(rootView: LockPlayerCard(nowPlaying: nowPlaying))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: LockScreenView(lyrics: lyrics, nowPlaying: nowPlaying, weather: weather))
        host.sizingOptions = []
        window.contentView = host
        return window
    }

    private func moveToLockScreen(_ window: NSWindow) {
        guard let api = SkyLight.shared else { return }
        let connection = api.mainConnection()
        if space == nil {
            let created = api.spaceCreate(connection, 1, 0)
            // 400 is the level the lock screen draws its own notifications at.
            _ = api.spaceSetAbsoluteLevel(connection, created, 400)
            _ = api.showSpaces(connection, [created] as CFArray)
            space = created
        }
        if let space {
            _ = api.addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        }
    }
}

private struct SkyLight {
    typealias MainConnection = @convention(c) () -> Int32
    typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    let mainConnection: MainConnection
    let spaceCreate: SpaceCreate
    let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevel
    let showSpaces: ShowSpaces
    let addWindows: AddWindows

    @MainActor static let shared: SkyLight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let main = load("SLSMainConnectionID", as: MainConnection.self),
              let create = load("SLSSpaceCreate", as: SpaceCreate.self),
              let level = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = load("SLSShowSpaces", as: ShowSpaces.self),
              let add = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self) else { return nil }
        return SkyLight(mainConnection: main, spaceCreate: create, spaceSetAbsoluteLevel: level, showSpaces: show, addWindows: add)
    }()
}

struct LockScreenView: View {
    static let reservedFraction: CGFloat = 0.24

    @ObservedObject var lyrics: Lyrics
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var weather: Weather

    @AppStorage(SettingsKey.lockScreenBackdrop) private var showsBackdrop = true
    @AppStorage(SettingsKey.lockScreenClock) private var showsClock = true
    @AppStorage(SettingsKey.lockScreenBattery) private var showsBattery = true
    @AppStorage(SettingsKey.wordByWord) private var wordByWord = true

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack {
                if showsBackdrop {
                    ArtworkBackdrop(artwork: nowPlaying.artwork, accent: Color(nsColor: nowPlaying.accent))
                }

                TimelineView(.animation(minimumInterval: 0.1)) { context in
                    VStack(spacing: 0) {
                        if showsBackdrop && showsClock {
                            LockClock(date: context.date, accent: Color(nsColor: nowPlaying.accent), showsBattery: showsBattery, weather: weather.conditions)
                                .padding(.top, height * 0.07)
                        }
                        Spacer(minLength: 20)
                        nowPlayingCard(at: context.date, height: height)
                        Spacer(minLength: 20)
                        // The player card window sits here, just above the password field and Touch ID prompt.
                        Color.clear.frame(height: height * Self.reservedFraction + LockPlayerCard.size.height + 24)
                    }
                }
            }
            .frame(width: geometry.size.width, height: height)
        }
        .environment(\.colorScheme, .dark)
    }

    private func nowPlayingCard(at date: Date, height: CGFloat) -> some View {
        let position = nowPlaying.position(at: date)
        let index = lyrics.currentIndex(at: position + 0.2)
        let lines = lyrics.lines
        let artSize = min(height * 0.24, 280)

        return VStack(spacing: 22) {
            ArtworkView(image: nowPlaying.artwork, cornerRadius: artSize * 0.07)
                .frame(width: artSize, height: artSize)
                .overlay(
                    RoundedRectangle(cornerRadius: artSize * 0.07, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 36, y: 18)
                .scaleEffect(nowPlaying.isPlaying ? 1 : 0.92)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: nowPlaying.isPlaying)

            VStack(spacing: 10) {
                if let index, lines.indices.contains(index) {
                    let line = lines[index]
                    Group {
                        if line.text.isEmpty {
                            Text("\u{266A}")
                        } else if wordByWord {
                            KaraokeLine(text: line.text, start: line.time, end: lyrics.endTime(of: index), position: position + 0.2)
                        } else {
                            Text(line.text)
                        }
                    }
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .id(line.id)
                    .transition(.opacity.combined(with: .offset(y: 12)))

                    if lines.indices.contains(index + 1) {
                        Text(lines[index + 1].text)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(minHeight: 90, alignment: .top)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: index)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .shadow(color: .black.opacity(0.35), radius: 10)
        .padding(.horizontal, 80)
    }
}

/// The artwork blown up to fill the screen, fading out before the bottom so
/// the password field stays visible.
struct ArtworkBackdrop: View {
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        ZStack {
            Color.black
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 40)
                    .saturation(1.15)
                    .opacity(0.8)
            } else {
                accent.opacity(0.25)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.66), .init(color: .clear, location: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct LockClock: View {
    let date: Date
    let accent: Color
    let showsBattery: Bool
    let weather: Weather.Conditions?

    var body: some View {
        VStack(spacing: 2) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(.system(size: 112, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(LinearGradient(colors: [.white, accent.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            HStack(spacing: 18) {
                if let weather {
                    Label(weather.temperatureText, systemImage: weather.symbol)
                }
                if showsBattery, let battery = Battery.read(at: date) {
                    Label("\(battery.percent)%", systemImage: battery.isCharging ? "bolt.fill" : battery.symbol)
                }
            }
            .font(.system(size: 14, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 4)
        }
    }
}

/// The glass player that sits above the password field. It lives in its own
/// small window so it can take clicks while the rest of the lock screen can't.
struct LockPlayerCard: View {
    static let size = CGSize(width: 380, height: 150)

    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        let accent = Color(nsColor: nowPlaying.accent)
        VStack(spacing: 10) {
            if let track = nowPlaying.track {
                HStack(spacing: 12) {
                    ArtworkView(image: nowPlaying.artwork, cornerRadius: 8)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(track.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !nowPlaying.isPlaying)) { context in
                        Waveform(time: context.date.timeIntervalSinceReferenceDate, color: accent, maxHeight: nowPlaying.isPlaying ? 16 : 4)
                    }
                    .frame(width: 22)
                }

                Scrubber(nowPlaying: nowPlaying, duration: track.duration)

                HStack(spacing: 40) {
                    TransportButton(symbol: "backward.fill", size: 16) { nowPlaying.previousTrack() }
                    TransportButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 24) { nowPlaying.togglePlayPause() }
                    TransportButton(symbol: "forward.fill", size: 16) { nowPlaying.nextTrack() }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                BehindWindowBlur()
                LinearGradient(colors: [accent.opacity(0.22), .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}
