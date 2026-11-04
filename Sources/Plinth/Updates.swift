import AppKit
import Observation
#if APPSTORE

/// The App Store updates Plinth, so this build never updates itself and
/// shows no update menu item or setting.
@MainActor @Observable
final class Updates {
    static let shared = Updates()
    let waiting = false
    let canCheck = false
    let available = false
    var checksAutomatically = false
    func start() {}
    func check() {}
}
#else
import Sparkle

/// New versions from GitHub releases, through Sparkle. Only builds signed for
/// release have a feed: scripts/build_app.sh drops it from ad hoc builds, so a
/// build of your own never offers to replace itself with ours.
@MainActor @Observable
final class Updates: NSObject {
    static let shared = Updates()

    /// A check the user didn't start found a newer Plinth. Sparkle shows it
    /// behind other windows, since the app has no Dock icon to bounce; the
    /// menu item says so until the user looks at it.
    private(set) var waiting = false
    private(set) var canCheck = false
    /// Whether this build can update itself at all.
    private(set) var available = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Ask GitHub once a day whether there is a newer Plinth.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        available = true
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    /// Check now, or bring a waiting update to the front.
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.updater.checkForUpdates()
    }
}

extension Updates: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !state.userInitiated { waiting = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waiting = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        waiting = false
    }
}
#endif
