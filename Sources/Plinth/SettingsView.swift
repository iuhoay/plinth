import SwiftUI

struct SettingsView: View {
    @Environment(Fish.self) private var fish

    var body: some View {
        @Bindable var fish = fish
        Form {
            Section("Knocking") {
                Toggle("Auto-knock", isOn: $fish.autoKnock)
                LabeledContent("Interval") {
                    HStack {
                        Slider(value: $fish.interval, in: 0.4...4, step: 0.1)
                        Text(String(format: "%.1f s", fish.interval))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Toggle("Stop auto-knock after 108 knocks", isOn: $fish.stopAt108)
                LabeledContent("Volume") { Slider(value: $fish.volume, in: 0...1) }
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
            Section("Skin") {
                Picker("Knock on", selection: $fish.skin) {
                    Text("Wooden Fish").tag("")
                    ForEach(fish.skins, id: \.self) { name in
                        Text((name as NSString).deletingPathExtension).tag(name)
                    }
                }
                HStack {
                    Button("Add Skins…") { fish.addSkins() }
                    Button("Open Skins Folder") { NSWorkspace.shared.open(Fish.skinsDirectory) }
                }
                Text("A skin is a folder with idle.png, blink.png, hit.png and skin.json (where the mallet lands). A single image works too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Why a Fish") {
                QuoteView(quote: Zen.whyFish).frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
