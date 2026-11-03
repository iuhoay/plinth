import AppKit
import AVFoundation
import Observation
import ServiceManagement
import UniformTypeIdentifiers

enum FloatMode: String, CaseIterable, Identifiable {
    case merit, zen, quiet
    var id: Self { self }
    var title: String {
        switch self {
        case .merit: "Merit +1"
        case .zen: "Zen characters"
        case .quiet: "Nothing"
        }
    }
}

enum Placement: String, CaseIterable, Identifiable {
    case floating, desktop
    var id: Self { self }
    var title: String {
        switch self {
        case .floating: "Above windows"
        case .desktop: "On the desktop"
        }
    }
}

enum FishSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
    var side: CGFloat {
        switch self {
        case .small: 150
        case .medium: 210
        case .large: 300
        }
    }
}

struct Floater: Identifiable {
    let id = UUID()
    let text: String
    let dx: CGFloat
}

@MainActor @Observable
final class Fish {
    static let shared = Fish()

    /// Time from the start of the swing until the mallet meets the wood.
    static let impactDelay = 0.1

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let sound = KnockSound()
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    @ObservationIgnored var onWindowChange: (() -> Void)?
    @ObservationIgnored private var skinWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var skinFileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var skinRefresh: Task<Void, Never>?

    private(set) var merit: Int { didSet { defaults.set(merit, forKey: "merit") } }
    private(set) var strikes = 0
    /// Counts the moments the mallet meets the figure.
    private(set) var impacts = 0
    private(set) var floaters: [Floater] = []
    private(set) var notice: Quote?
    private var autoRound = 0

    var autoKnock: Bool {
        didSet { defaults.set(autoKnock, forKey: "autoKnock"); autoRound = 0; restartAuto() }
    }
    var interval: Double {
        didSet { defaults.set(interval, forKey: "interval"); restartAuto() }
    }
    var stopAt108: Bool { didSet { defaults.set(stopAt108, forKey: "stopAt108") } }
    var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    var floatMode: FloatMode { didSet { defaults.set(floatMode.rawValue, forKey: "floatMode") } }
    var showCount: Bool { didSet { defaults.set(showCount, forKey: "showCount") } }
    var size: FishSize {
        didSet { defaults.set(size.rawValue, forKey: "size"); onWindowChange?() }
    }
    /// Name of the skin folder or image in `skinsDirectory`, or "" for the built-in fish.
    var skin: String {
        didSet { defaults.set(skin, forKey: "skin"); loadSkin() }
    }
    private(set) var pack = SkinPack.builtIn
    private(set) var skins: [String] = []

