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
        case .floating: String(localized: "Above windows")
        case .desktop: String(localized: "On the desktop")
        }
    }
}

enum FishSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
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

/// How auto-knock spaces its knocks around the chosen interval.
enum Rhythm: String, CaseIterable, Identifiable {
    case steady, quickening, natural
    var id: Self { self }
    var title: String {
        switch self {
        case .steady: String(localized: "Steady")
        case .quickening: String(localized: "Quickening")
        case .natural: String(localized: "Natural")
        }
    }

    /// The quiet before auto-knock's knock number `n`, counting from 0.
    func gap(before n: Int, interval: Double) -> Double {
        switch self {
        case .steady:
            return interval
        case .natural:
            // A hand keeping time: each gap a little long or short, about 0.7 to 1.4 times.
            return interval * exp(.random(in: -0.35...0.35))
        case .quickening:
            // 起板: a round of fifteen knocks that starts slow and quickens
            // into a roll, then a rest before the next round begins.
            let k = n % 15
            if k == 0 { return n == 0 ? interval : interval * 5 }
            return max(interval * 2.5 * pow(0.1, Double(k - 1) / 13), 0.15)
        }
    }
}

@MainActor @Observable
final class Fish {
    static let shared = Fish()

    /// Time from the start of the swing until the mallet meets the wood, and
    /// how much of it the small lift before the swing takes.
    static let impactDelay = 0.13
    static let liftDuration = 0.05
    /// A typed key gets a short, quick swing, so the knock keeps up with the hand.
    static let quickImpactDelay = 0.03

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let sound = KnockSound()
    @ObservationIgnored private let typing = TypingWatcher()
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    @ObservationIgnored var onWindowChange: (() -> Void)?
    @ObservationIgnored private var skinWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var skinFileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var skinRefresh: Task<Void, Never>?
    /// When the mallet last met the wood, on the system uptime clock.
    @ObservationIgnored private var lastImpact = -Double.infinity

    private(set) var strikes = 0
    /// Whether the latest swing is a quick one, for a typed key.
    private(set) var quickStrike = false
    /// Counts the moments the mallet meets the figure. Nothing else is
    /// counted: knocking earns no merit.
    private(set) var impacts = 0
    /// How fully the last knock rang: 0 after a rushed knock, 1 after a long quiet.
    private(set) var bloom = 1.0
    private(set) var notice: Quote?
    /// Auto-knocks since it was turned on, for Stop after 108.
    private var autoRound = 0
    /// Auto-knocks since the rhythm last changed, so a new rhythm starts at its beginning.
    private var rhythmStep = 0
    /// The stick of incense burning beside the fish, if one is lit.
    private(set) var incense: Incense?
    @ObservationIgnored private var incenseTask: Task<Void, Never>?

    var autoKnock: Bool {
        didSet { defaults.set(autoKnock, forKey: "autoKnock"); autoRound = 0; rhythmStep = 0; restartAuto() }
    }
    var interval: Double {
        didSet { defaults.set(interval, forKey: "interval"); restartAuto() }
    }
    var rhythm: Rhythm {
        didSet { defaults.set(rhythm.rawValue, forKey: "rhythm"); rhythmStep = 0; restartAuto() }
    }
    var stopAt108: Bool { didSet { defaults.set(stopAt108, forKey: "stopAt108") } }
    /// Each key pressed in any app knocks once. Typed knocks are never answered.
    var knockAsYouType: Bool {
        didSet { defaults.set(knockAsYouType, forKey: "knockAsYouType"); watchTyping() }
    }
    var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    /// The room the knock rings in: 0 a small meditation room, 1 a great hall.
    var space: Double {
        didSet {
            defaults.set(space, forKey: "space")
            // Rendering the room takes a moment, so wait for the slider to settle.
            spaceChange?.cancel()
            spaceChange = Task {
                try? await Task.sleep(for: .seconds(0.25))
                guard !Task.isCancelled else { return }
                sound.use(voice: pack.voice, space: Float(space))
            }
        }
    }
    @ObservationIgnored private var spaceChange: Task<Void, Never>?
    /// While another app listens to a microphone, as in a meeting, only a
    /// knock by hand sounds; the others swing in silence.
    var quietWhileMicInUse: Bool {
        didSet { defaults.set(quietWhileMicInUse, forKey: "quietWhileMicInUse") }
    }
    var size: FishSize {
        didSet { defaults.set(size.rawValue, forKey: "size"); onWindowChange?() }
    }
    /// The worn skin's `SkinOption.id`: "" for the wooden fish.
    var skin: String {
        didSet {
            defaults.set(skin, forKey: "skin")
            // Only the worn skin's folder is watched, so read the skins folder
            // afresh: another skin may have changed since the list was made.
            refreshSkins()
            loadSkin()
        }
    }
    private(set) var pack = SkinOption.woodenFish.pack
    /// The worn skin, small enough for the menu bar.
    private(set) var menuIcon = SkinOption.woodenFish.pack.idle.menuBarIcon()
    /// The skins in `skinsDirectory`.
    private(set) var skins: [SkinOption] = []
    /// Every skin to choose from: those that ship with the app, then the user's.
    var allSkins: [SkinOption] { SkinOption.builtIn + skins }

