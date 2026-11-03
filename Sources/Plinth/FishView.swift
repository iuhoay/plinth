import SwiftUI

/// Moves the borderless panel while the fish is dragged.
@MainActor enum PanelMover {
    static weak var panel: NSPanel?
    private static var start: (mouse: NSPoint, origin: NSPoint)?

    static func drag() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if start == nil { start = (mouse, panel.frame.origin) }
        guard let start else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    static func end() { start = nil }
}

struct FishView: View {
    @Environment(Fish.self) private var fish

    var body: some View {
        let side = fish.size.side
        VStack(spacing: 0) {
            SpriteFish(pack: fish.pack, side: side)
                .frame(width: side, height: side)
                .onTapGesture { fish.knock() }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { _ in PanelMover.drag() }
                    .onEnded { _ in PanelMover.end() })
                .contextMenu { FishMenu() }
                .help("Click to knock · Drag to move · Right-click for options")
            caption
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: fish.notice)
    }

    /// The fish's few words, when it has something to say. Otherwise nothing.
    @ViewBuilder private var caption: some View {
        if let quote = fish.notice {
            QuoteView(quote: quote).bubble()
        }
    }
}

struct QuoteView: View {
    let quote: Quote

    var body: some View {
        VStack(spacing: 3) {
            Text(quote.text)
                .font(.system(size: 12, design: .serif))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(quote.source)")
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func bubble() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
            .transition(.opacity)
    }
}

/// The skins that ship with the app, then any in the skins folder.
struct SkinPicker: View {
    @Environment(Fish.self) private var fish

    var body: some View {
        @Bindable var fish = fish
        Picker("Skin", selection: $fish.skin) {
            ForEach(SkinOption.builtIn) { Text($0.title).tag($0.id) }
            if !fish.skins.isEmpty {
                Divider()
                ForEach(fish.skins) { Text($0.title).tag($0.id) }
            }
        }
        .pickerStyle(.inline)
    }
}

/// Shared by the menu bar item and the fish's right-click menu.
struct FishMenu: View {
    @Environment(Fish.self) private var fish
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var fish = fish
        Button("Knock") { fish.knock() }
        Toggle("Auto-Knock", isOn: $fish.autoKnock)
        Picker("Pace", selection: $fish.interval) {
            Text("Slow · every 2 s").tag(2.0)
            Text("Steady · every 1 s").tag(1.0)
            Text("Fast · every 0.5 s").tag(0.5)
        }
        Toggle("Knock as You Type", isOn: $fish.knockAsYouType)
        Picker("Placement", selection: $fish.placement) {
            ForEach(Placement.allCases) { Text($0.title).tag($0) }
        }
        Menu("Skin") {
            SkinPicker()
            Divider()
            Button("Add Skins…") { fish.addSkins() }
            Button("Open Skins Folder") { NSWorkspace.shared.open(Fish.skinsDirectory) }
        }
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Quit Plinth") { NSApp.terminate(nil) }
    }
}
