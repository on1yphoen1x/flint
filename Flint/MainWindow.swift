import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case lyrics, shelf, general, media, notch, lockScreen, ember, updates

    var id: Self { self }

    static let library: [Page] = [.lyrics, .shelf]
    static let settings: [Page] = [.general, .media, .notch, .lockScreen, .ember, .updates]

    var title: String {
        switch self {
        case .lyrics: "Lyrics"
        case .shelf: "Shelf"
        case .general: "General"
        case .media: "Media"
        case .notch: "Notch"
        case .lockScreen: "Lock Screen"
        case .ember: "Ember"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .lyrics: "quote.bubble"
        case .shelf: "tray.full"
        case .general: "gearshape"
        case .media: "play.square"
        case .notch: "rectangle.topthird.inset.filled"
        case .lockScreen: "lock.rectangle"
        case .ember: "record.circle"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .lyrics: .pink
        case .shelf: .blue
        case .general: .gray
        case .media: .red
        case .notch: .indigo
        case .lockScreen: .teal
        case .ember: .orange
        case .updates: .green
        }
    }
}

struct MainWindow: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var shelf: Shelf
    @ObservedObject var updater: Updater
    let lockScreen: LockScreenLyrics
    let weather: Weather

    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.lyricsEnabled) private var lyricsEnabled = true
    @State private var page: Page?
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var isFullScreen = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $page) {
                Section {
                    ForEach(library) { SidebarRow(page: $0).tag($0) }
                }
                Section("Settings") {
                    ForEach(Page.settings) { SidebarRow(page: $0).tag($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch page ?? library[0] {
            case .lyrics:
                LyricsView(lyrics: lyrics, nowPlaying: nowPlaying, isFullScreen: isFullScreen)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                toggleFullScreen()
                            } label: {
                                Label(isFullScreen ? "Exit Full Screen" : "Full Screen Lyrics",
                                      systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            }
                            .help(isFullScreen ? "Exit full screen" : "Show lyrics full screen")
                        }
                    }
            case .shelf:
                ShelfPage(shelf: shelf)
            case .general:
                GeneralSettings(weather: weather)
            case .media:
                MediaSettings(nowPlaying: nowPlaying)
            case .notch:
                NotchSettings()
            case .lockScreen:
                LockScreenSettings(lockScreen: lockScreen)
            case .ember:
                EmberSettings()
            case .updates:
                UpdateSettings(updater: updater)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .onChange(of: lyricsEnabled) { _, enabled in
            if !enabled && page == .lyrics { page = .shelf }
        }
        .onAppear {
            if page == nil { page = library[0] }
            NSApp.setActivationPolicy(.regular)
            MainWindowOpener.action = { openWindow(id: "main") }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
            columns = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            if page == .lyrics {
                isFullScreen = true
                columns = .detailOnly
            }
        }
    }

    private var library: [Page] {
        lyricsEnabled ? Page.library : Page.library.filter { $0 != .lyrics }
    }

    private func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) else { return }
        window.toggleFullScreen(nil)
    }
}

struct ShelfPage: View {
    @ObservedObject var shelf: Shelf
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shelf")
                        .font(.system(size: 22, weight: .bold))
                    Text("Files you drop on the notch wait here until you drag them somewhere else.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !shelf.items.isEmpty {
                    Button("AirDrop All") { shelf.airDrop(shelf.items) }
                    Button("Clear") { shelf.clear() }
                }
            }

            if shelf.items.isEmpty {
                Text("Drag files onto the notch or into this window.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfTile(url: url, shelf: shelf)
                                .environment(\.colorScheme, .dark)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

struct SidebarRow: View {
    let page: Page

    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