    /// The community gallery, where skins are shared as .plinthskin files.
    static let moreSkins = URL(string: "https://github.com/rubycatco/plinth-skins")!

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
            "interval": 1.0, "volume": 0.8, "space": Double(KnockSynth.Hall.defaultSpace), "size": FishSize.medium.rawValue,
            "placement": Placement.floating.rawValue, "quietWhileMicInUse": true,
        ])
        autoKnock = d.bool(forKey: "autoKnock")
        interval = d.double(forKey: "interval")
        rhythm = Rhythm(rawValue: d.string(forKey: "rhythm") ?? "") ?? .steady
        stopAt108 = d.bool(forKey: "stopAt108")
        knockAsYouType = d.bool(forKey: "knockAsYouType")
        volume = d.double(forKey: "volume")
        space = d.double(forKey: "space")
        quietWhileMicInUse = d.bool(forKey: "quietWhileMicInUse")
        size = FishSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        placement = Placement(rawValue: d.string(forKey: "placement") ?? "") ?? .floating
        launchAtLogin = SMAppService.mainApp.status == .enabled
        skin = d.string(forKey: "skin") ?? ""
        refreshSkins()
        loadSkin()
        watchSkins()
        restartAuto()
        typing.onPress = { [weak self] in self?.knock(byHand: false, quick: true) }
        watchTyping()
    }

    /// Knock once. Auto-knock and typing pass `byHand: false`: only a knock on
    /// the fish itself is ever answered. `quick` is the short swing for typing.
    func knock(byHand: Bool = true, quick: Bool = false) {
        quickStrike = quick
        strikes += 1
        Task {
            try? await Task.sleep(for: .seconds(quick ? Self.quickImpactDelay : Self.impactDelay))
            let now = ProcessInfo.processInfo.systemUptime
            bloom = Self.bloom(afterSilence: now - lastImpact)
            lastImpact = now
            impacts += 1
            if byHand || !quietWhileMicInUse || !Microphone.inUseByOthers() {
                sound.play(volume: Float(volume), bloom: Float(bloom))
            }
            if byHand {
                // A Force Touch trackpad taps back as the mallet lands. macOS
                // plays it only while a finger rests on the trackpad.
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                speak()
            }
        }
    }

    /// Place the knock where the fish sits: `x` runs from 0 at the screen's
    /// left edge to 1 at its right. Not all the way to one ear: it is beside you.
    func heard(at x: Double) {
        sound.pan = Float((min(max(x, 0), 1) * 2 - 1) * 0.5)
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
        skins = files.sorted().compactMap { name in
            SkinPack.load(Self.skinsDirectory.appending(path: name)).map {
                SkinOption(id: name, title: $0.name ?? (name as NSString).deletingPathExtension, pack: $0)
            }
        }
    }

    /// Add the images, skin folders or `.plinthskin` files the user picks.
    func addSkins() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, SkinArchive.type]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose images, skin folders that contain idle.png, or .plinthskin files")
        guard panel.runModal() == .OK else { return }
        install(panel.urls)
    }

    /// Copy images, skin folders and `.plinthskin` files into the skins folder,
    /// replacing any of the same name, and wear the first.
    func install(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var added: [String] = []
        var refused: [String] = []
        for url in urls {
            var source = url
            var name = url.lastPathComponent
            let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: scratch) }
            if url.pathExtension.lowercased() == "plinthskin" {
                guard let folder = try? SkinArchive.unpack(url, into: scratch) else {
                    refused.append(url.lastPathComponent)
                    continue
                }
                source = folder
                // The folder inside keeps its name when a download is renamed "skin (1)".
                name = folder == scratch ? url.deletingPathExtension().lastPathComponent : folder.lastPathComponent
            }
            let dest = Self.skinsDirectory.appending(path: name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: source, to: dest)) != nil, SkinPack.load(dest) != nil {
                added.append(name)
            } else {
                try? FileManager.default.removeItem(at: dest)
                refused.append(url.lastPathComponent)
            }
        }
        refreshSkins()
        if let first = added.first { skin = first }
        if !refused.isEmpty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Some skins couldn't be added")
            alert.informativeText = refused.joined(separator: "\n") + "\n\n"
                + String(localized: "A skin is an image, or a folder with idle.png. A .plinthskin file is such a folder, zipped.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// Save a skin of your own as a `.plinthskin` file, to share.
    func export(_ option: SkinOption) {
        let folder = Self.skinsDirectory.appending(path: option.id)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [SkinArchive.type]
        panel.nameFieldStringValue = "\(option.id).plinthskin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !SkinArchive.pack(folder, to: url) { NSSound.beep() }
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
            if !allSkins.contains(where: { $0.id == skin }) { skin = "" } else { loadSkin() }
        }
    }

    private func loadSkin() {
        pack = (allSkins.first { $0.id == skin } ?? SkinOption.woodenFish).pack
        menuIcon = pack.idle.menuBarIcon()
        sound.use(voice: pack.voice, space: Float(space))
        skinFileWatcher?.cancel()
        let isOwn = skins.contains { $0.id == skin }
        skinFileWatcher = isOwn ? watch(Self.skinsDirectory.appending(path: skin), [.write, .extend, .delete, .rename]) : nil
    }

    func show(_ quote: Quote, for seconds: Double = 8) {
        notice = quote
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if notice == quote { notice = nil }
        }
    }

    /// Light a stick of incense: one knock as it is lit, quiet while it burns,
    /// three knocks as it goes out. Nothing is counted or kept.
    func lightIncense(minutes: Int) {
        incenseTask?.cancel()
        let stick = Incense(lit: .now, duration: Double(minutes) * 60)
        incense = stick
        knock(byHand: false)
        incenseTask = Task { [weak self] in
            // The continuous clock keeps burning while the Mac sleeps.
            try? await Task.sleep(for: .seconds(stick.duration))
            guard let self, !Task.isCancelled else { return }
            // The spent stick stays while the ember dies and its last smoke
            // drifts away under the three knocks. A new stick lit between
            // the knocks ends this one's.
            for i in 0..<3 {
                if i > 0 { try? await Task.sleep(for: .seconds(1.6)) }
                guard !Task.isCancelled else { return }
                knock(byHand: false)
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            incense = nil
        }
    }

    /// Put the incense out early, without a knock.
    func putOutIncense() {
        incenseTask?.cancel()
        incense = nil
    }

    private func watchTyping() {
        if knockAsYouType { typing.start() } else { typing.stop() }
    }

    private func restartAuto() {
        autoTask?.cancel()
        autoTask = nil
        guard autoKnock else { return }
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let gap = self.map({ $0.rhythm.gap(before: $0.rhythmStep, interval: $0.interval) }) else { return }
                try? await Task.sleep(for: .seconds(gap))
                guard let self, !Task.isCancelled else { return }
                knock(byHand: false)
                autoRound += 1
                rhythmStep += 1
                // One turn of the mala, then quiet. The quiet says the rest.
                if stopAt108 && autoRound >= 108 { autoKnock = false }
            }
        }
    }
}