    static let skinsDirectory: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Plinth/Skins")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var placement: Placement {
        didSet { defaults.set(placement.rawValue, forKey: "placement"); onWindowChange?() }
    }
    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Plinth: launch at login failed: \(error)")
            }
        }
    }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "interval": 1.0, "volume": 0.8, "floatMode": FloatMode.merit.rawValue,
            "showCount": true, "size": FishSize.medium.rawValue,
            "placement": Placement.floating.rawValue,
        ])
        merit = d.integer(forKey: "merit")
        autoKnock = d.bool(forKey: "autoKnock")
        interval = d.double(forKey: "interval")
        stopAt108 = d.bool(forKey: "stopAt108")
        volume = d.double(forKey: "volume")
        floatMode = FloatMode(rawValue: d.string(forKey: "floatMode") ?? "") ?? .merit
        showCount = d.bool(forKey: "showCount")
        size = FishSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        placement = Placement(rawValue: d.string(forKey: "placement") ?? "") ?? .floating
        launchAtLogin = SMAppService.mainApp.status == .enabled
        skin = d.string(forKey: "skin") ?? ""
        refreshSkins()
        loadSkin()
        watchSkins()
        restartAuto()
    }

    func knock() {
        strikes += 1
        Task {
            try? await Task.sleep(for: .seconds(Self.impactDelay))
            impacts += 1
            sound.play(volume: Float(volume))
            merit += 1
            emitFloater()
            if merit % 108 == 0 { reflect() }
        }
    }

    func refreshSkins() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.skinsDirectory.path)) ?? []
        skins = files.filter { SkinPack.load(Self.skinsDirectory.appending(path: $0)) != nil }.sorted()
    }

    /// Copy the images or skin folders the user picks into the skins folder
    /// and wear the first.
    func addSkins() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose images, or skin folders that contain idle.png"
        guard panel.runModal() == .OK else { return }
        var added: [String] = []
        for url in panel.urls {
            let dest = Self.skinsDirectory.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { added.append(dest.lastPathComponent) }
        }
        refreshSkins()
        if let first = added.first { skin = first }
    }

    /// Pick up skin images added, replaced or removed while the app runs.
    /// The folder sees files added, removed or swapped in; the worn skin's own
    /// file is watched too, since overwriting it in place leaves the folder as is.
    private func watchSkins() {
        skinWatcher = watch(Self.skinsDirectory, .write)
    }

    private func watch(_ url: URL, _ events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.skinsChanged() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func skinsChanged() {
        // The folder changes as soon as a copy starts; wait for it to finish.
        skinRefresh?.cancel()
        skinRefresh = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            refreshSkins()
            if !skin.isEmpty && !skins.contains(skin) { skin = "" } else { loadSkin() }
        }
    }

    private func loadSkin() {
        let url = Self.skinsDirectory.appending(path: skin)
        pack = skin.isEmpty ? .builtIn : SkinPack.load(url) ?? .builtIn
        skinFileWatcher?.cancel()
        skinFileWatcher = skin.isEmpty ? nil : watch(url, [.write, .extend, .delete, .rename])
    }

    /// Let go: the count was never the point.
    func letGo() { merit = 0 }

    func show(_ quote: Quote, for seconds: Double = 8) {
        notice = quote
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if notice == quote { notice = nil }
        }
    }

    private func emitFloater() {
        let text: String
        switch floatMode {
        case .quiet: return
        case .merit: text = "功德 +1"
        case .zen: text = Zen.words.randomElement()!
        }
        let floater = Floater(text: text, dx: .random(in: -26...26))
        floaters.append(floater)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            floaters.removeAll { $0.id == floater.id }
        }
    }

    /// Every 108 knocks (one turn of the mala) the fish offers a teaching.
    /// The first time, it is Bodhidharma telling the emperor there is no merit.
    private func reflect() {
        if !defaults.bool(forKey: "sawNoMerit") {
            defaults.set(true, forKey: "sawNoMerit")
            show(Zen.noMerit, for: 12)
        } else {
            show(Zen.quotes.randomElement()!)
        }
    }

    private func restartAuto() {
        autoTask?.cancel()
        autoTask = nil
        guard autoKnock else { return }
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.interval ?? 1))
                guard let self, !Task.isCancelled else { return }
                knock()
                autoRound += 1
                if stopAt108 && autoRound >= 108 {
                    autoKnock = false
                    show(Quote(text: "一百零八声已尽。\n且听余音，归于寂静。", source: "木鱼"))
                }
            }
        }
    }
}

/// A small pool of players so fast knocks overlap instead of cutting off.
final class KnockSound {
    private var players: [AVAudioPlayer] = []

    init() {
        for i in 1...3 {
            guard let url = Bundle.main.url(forResource: "knock\(i)", withExtension: "wav") else { continue }
            for _ in 0..<3 {
                guard let p = try? AVAudioPlayer(contentsOf: url) else { continue }
                p.enableRate = true
                p.prepareToPlay()
                players.append(p)
            }
        }
    }

    func play(volume: Float) {
        guard let p = players.filter({ !$0.isPlaying }).randomElement() ?? players.randomElement() else { return }
        p.stop()
        p.currentTime = 0
        // No two knocks are quite the same.
        p.rate = .random(in: 0.97...1.03)
        p.volume = volume * .random(in: 0.88...1.0)
        p.play()
    }
}
