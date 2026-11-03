import AppKit
import AVFoundation
import Observation
import ServiceManagement
import UniformTypeIdentifiers

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
    /// When the mallet last met the wood, on the system uptime clock.
    @ObservationIgnored private var lastImpact = -Double.infinity

    private(set) var strikes = 0
    /// Counts the moments the mallet meets the figure. Nothing else is
    /// counted: knocking earns no merit.
    private(set) var impacts = 0
    /// How fully the last knock rang: 0 after a rushed knock, 1 after a long quiet.
    private(set) var bloom = 1.0
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
            "interval": 1.0, "volume": 0.8, "size": FishSize.medium.rawValue,
            "placement": Placement.floating.rawValue,
        ])
        autoKnock = d.bool(forKey: "autoKnock")
        interval = d.double(forKey: "interval")
        stopAt108 = d.bool(forKey: "stopAt108")
        volume = d.double(forKey: "volume")
        size = FishSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        placement = Placement(rawValue: d.string(forKey: "placement") ?? "") ?? .floating
        launchAtLogin = SMAppService.mainApp.status == .enabled
        skin = d.string(forKey: "skin") ?? ""
        refreshSkins()
        loadSkin()
        watchSkins()
        restartAuto()
    }

    /// Knock once. Auto-knock passes `byHand: false`: only a person's knock
    /// is ever answered.
    func knock(byHand: Bool = true) {
        strikes += 1
        Task {
            try? await Task.sleep(for: .seconds(Self.impactDelay))
            let now = ProcessInfo.processInfo.systemUptime
            bloom = Self.bloom(afterSilence: now - lastImpact)
            lastImpact = now
            impacts += 1
            sound.play(volume: Float(volume), bloom: Float(bloom))
            if byHand { speak() }
        }
    }

    /// The longer the quiet before a knock, the more fully it rings: none of
    /// the hall after a rushed knock, all of it after twenty seconds of quiet.
    static func bloom(afterSilence seconds: Double) -> Double {
        let x = (log(seconds) - log(0.8)) / (log(20) - log(0.8))
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The fish has a few things to say and says each of them once: the next
    /// line, on the first knock by hand each day. After the last, it only knocks.
    private func speak() {
        let said = defaults.integer(forKey: "said")
        let today = Self.today()
        guard said < Zen.sayings.count, defaults.string(forKey: "lastSaidDay") != today else { return }
        defaults.set(said + 1, forKey: "said")
        defaults.set(today, forKey: "lastSaidDay")
        let saying = Zen.sayings[said]
        // Long enough to read slowly.
        show(saying, for: min(14, max(7, Double(saying.text.count) * 0.4)))
    }

    private static func today() -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
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

    func show(_ quote: Quote, for seconds: Double = 8) {
        notice = quote
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if notice == quote { notice = nil }
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
                knock(byHand: false)
                autoRound += 1
                // One turn of the mala, then quiet. The quiet says the rest.
                if stopAt108 && autoRound >= 108 { autoKnock = false }
            }
        }
    }
}

/// The knock and its hall. Each voice pairs a dry knock with the same knock's
/// reverberation in a large wooden hall (`knockN-hall.wav`); a small pool of
/// voices lets fast knocks overlap instead of cutting off.
final class KnockSound {
    private struct Voice {
        let dry: AVAudioPlayer
        let hall: AVAudioPlayer?
        var isPlaying: Bool { dry.isPlaying || hall?.isPlaying == true }
    }

    private var voices: [Voice] = []

    init() {
        for i in 1...3 {
            guard let dryURL = Bundle.main.url(forResource: "knock\(i)", withExtension: "wav") else { continue }
            let hallURL = Bundle.main.url(forResource: "knock\(i)-hall", withExtension: "wav")
            for _ in 0..<4 {
                guard let dry = Self.player(dryURL) else { continue }
                voices.append(Voice(dry: dry, hall: hallURL.flatMap(Self.player)))
            }
        }
    }

    private static func player(_ url: URL) -> AVAudioPlayer? {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.enableRate = true
        p.prepareToPlay()
        return p
    }

    /// Play one knock. `bloom` (0...1) is how much of the hall rings with it;
    /// a rushed knock is also a little quieter.
    func play(volume: Float, bloom: Float) {
        guard let voice = voices.filter({ !$0.isPlaying }).randomElement() ?? voices.randomElement() else { return }
        // No two knocks are quite the same.
        let rate = Float.random(in: 0.97...1.03)
        let gain = volume * .random(in: 0.88...1.0)
        start(voice.dry, rate: rate, volume: gain * (0.8 + 0.2 * bloom))
        if let hall = voice.hall, bloom > 0.01 {
            start(hall, rate: rate, volume: gain * bloom)
        }
    }

    private func start(_ player: AVAudioPlayer, rate: Float, volume: Float) {
        player.stop()
        player.currentTime = 0
        player.rate = rate
        player.volume = volume
        player.play()
    }
}
