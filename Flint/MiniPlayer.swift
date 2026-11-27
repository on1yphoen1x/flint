import Combine
import SwiftUI

/// A small floating player that stays on top of other windows while something is playing.
/// Drag it anywhere; macOS remembers where it was left.
@MainActor
final class MiniPlayer {
    static let size = CGSize(width: 300, height: 68)

    private let nowPlaying: NowPlaying
    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()

    init(nowPlaying: NowPlaying) {
        self.nowPlaying = nowPlaying

        let enabled = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in Self.isEnabled }
            .prepend(Self.isEnabled)
            .removeDuplicates()
        let hasTrack = nowPlaying.$track.map { $0 != nil }.removeDuplicates()

        enabled.combineLatest(hasTrack)
            .map { $0 && $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                MainActor.assumeIsolated { self?.setVisible(visible) }
            }
            .store(in: &subscriptions)
    }

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.showsMiniPlayer, default: true)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            let panel = panel ?? makePanel()
            self.panel = panel
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let host = DraggableHostingView(rootView: MiniPlayerView(nowPlaying: nowPlaying))
        host.sizingOptions = []
        panel.contentView = host

        if !panel.setFrameUsingName("MiniPlayer"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: visible.maxX - Self.size.width - 24, y: visible.minY + 24))
        }
        panel.setFrameAutosaveName("MiniPlayer")
        return panel
    }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct MiniPlayerView: View {
    @ObservedObject var nowPlaying: NowPlaying
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(image: nowPlaying.artwork, cornerRadius: 8)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.track?.title ?? "")
                    .font(.system(size: 12, weight: .semibold))
                Text(nowPlaying.track?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                control("backward.fill", size: 11, action: { nowPlaying.previousTrack() })
                control(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 15, action: { nowPlaying.togglePlayPause() })
                control("forward.fill", size: 11, action: { nowPlaying.nextTrack() })
            }
        }
        .padding(.horizontal, 12)
        .frame(width: MiniPlayer.size.width, height: MiniPlayer.size.height)
        .overlay(alignment: .bottom) { progress }
        .background(BehindWindowBlur())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if isHovering {
                Button {
                    UserDefaults.standard.set(false, forKey: SettingsKey.showsMiniPlayer)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(.black.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Hide the mini player. Turn it back on from the menu bar or Settings.")
                .padding(4)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = nowPlaying.track?.duration ?? 0
            let fraction = duration > 0 ? nowPlaying.position(at: context.date) / duration : 0
            GeometryReader { geometry in
                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(width: geometry.size.width * fraction, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
