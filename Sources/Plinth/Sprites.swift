import SwiftUI

/// A skin is a folder of square sprite frames plus a little metadata:
///
///     idle.png    resting pose (required)
///     blink.png   shown for a moment every few seconds (optional)
///     hit.png     shown right after the mallet lands (optional)
///     skin.json   {"strike": [x, y]}: where the mallet head's centre lands,
///                 as a fraction of the frame, y down (optional)
///
/// A single image file in the skins folder also works, as an idle-only skin.
/// The app composes the animation: idle and blink while waiting; on a knock the
/// shared mallet swings onto `strike`, the frame switches to hit, an impact
/// flash bursts and the sound plays, then it settles back to idle.
struct SkinPack {
    var idle: NSImage
    var blink: NSImage?
    var hit: NSImage?
    var strike = CGPoint(x: 0.6, y: 0.3)

    static let builtIn = load(Bundle.main.url(forResource: "wooden-fish", withExtension: nil, subdirectory: "Skins"))
        ?? SkinPack(idle: NSImage())

    static func load(_ url: URL?) -> SkinPack? {
        guard let url else { return nil }
        if let image = NSImage(contentsOf: url) { return SkinPack(idle: image) }
        func frame(_ name: String) -> NSImage? { NSImage(contentsOf: url.appending(path: "\(name).png")) }
        guard let idle = frame("idle") else { return nil }
        var pack = SkinPack(idle: idle, blink: frame("blink"), hit: frame("hit"))
        struct Meta: Decodable { var strike: [Double] }
        if let data = try? Data(contentsOf: url.appending(path: "skin.json")),
           let meta = try? JSONDecoder().decode(Meta.self, from: data), meta.strike.count == 2 {
            pack.strike = CGPoint(x: meta.strike[0], y: meta.strike[1])
        }
        return pack
    }
}

/// Shared sprites, and where the mallet's head and grip sit in its image.
enum Sprite {
    static let mallet = load("mallet")
    static let impact = load("impact")
    static let malletHead = UnitPoint(x: 0.169, y: 0.505)
    static let malletGrip = UnitPoint(x: 0.964, y: 0.505)
    /// Mallet image size as a fraction of the frame.
    static let malletSize = 0.6
    /// At impact the handle rises this far above horizontal toward the grip;
    /// at rest the mallet is lifted this much further around the grip.
    static let strikeDegrees = 15.0
    static let raiseDegrees = 25.0

    private static func load(_ name: String) -> NSImage {
        Bundle.main.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
    }
}

struct SpriteFish: View {
    let pack: SkinPack
    let side: CGFloat
    @Environment(Fish.self) private var fish
    @State private var blinking = false
    @State private var hit = false

    var body: some View {
        let frame = hit ? (pack.hit ?? pack.idle) : blinking ? (pack.blink ?? pack.idle) : pack.idle
        ZStack {
            Image(nsImage: frame).resizable()
            impact
            mallet
        }
        .frame(width: side, height: side)
        .onChange(of: fish.impacts) { _, n in
            hit = true
            Task {
                try? await Task.sleep(for: .seconds(0.25))
                if fish.impacts == n { hit = false }
            }
        }
        .task(id: pack.blink == nil) {
            guard pack.blink != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(.random(in: 3...6)))
                blinking = true
                try? await Task.sleep(for: .seconds(0.14))
                blinking = false
            }
        }
    }

    /// The mallet hangs from its grip, which sits up and to the right of the
    /// strike point; all motion is rotation around the grip.
    private var mallet: some View {
        let size = side * Sprite.malletSize
        let reach = (Sprite.malletGrip.x - Sprite.malletHead.x) * size
        let a = Sprite.strikeDegrees * .pi / 180
        let grip = CGPoint(x: pack.strike.x * side + reach * cos(a), y: pack.strike.y * side - reach * sin(a))
        let hit = -Sprite.strikeDegrees, rest = hit + Sprite.raiseDegrees
        return Image(nsImage: Sprite.mallet)
            .resizable()
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: rest, trigger: fish.strikes) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: Sprite.malletGrip)
            } keyframes: { _ in
                KeyframeTrack {
                    // A small lift, the swing, then the rebound.
                    CubicKeyframe(rest + 6, duration: 0.04)
                    CubicKeyframe(hit, duration: Fish.impactDelay - 0.04)
                    SpringKeyframe(rest, duration: 0.45, spring: .bouncy)
                }
            }
            .position(x: grip.x + (0.5 - Sprite.malletGrip.x) * size,
                      y: grip.y + (0.5 - Sprite.malletGrip.y) * size)
            .allowsHitTesting(false)
    }

    /// A neon burst just under the mallet head where it meets the figure.
    private var impact: some View {
        let size = side * 0.26
        let headRadius = side * Sprite.malletSize * 0.13
        return Image(nsImage: Sprite.impact)
            .resizable()
            .frame(width: size, height: size)
            .blendMode(.screen)
            .keyframeAnimator(initialValue: Flash(), trigger: fish.impacts) { content, v in
                content.scaleEffect(v.scale).opacity(v.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.4, duration: 0.01)
                    CubicKeyframe(1.15, duration: 0.3)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: 0.01)
                    LinearKeyframe(1.0, duration: 0.08)
                    CubicKeyframe(0.0, duration: 0.25)
                }
            }
            .position(x: pack.strike.x * side, y: pack.strike.y * side + headRadius)
            .allowsHitTesting(false)
    }
}

private struct Flash {
    var scale = 0.3
    var opacity = 0.0
}
