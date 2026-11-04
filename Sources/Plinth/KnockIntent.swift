import AppIntents

/// The Knock action in Shortcuts. Like `plinth://knock`, it knocks without
/// opening anything, and like auto-knock it is never answered.
struct KnockIntent: AppIntent {
    static let title: LocalizedStringResource = "Knock"
    static let description = IntentDescription("Knocks once.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Fish.shared.knock(byHand: false)
        return .result()
    }
}
