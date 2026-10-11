import Foundation

struct SharedReply: Codable {
    let level: String
    let text: String
    let why: String
}

struct SharedCounterExample: Codable {
    let text: String
    let why: String
}

/// What the app figured out, packed for the keyboard.
///
/// The app does the reading and the thinking (it has memory and network); the
/// keyboard only has to show three lines and type one.
struct SharedAnalysis: Codable {
    var headline: String
    var feelingLabel: String
    var intentLabel: String
    var move: String
    var keyword: String
    var quote: String
    var signals: [String]
    var replies: [SharedReply]
    var counterexamples: [SharedCounterExample]
    var tips: [String]
    var source: String
    var updatedAt: Date

    var suggestions: [Suggestion] {
        replies.map { Suggestion(text: $0.text, badge: "🎯 " + $0.level) }
    }

    init(analysis: ConversationAnalysis, composition: Composition, source: String) {
        headline = analysis.headline
        feelingLabel = analysis.feelingLabel
        intentLabel = analysis.intentLabel
        move = analysis.strategy.move
        keyword = analysis.keyword
        quote = analysis.quote
        signals = analysis.signals.map { $0.title + "：" + $0.detail }
        replies = composition.replies.map {
            SharedReply(level: $0.level, text: $0.text, why: $0.why)
        }
        counterexamples = composition.counterexamples.map {
            SharedCounterExample(text: $0.text, why: $0.why)
        }
        tips = composition.tips
        self.source = source
        updatedAt = Date()
    }
}

/// The hand-off between the app and the keyboard.
enum SharedStore {

    /// Create this App Group in both targets (Signing & Capabilities → App Groups)
    /// and keep the string identical here.
    static let appGroupID = "group.com.example.heartkeyboard"

    private static let key = "hk.shared.analysis"
    private static let probeKey = "hk.probe"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ analysis: SharedAnalysis) {
        guard let data = try? JSONEncoder().encode(analysis) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> SharedAnalysis? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedAnalysis.self, from: data)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    /// True only when the App Group entitlement is actually present.
    ///
    /// A probe through `UserDefaults` is not enough: without the entitlement the
    /// suite still writes and reads back happily inside one process, it just
    /// never crosses into the other bundle. The container URL is the honest test.
    /// `false` means the app and the keyboard keep separate copies, and the
    /// keyboard should use its own 剪贴板识别 instead.
    static var isGroupAvailable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }
}
