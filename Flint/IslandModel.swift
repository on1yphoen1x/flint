import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    enum Tab: Hashable {
        case media, shelf, devices, recording
    }

    static let compactWing: CGFloat = 38
    static let recordingWing: CGFloat = 66
    static let expandedWidth: CGFloat = 460
    static let expandedContentHeight: CGFloat = 124

    @Published var notchSize = CGSize(width: 0, height: 24)
    @Published var hasNotch = false
    @Published var tab = Tab.media
    @Published var isDropTargeted = false
    @Published private(set) var isExpanded = false
    @Published private(set) var isWelcoming = false
    /// Set when files are dropped on the notch, so it stays open until closed by hand.
    @Published private(set) var isPinned = false

    let nowPlaying: NowPlaying
    let ember: EmberLink
    let shelf: Shelf
    let lyrics: Lyrics
    let devices: DeviceWatcher
    let weather: Weather
    let batteries = Devices()

    init(nowPlaying: NowPlaying, ember: EmberLink, shelf: Shelf, lyrics: Lyrics, devices: DeviceWatcher, weather: Weather) {
        self.nowPlaying = nowPlaying
        self.ember = ember
        self.shelf = shelf
        self.lyrics = lyrics
        self.devices = devices
        self.weather = weather
    }

    /// Charging and headphone notes briefly take over the closed island.
    var alert: IslandAlert? {
        guard UserDefaults.standard.bool(forKey: SettingsKey.showsAlerts, default: true) else { return nil }
        return devices.alert
    }

    /// A recording takes the island over from music until it stops.
    var showsRecording: Bool {
        ember.isActive
    }

    private var showsMedia: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.showsMedia, default: true)
    }

    private var showsEmber: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.showsEmber, default: true)
    }

    var showsClipSaved: Bool {
        !showsRecording && ember.justSavedClip
    }

    /// Clipping sits above music, since it usually means a game is running full screen.
    var showsClipping: Bool {
        showsEmber && !showsRecording && !showsClipSaved && ember.isClipping
    }

    var showsCompact: Bool {
        alert != nil || showsRecording || showsClipSaved || showsClipping || (showsMedia && nowPlaying.isPlaying && nowPlaying.track != nil)
    }

    var tabs: [Tab] {
        if showsRecording { return [.recording, .media, .shelf, .devices] }
        return ember.isRunning ? [.media, .shelf, .devices, .recording] : [.media, .shelf, .devices]
    }

    var topRadius: CGFloat {
        isExpanded ? 14 : 6
    }

    var bottomRadius: CGFloat {
        if isExpanded { return 30 }
        return hasNotch ? 10 : notchSize.height / 2
    }

    /// The space the hardware notch takes up between the left and right halves of the compact pill.
    var gap: CGFloat {
        hasNotch ? notchSize.width : 28
    }

    var headerHeight: CGFloat {
        hasNotch ? notchSize.height : 30
    }

    var size: CGSize {
        if isExpanded {
            let width = max(Self.expandedWidth, notchSize.width + 220)
            return CGSize(width: width + topRadius * 2, height: headerHeight + Self.expandedContentHeight + 14)
        }
        if showsCompact {
            let wing = alert != nil || showsRecording || showsClipSaved || showsClipping ? Self.recordingWing : Self.compactWing
            return CGSize(width: gap + wing * 2 + topRadius * 2, height: notchSize.height)
        }
        return hasNotch ? CGSize(width: notchSize.width + topRadius * 2, height: notchSize.height) : .zero
    }

    func welcome() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        isWelcoming = true
        isExpanded = true
    }

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: SettingsKey.hasWelcomed)
        isWelcoming = false
        isExpanded = false
    }

    func setExpanded(_ expanded: Bool, for preferred: Tab? = nil) {
        guard !isWelcoming else { return }
        if let preferred { tab = preferred }
        if !tabs.contains(tab) { tab = .media }
        guard expanded != isExpanded, expanded || !isPinned else { return }
        if expanded {
            nowPlaying.refreshPosition()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } else {
            isDropTargeted = false
        }
        isExpanded = expanded
    }

    func pin() {
        isPinned = true
        tab = .shelf
        isExpanded = true
    }

    func close() {
        isPinned = false
        isDropTargeted = false
        isExpanded = false
    }
}