/// The worn skin's knock, synthesized, and its hall. A small pool of players
/// lets fast knocks overlap instead of cutting off.
///
/// The engine runs only while a knock rings. A running engine holds the audio
/// output open, which keeps the Mac from idle sleep and costs CPU even in silence.
@MainActor
final class KnockSound {
    private struct Slot {
        let dry: AVAudioPlayerNode
        let hall: AVAudioPlayerNode
        var freeAt = 0.0
    }

    /// How long the engine stays up after the last knock has rung out, so a
    /// run of knocks doesn't start it again for each one.
    private static let linger = 2.0

    private let engine = AVAudioEngine()
    private var slots: [Slot] = []
    private var cache: [KnockSynth.Variation] = []
    private var voice = ""
    private var space = KnockSynth.Hall.defaultSpace
    private var quiet: Task<Void, Never>?
    private let mono = AVAudioFormat(standardFormatWithSampleRate: Double(KnockSynth.sampleRate), channels: 1)!
    private let stereo = AVAudioFormat(standardFormatWithSampleRate: Double(KnockSynth.sampleRate), channels: 2)!

    init() {
        for _ in 0..<12 {
            let dry = AVAudioPlayerNode()
            let hall = AVAudioPlayerNode()
            engine.attach(dry)
            engine.attach(hall)
            engine.connect(dry, to: engine.mainMixerNode, format: mono)
            engine.connect(hall, to: engine.mainMixerNode, format: stereo)
            slots.append(Slot(dry: dry, hall: hall))
        }
        engine.prepare()
    }

