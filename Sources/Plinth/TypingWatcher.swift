import AppKit
import CoreGraphics

/// Notices key presses in any app, for "Knock as you type", without any
/// special permission. It never sees which key: it only asks macOS how long
/// ago a key last went down or came up (the counters idle timers use).
@MainActor
final class TypingWatcher {
    var onPress: () -> Void = {}

    private var timer: DispatchSourceTimer?
    private var lastDown = 0.0
    private var lastPress = 0.0
    /// When the current run of key presses with no key coming up began.
    private var heldSince = 0.0

    func start() {
        guard timer == nil else { return }
        lastDown = Self.lastEvent(.keyDown)
        heldSince = lastDown
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// When the keyboard itself last sent an event of `type`, on the uptime clock.
    private static func lastEvent(_ type: CGEventType) -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
            - CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
    }

    private func check() {
        let down = Self.lastEvent(.keyDown)
        guard down > lastDown + 0.001 else { return }
        let fresh = Self.lastEvent(.keyUp) > lastDown
        if fresh { heldSince = down }
        lastDown = down
        // A held key repeats with no key coming up in between, so only its
        // first press counts. Keys rolled over quickly while typing still do.
        guard fresh || down - heldSince < NSEvent.keyRepeatDelay * 0.8 else { return }
        // Keys mashed together count once.
        guard down - lastPress > 0.05 else { return }
        lastPress = down
        onPress()
    }
}
