import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            KnockingSettings().tabItem { Label("Knocking", systemImage: "hand.tap") }
            SkinSettings().tabItem { Label("Skins", systemImage: "paintpalette") }
            AboutSettings().tabItem { Label("Why a Fish", systemImage: "fish") }
        }
        .frame(width: 500)
    }
}

private struct KnockingSettings: View {
    @Environment(Fish.self) private var fish

    var body: some View {
        @Bindable var fish = fish
        Form {
            Section {
                LabeledContent("Volume") {
                    Slider(value: $fish.volume, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Space") {
                    Slider(value: $fish.space, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Meditation room").foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Great hall").foregroundStyle(.secondary)
                    }
                }
                Toggle("Knock as you type", isOn: $fish.knockAsYouType)
                if Microphone.canTell {
                    Toggle("Quiet while a microphone is in use", isOn: $fish.quietWhileMicInUse)
                }
            } header: {
                Text("Knocking")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Typing: each key you press, in any app, knocks once. Plinth only notices when a key goes down, never which key, so it needs no special permission.")
                        .settingsFootnote()
                    if Microphone.canTell {
                        Text("Quiet: while another app listens to a microphone, as in a call, only a knock by hand sounds. Plinth never listens itself.")
                            .settingsFootnote()
                    }
                }
            }
            Section {
                Toggle("Knock on its own", isOn: $fish.autoKnock)
                LabeledContent("Every") {
                    HStack {
                        Slider(value: $fish.interval, in: 0.4...4) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "hare").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "tortoise").foregroundStyle(.secondary)
                        }
                        Text("\(fish.interval, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!fish.autoKnock)
                Picker("Rhythm", selection: $fish.rhythm) {
                    ForEach(Rhythm.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!fish.autoKnock)
                Toggle("Stop after 108 knocks, one turn of a mala", isOn: $fish.stopAt108)
                    .disabled(!fish.autoKnock)
            } header: {
                Text("Auto-Knock")
            } footer: {
                Text("Quickening starts slow and quickens into a roll, as a chant begins, then rests. Natural lets each gap run a little long or short, like a hand keeping time.")
                    .settingsFootnote()
            }
            Section("Display") {
                Picker("Size", selection: $fish.size) {
                    ForEach(FishSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Placement", selection: $fish.placement) {
                    ForEach(Placement.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: $fish.launchAtLogin)
            }
            if Updates.shared.available {
                UpdateSettings()
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UpdateSettings: View {
    var body: some View {
        @Bindable var updates = Updates.shared
        Section {
            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
        } header: {
            Text("Updates")
        } footer: {
            Text("Once a day, Plinth asks GitHub whether there is a newer version, and asks you before installing it. Nothing about you or your Mac is sent.")
                .settingsFootnote()
        }
    }
}

/// Every skin as a thumbnail; click one to wear it.
private struct SkinSettings: View {
    @Environment(Fish.self) private var fish

    var body: some View {
        Form {
            Section("Built In") { grid(SkinOption.builtIn) }
            Section {
                if fish.skins.isEmpty {
                    Text("No skins of your own yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    grid(fish.skins, exportable: true)
                }
                HStack {
                    Button("Add Skins…") { fish.addSkins() }
                    Button("Open Skins Folder") { NSWorkspace.shared.open(Fish.skinsDirectory) }
                    Spacer()
                    Button("Browse More Skins…") { NSWorkspace.shared.open(Fish.moreSkins) }
                }
            } header: {
                Text("Your Skins")
            } footer: {
                Text("A skin is a folder with idle.png, and optionally blink.png and hit.png (or numbered sequences like blink-1.png, blink-2.png), its own mallet.png and impact.png, and skin.json for its name, where the mallet lands, and its knock: wood, lacquer, ink, cartoon, pixel, jade, bowl, key, bamboo, stone, piston, crt, bead, plate, porcelain, bell, stamp, chime, board, or ceramic. A single image works too, and so does a .plinthskin file, a skin folder zipped to share. Right-click a skin of your own to export one.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }

    private func grid(_ options: [SkinOption], exportable: Bool = false) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(options) { option in
                SkinTile(option: option, selected: option.id == fish.skin) { fish.skin = option.id }
                    .contextMenu {
                        // A folder skin goes out as one .plinthskin file; a single image is shared as it is.
                        if exportable, (try? Fish.skinsDirectory.appending(path: option.id).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                            Button("Export as .plinthskin…") { fish.export(option) }
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SkinTile: View {
    let option: SkinOption
    let selected: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                Image(nsImage: option.pack.idle)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .scaleEffect(hovering ? 1.06 : 1)
                Text(option.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.15) : hovering ? Color.primary.opacity(0.05) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(option.title)
    }
}

/// A hanging scroll: the ink fish in an ensō on rice paper, and the rule
/// that explains it written top to bottom, right to left, with its source
/// and a seal. It stays paper in Dark Mode too; ink needs a light ground.
private struct AboutSettings: View {
    static let paper = Color(red: 0.953, green: 0.933, blue: 0.890)
    static let ink = Color(red: 0.16, green: 0.15, blue: 0.14)
    static let cinnabar = Color(red: 0.70, green: 0.20, blue: 0.15)

    private let inkFish = SkinOption.builtIn.first { $0.id == "builtin/ink-fish" } ?? .woodenFish

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ZStack {
                    Enso(color: Self.ink, opacity: 0.3)
                        .frame(width: 200, height: 200)
                    Image(nsImage: inkFish.pack.idle)
                        .resizable()
                        .frame(width: 176, height: 176)
                        // The fish sits low in its sprite, under the mallet's arc.
                        .offset(y: -24)
                }
                .padding(.top, 52)
                .frame(maxWidth: .infinity)
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 14) {
                        Column(text: Zen.whyFish.source.trimmingCharacters(in: CharacterSet(charactersIn: "《》")),
                               size: 11, color: Self.ink.opacity(0.5))
                        Seal(text: "常醒")
                    }
                    .padding(.top, 92)
                    ForEach(Array(Self.columns(Zen.whyFish.text).enumerated().reversed()), id: \.offset) { _, line in
                        Column(text: line, size: 19, color: Self.ink.opacity(0.88))
                    }
                }
                .padding(.top, 40)
                .padding(.trailing, 44)
            }
            Spacer(minLength: 24)
            Text("Knocking earns no merit.")
                .font(.system(size: 11, design: .serif))
                .tracking(1.5)
                .foregroundStyle(Self.ink.opacity(0.38))
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .background(Self.paper)
        .environment(\.colorScheme, .light)
    }

    /// One column per clause, without punctuation, as on a scroll.
    private static func columns(_ text: String) -> [String] {
        text.split(whereSeparator: { "，。、；：！？\n".contains($0) }).map(String.init)
    }
}

/// Characters stacked top to bottom.
private struct Column: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        VStack(spacing: size * 0.32) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
            }
        }
        .font(.custom("Songti SC", size: size))
        .foregroundStyle(color)
    }
}

/// A small cinnabar seal, its characters carved out in white.
private struct Seal: View {
    let text: String

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
            }
        }
        .font(.custom("Songti SC", size: 10).weight(.bold))
        .foregroundStyle(AboutSettings.paper)
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .background(AboutSettings.cinnabar, in: RoundedRectangle(cornerRadius: 2))
        .opacity(0.9)
    }
}

/// One brushstroke round, open where the brush lifted. The brush lands at the
/// lower left, goes round clockwise, thins, and runs dry: its hairs part
/// into streaks and give out one by one before the circle closes.
private struct Enso: View {
    let color: Color
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let thickest = radius * 0.15
            /// A point on the stroke at t (0 where the brush lands, 1 where
            /// the circle would close), `offset` out from its middle.
            func point(_ t: Double, _ offset: Double) -> CGPoint {
                let angle = 2.3 + 2 * Double.pi * 0.9 * t // radians, y down: from the lower left
                let r = radius - thickest / 2 + radius * 0.012 * sin(t * 9 + 0.5) + offset
                return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            }
            func width(_ t: Double) -> Double { thickest * pow(max(0, 1 - t), 1.1) }

            // The body of the stroke, thinning as the ink runs out.
            let wet = (0...180).map { 0.8 * Double($0) / 180 }
            var body = Path()
            body.addLines(wet.map { point($0, width($0) / 2) } + wet.reversed().map { point($0, -width($0) / 2) })
            body.closeSubpath()
            // Where the brush lands it presses down, a blunt drop along the stroke.
            let landing = point(0.012, 0)
            let along = atan2(point(0.03, 0).y - landing.y, point(0.03, 0).x - landing.x)
            body.addPath(Path(ellipseIn: CGRect(x: -thickest * 0.75, y: -thickest * 0.6,
                                                width: thickest * 1.5, height: thickest * 1.2)),
                         transform: CGAffineTransform(translationX: landing.x, y: landing.y).rotated(by: along))
            context.fill(body, with: .color(color))
            // Then it runs dry: a few hairs carry on alone and give out one by one.
            for (across, end) in [(-0.45, 0.86), (-0.2, 0.97), (0.05, 0.91), (0.3, 0.95), (0.48, 0.84)] {
                var hair = Path()
                hair.addLines((0...60).map { point(0.55 + (end - 0.55) * Double($0) / 60, across * width(0.55)) })
                context.stroke(hair, with: .color(color),
                               style: StrokeStyle(lineWidth: thickest * 0.09, lineCap: .round))
            }
        }
        // Overlaps don't darken: the stroke is one wash of ink.
        .compositingGroup()
        .opacity(opacity)
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.footnote).foregroundStyle(.secondary)
    }
}