    /// Wear this voice, in a room of this size. Unknown names, and none, are
    /// the wooden fish.
    func use(voice name: String?, space: Float) {
        let next = KnockSynth.resolve(name)
        guard next != voice || space != self.space else { return }
        voice = next
        self.space = space
        cache = KnockSynth.prepare(next, space: space)
    }

    /// Where the fish sits, from -1 at the screen's left edge to 1 at its
    /// right. Knocks still ringing move with it.
    var pan: Float = 0 {
        didSet {
            for slot in slots {
                slot.dry.pan = pan
                slot.hall.pan = pan
            }
        }
    }

    /// Play one knock. `bloom` (0...1) is how much of the hall rings with it;
    /// a rushed knock is also a little quieter.
    func play(volume: Float, bloom: Float) {
        guard !cache.isEmpty, !slots.isEmpty else { return }
        // A player node raises an exception if played while its engine is down.
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let index = slots.indices.filter { slots[$0].freeAt <= now }.randomElement()
            ?? slots.indices.min { slots[$0].freeAt < slots[$1].freeAt }!
        let variation = cache.randomElement()!
        // No two knocks are quite the same.
        let rate = Float.random(in: 0.98...1.02)
        let gain = volume * .random(in: 0.88...1.0)
        let ringsHall = bloom > 0.01
        guard let dry = buffer(variation.dry, format: mono, rate: rate) else { return }
        start(slots[index].dry, dry, volume: gain * (0.8 + 0.2 * bloom))
        var until = now + Double(dry.frameLength) / Double(KnockSynth.sampleRate)
        if ringsHall, let hall = buffer(variation.left, variation.right, format: stereo, rate: rate) {
            start(slots[index].hall, hall, volume: gain * bloom)
            until = max(until, now + Double(hall.frameLength) / Double(KnockSynth.sampleRate))
        } else {
            slots[index].hall.stop()
        }
        slots[index].freeAt = until
        pauseWhenQuiet()
    }

    /// Pause the engine once every knock has rung out, plus `linger`.
    private func pauseWhenQuiet() {
        quiet?.cancel()
        let ringsUntil = slots.map(\.freeAt).max() ?? 0
        let wait = ringsUntil + Self.linger - ProcessInfo.processInfo.systemUptime
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(wait, 0)))
            guard !Task.isCancelled, let self else { return }
            self.engine.pause()
        }
    }

    private func start(_ node: AVAudioPlayerNode, _ buffer: AVAudioPCMBuffer, volume: Float) {
        node.stop()
        node.volume = volume
        node.scheduleBuffer(buffer, completionHandler: nil)
        node.play()
    }

    private func buffer(_ samples: [Float], format: AVAudioFormat, rate: Float) -> AVAudioPCMBuffer? {
        guard samples.count > 1,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Float(samples.count) / rate) + 1),
              let dst = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(write(samples, into: dst, capacity: Int(buf.frameCapacity), rate: rate))
        return buf
    }

    private func buffer(_ left: [Float], _ right: [Float], format: AVAudioFormat, rate: Float) -> AVAudioPCMBuffer? {
        guard left.count > 1,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Float(left.count) / rate) + 1),
              let l = buf.floatChannelData?[0], let r = buf.floatChannelData?[1] else { return nil }
        let n = write(left, into: l, capacity: Int(buf.frameCapacity), rate: rate)
        _ = write(right, into: r, capacity: Int(buf.frameCapacity), rate: rate)
        buf.frameLength = AVAudioFrameCount(n)
        return buf
    }

    private func write(_ samples: [Float], into dst: UnsafeMutablePointer<Float>, capacity: Int, rate: Float) -> Int {
        var n = 0
        var pos: Float = 0
        let last = samples.count - 1
        while n < capacity && pos < Float(last) {
            let j = Int(pos)
            let f = pos - Float(j)
            dst[n] = samples[j] + (samples[j + 1] - samples[j]) * f
            pos += rate
            n += 1
        }
        return n
    }
}
