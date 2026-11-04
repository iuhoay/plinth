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
                }
            } header: {
                Text("Your Skins")
            } footer: {
                Text("A skin is a folder with idle.png, and optionally blink.png and hit.png (or numbered sequences like blink-1.png, blink-2.png), its own mallet.png and impact.png, and skin.json for its name, where the mallet lands, and its knock: wood, lacquer, ink, cartoon, pixel, jade, bowl, key, bamboo, stone, piston, or crt. A single image works too, and so does a .plinthskin file, a skin folder zipped to share. Right-click a skin of your own to export one.")
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

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: SkinOption.woodenFish.pack.idle)
                .resizable()
                .frame(width: 120, height: 120)
            QuoteView(quote: Zen.whyFish)
                .frame(maxWidth: 380)
            Text("Knocking earns no merit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.footnote).foregroundStyle(.secondary)
    }
}
