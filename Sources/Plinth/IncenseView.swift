import SwiftUI

/// A stick of incense, lit at `lit`, that burns for `duration` seconds.
struct Incense: Equatable {
    let lit: Date
    let duration: TimeInterval

    func burnt(at date: Date) -> Double {
        min(max(date.timeIntervalSince(lit) / duration, 0), 1)
    }
}

/// The stick in its censer beside the fish: it shortens as it burns, its tip
/// glows, and a thread of smoke rises. It shows no numbers.
struct IncenseView: View {
    let incense: Incense
    let side: CGFloat

    var body: some View {
        // A few frames a second is plenty for smoke, and keeps it cheap.
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                draw(in: &gc, size: size, burnt: incense.burnt(at: context.date), t: t)
            }
        }
        .frame(width: side * 0.16, height: side * 0.85)
        .allowsHitTesting(false)
        .accessibilityLabel("Incense")
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, burnt: Double, t: Double) {
        let mid = size.width / 2
        let censer = CGSize(width: side * 0.12, height: side * 0.055)
        let rim = size.height - censer.height

        // The stick: tall when lit, down to a stub at the end.
        let stickWidth = max(side * 0.012, 1.5)
        let full = side * 0.42
        let tipY = rim - side * 0.02 - full * (1 - burnt)
        gc.fill(Path(CGRect(x: mid - stickWidth / 2, y: tipY, width: stickWidth, height: rim - tipY)),
                with: .color(Color(red: 0.55, green: 0.24, blue: 0.17)))

        // Smoke: a thin thread that sways more the higher it drifts.
        let rise = side * 0.32
        var smoke = Path()
        smoke.move(to: CGPoint(x: mid, y: tipY))
        for step in 1...24 {
            let f = Double(step) / 24
            let sway = sin(f * 5 - t * 1.3) * f * side * 0.035 + sin(f * 2.3 - t * 0.7) * f * f * side * 0.03
            smoke.addLine(to: CGPoint(x: mid + sway, y: tipY - f * rise))
        }
        gc.stroke(smoke, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.45), .white.opacity(0)]),
            startPoint: CGPoint(x: mid, y: tipY), endPoint: CGPoint(x: mid, y: tipY - rise)),
            style: StrokeStyle(lineWidth: max(side * 0.008, 1), lineCap: .round))

        // The ember, breathing a little.
        let glow = 0.75 + 0.25 * sin(t * 2.1)
        let ember = stickWidth * 1.4
        var lit = gc
        lit.addFilter(.shadow(color: Color(red: 1, green: 0.45, blue: 0.15).opacity(glow), radius: side * 0.03))
        lit.fill(Path(ellipseIn: CGRect(x: mid - ember / 2, y: tipY - ember / 2, width: ember, height: ember)),
                 with: .color(Color(red: 1, green: 0.55 + 0.2 * glow, blue: 0.25)))

        // The censer: a small dark bowl with a neon rim, like the pedestal.
        let bowl = CGRect(x: mid - censer.width / 2, y: rim, width: censer.width, height: censer.height)
        var body = Path()
        body.move(to: CGPoint(x: bowl.minX, y: bowl.minY))
        body.addQuadCurve(to: CGPoint(x: bowl.maxX, y: bowl.minY), control: CGPoint(x: bowl.midX, y: bowl.maxY + censer.height * 0.6))
        body.closeSubpath()
        gc.fill(body, with: .color(Color(white: 0.16)))
        let lip = Path(ellipseIn: CGRect(x: bowl.minX, y: bowl.minY - censer.height * 0.18,
                                         width: bowl.width, height: censer.height * 0.36))
        gc.fill(lip, with: .color(Color(white: 0.24)))
        gc.stroke(lip, with: .color(Color(red: 1, green: 0.2, blue: 0.75).opacity(0.85)), lineWidth: max(side * 0.006, 1))
    }
}
