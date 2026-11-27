import Combine
import Foundation

/// Fetches lyrics for whatever is playing from LRCLIB, a free lyrics database that
/// includes timings for many songs.
@MainActor
final class Lyrics: ObservableObject {
    struct Line: Identifiable, Equatable, Sendable {
        let id: Int
        let time: Double
        let text: String
    }

    enum Content: Equatable {
        case none
        case loading
        case synced([Line])
        case plain([String])
        case instrumental
        case notFound
    }

    @Published private(set) var content = Content.none

    private let nowPlaying: NowPlaying
    private var cache: [String: Content] = [:]
    private var subscription: AnyCancellable?
    private var settingObserver: AnyCancellable?
    private var request: Task<Void, Never>?

    init(nowPlaying: NowPlaying) {
        self.nowPlaying = nowPlaying
        subscription = nowPlaying.$track
            .removeDuplicates()
            .sink { [weak self] track in
                MainActor.assumeIsolated { self?.load(for: track) }
            }
        settingObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in Self.isEnabled }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.load(for: self.nowPlaying.track)
                }
            }
    }

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.lyricsEnabled, default: true)
    }

    var lines: [Line] {
        if case .synced(let lines) = content { return lines }
        return []
    }

    /// When the given line gives way to the next one.
    func endTime(of index: Int) -> Double {
        let lines = lines
        guard lines.indices.contains(index) else { return 0 }
        return lines.indices.contains(index + 1) ? lines[index + 1].time : lines[index].time + 5
    }

    /// The line being sung at the given position, or nil before the first one starts.
    func currentIndex(at position: Double) -> Int? {
        let lines = lines
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= position {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    private func load(for track: Track?) {
        request?.cancel()
        guard let track, Self.isEnabled else {
            content = .none
            return
        }
        let key = "\(track.artist)|\(track.title)"
        if let cached = cache[key] {
            content = cached
            return
        }
        content = .loading
        request = Task {
            let result = await Self.fetch(track)
            guard !Task.isCancelled else { return }
            cache[key] = result
            content = result
        }
    }

    private nonisolated static func fetch(_ track: Track) async -> Content {
        struct Response: Decodable {
            let instrumental: Bool?
            let plainLyrics: String?
            let syncedLyrics: String?
        }

        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]
        // Without the album and duration the lookup is looser, which helps with live
        // versions and remasters that LRCLIB files under a different album.
        let fallback = URL(string: "https://lrclib.net/api/get?" + [
            "track_name=\(encode(track.title))",
            "artist_name=\(encode(track.artist))"
        ].joined(separator: "&"))

        for url in [components.url, fallback].compactMap({ $0 }) {
            var request = URLRequest(url: url)
            request.setValue("Flint (https://getflint.uk)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try? JSONDecoder().decode(Response.self, from: data) else { continue }

            if body.instrumental == true { return .instrumental }
            if let synced = body.syncedLyrics, case let lines = parse(synced), !lines.isEmpty {
                return .synced(lines)
            }
            if let plain = body.plainLyrics, !plain.isEmpty {
                return .plain(plain.components(separatedBy: .newlines))
            }
        }
        return .notFound
    }

    private nonisolated static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? value
    }

    /// Parses LRC lines such as "[01:23.45] words". A line can carry several timestamps.
    private nonisolated static func parse(_ lrc: String) -> [Line] {
        var timed: [(Double, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    times.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                timed.append((time, text))
            }
        }
        return timed.sorted { $0.0 < $1.0 }.enumerated().map { Line(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
