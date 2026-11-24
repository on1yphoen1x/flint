import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var ember: EmberLink
    @ObservedObject var shelf: Shelf
    @ObservedObject var devices: DeviceWatcher
    @ObservedObject var weather: Weather

    @AppStorage(SettingsKey.islandStyle) private var style = IslandStyle.solid
    @AppStorage(SettingsKey.showsMedia) private var showsMedia = true
    @AppStorage(SettingsKey.showsEmber) private var showsEmber = true

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        let size = model.size
        let isVisible = model.isExpanded || model.showsCompact
        let shape = IslandShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)

        ZStack(alignment: .top) {
            Group {
                if style != .solid && model.isExpanded {
                    GlassFill(headerHeight: model.headerHeight, isLight: style == .light)
                } else {
                    Color.black
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(isVisible ? 1 : 0)

            content
                .frame(width: max(size.width - model.topRadius * 2, 0), height: size.height, alignment: .top)
        }
        // Everything is clipped to the island itself, so content shrinks away with it
        // instead of lingering outside while it fades.
        .frame(width: size.width, height: size.height, alignment: .top)
        .mask(shape)
        .overlay {
            if style != .solid && model.isExpanded {
                shape
                    .stroke(LinearGradient(colors: [.clear, .white.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .frame(width: size.width, height: size.height)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, style == .light && model.isExpanded ? .light : .dark)
        .animation(spring, value: model.isExpanded)
        .animation(spring, value: model.isWelcoming)
        .onChange(of: shelf.items.isEmpty) { _, isEmpty in
            if isEmpty && model.isPinned {
                withAnimation(spring) { model.close() }
            }
        }
        .animation(spring, value: style)
        .animation(spring, value: model.showsCompact)
        .animation(spring, value: model.showsRecording)
        .animation(spring, value: model.showsClipSaved)
        .animation(spring, value: model.showsClipping)
        .animation(spring, value: model.alert?.id)
        .animation(spring, value: model.notchSize)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.tab)
    }

    private var shrink: AnyTransition {
        .scale(scale: 0.4, anchor: .top).combined(with: .opacity)
    }

    @ViewBuilder
    private var content: some View {
        if model.isWelcoming {
            WelcomeView(model: model)
                .padding(.top, model.headerHeight)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .transition(shrink)
        } else if model.isExpanded {
            VStack(spacing: 0) {
                IslandHeader(model: model, shelf: shelf, weather: weather)
                    .frame(height: model.headerHeight)
                Group {
                    switch model.tab {
                    case .recording:
                        RecordingPanelView(ember: ember)
                    case .media:
                        MediaPlayerView(nowPlaying: nowPlaying, lyrics: model.lyrics)
                    case .devices:
                        DevicesView(devices: model.batteries)
                    case .shelf:
                        ShelfView(shelf: shelf, isTargeted: model.isDropTargeted)
                    }
                }
                .frame(height: IslandModel.expandedContentHeight)
                .id(model.tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                shelf.add(urls)
                model.pin()
                return true
            } isTargeted: { targeted in
                model.isDropTargeted = targeted
                if targeted { model.tab = .shelf }
            }
            .transition(shrink)
        } else if let alert = model.alert {
            CompactAlertView(alert: alert, gap: model.gap, height: model.notchSize.height)
                .id(alert.id)
                .transition(shrink)
        } else if model.showsRecording {
            CompactRecordingView(ember: ember, gap: model.gap, height: model.notchSize.height)
                .transition(shrink)
                .onTapGesture {
                    withAnimation(spring) { model.setExpanded(true) }
                }
        } else if model.showsClipSaved {
            CompactClipSavedView(gap: model.gap, height: model.notchSize.height)
                .transition(shrink)
        } else if model.showsClipping {
            CompactClippingView(ember: ember, gap: model.gap, height: model.notchSize.height)
                .transition(shrink)
                .onTapGesture {
                    withAnimation(spring) { model.setExpanded(true, for: .recording) }
                }
        } else if model.showsCompact {
            CompactMediaView(nowPlaying: nowPlaying, gap: model.gap, height: model.notchSize.height)
                .transition(shrink)
                .onTapGesture {
                    withAnimation(spring) { model.setExpanded(true) }
                }
        }
    }
}

/// Tabs sit beside the camera on notched displays, using space that would otherwise be empty.
struct IslandHeader: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var shelf: Shelf
    @ObservedObject var weather: Weather

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs, id: \.self) { tab in
                Button {
                    model.tab = tab
                } label: {
                    Image(systemName: symbol(for: tab))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.45))
                        .frame(width: 28, height: 22)
                        .background(.white.opacity(model.tab == tab ? 0.16 : 0), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(title(for: tab))
            }
            Spacer(minLength: model.hasNotch ? model.notchSize.width + 12 : 8)
            HStack(spacing: 10) {
                if !shelf.items.isEmpty {
                    Text(shelf.items.count == 1 ? "1 file" : "\(shelf.items.count) files")
                }
                if let conditions = weather.conditions {
                    Label(conditions.temperatureText, systemImage: conditions.symbol)
                        .labelStyle(.titleAndIcon)
                }
                if model.isPinned {
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.close() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(.white.opacity(0.16), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .help("Close")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func symbol(for tab: IslandModel.Tab) -> String {
        switch tab {
        case .media: "music.note"
        case .shelf: "tray.full"
        case .devices: "battery.75percent"
        case .recording: "record.circle"
        }
    }

    private func title(for tab: IslandModel.Tab) -> String {
        switch tab {
        case .media: "Now Playing"
        case .shelf: "Shelf"
        case .devices: "Devices"
        case .recording: "Ember"
        }
    }
}
