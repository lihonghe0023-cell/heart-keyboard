import Foundation

/// One line the keyboard offers for the current message field.
struct Suggestion {
    let text: String
    /// Short tag shown above the line: 「✨ 结合 TA 刚说的话」 or 「🎯 稳」.
    let badge: String?

    /// True when the line answers something concrete rather than a category.
    var isContextAware: Bool { badge != nil }
}

/// The whole "brain" of the keyboard.
///
/// It is offline, dependency free and deterministic: no network call, no model
/// download, nothing to review for privacy. Everything it knows lives in
/// `Lines.swift`.
final class ReplyEngine {

    private enum DefaultsKey {
        static let persona = "hk.persona"
        static let scene = "hk.scene"
        static let tone = "hk.tone"
        static let autoScene = "hk.autoScene"
    }

    private let defaults: UserDefaults
    private var recentLines: [String] = []

    private(set) var personaID: String
    private(set) var sceneID: String
    private(set) var toneID: String

    /// When true, sending a message walks the conversation forward one scene,
    /// the way the prototype does. Choosing a scene by hand turns this off.
    private(set) var advancesAutomatically: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedPersona = defaults.string(forKey: DefaultsKey.persona)
        personaID = storedPersona ?? Lines.personas[0].id
        sceneID = defaults.string(forKey: DefaultsKey.scene)
            ?? Lines.persona(personaID).startingScene
        toneID = defaults.string(forKey: DefaultsKey.tone) ?? Lines.tones[0].id
        advancesAutomatically = defaults.object(forKey: DefaultsKey.autoScene) as? Bool ?? true
    }

    var persona: Persona { Lines.persona(personaID) }
    var scene: Scene { Lines.scene(sceneID) }
    var tone: Tone { Lines.tone(toneID) }

    var sweetness: Int { tone.sweetness }
    var risk: String { tone.risk }
    var tip: String { Lines.tip(persona: personaID, scene: sceneID) }
    var header: String { "✨ 心跳建议 · \(tone.label) · \(scene.label)" }

    // MARK: - State changes

    func select(persona id: String) {
        personaID = id
        sceneID = Lines.persona(id).startingScene
        recentLines.removeAll()
        advancesAutomatically = true
        persist()
    }

    func select(scene id: String) {
        sceneID = id
        advancesAutomatically = false
        persist()
    }

    func select(tone id: String) {
        toneID = id
        persist()
    }

    /// Remember what the user actually sent, and move to the next scene when
    /// the conversation is flowing on its own.
    func noteSent(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentLines.removeAll { $0 == trimmed }
        recentLines.insert(trimmed, at: 0)
        if recentLines.count > 6 { recentLines.removeLast(recentLines.count - 6) }

        guard advancesAutomatically,
              let index = Lines.sceneFlow.firstIndex(of: sceneID),
              index + 1 < Lines.sceneFlow.count else { return }
        sceneID = Lines.sceneFlow[index + 1]
        persist()
    }

    // MARK: - Suggestions

    /// - Parameter context: recent text around the cursor, when the host app
    ///   exposes it. Used to answer what the other person actually just said.
    func suggestions(context: String, limit: Int = 3) -> [Suggestion] {
        var result: [Suggestion] = []
        let haystack = context.lowercased()

        if let hook = Lines.contextHooks.first(where: { hook in
            hook.keywords.contains { haystack.contains($0) }
        }) {
            let text = filled(hook.text, context: context)
            if !recentLines.contains(text) {
                result.append(Suggestion(text: text, badge: "✨ 结合 TA 刚说的话"))
            }
        }

        let pool = Lines.repliesByScene[sceneID]?[toneID] ?? []
        let all = pool.map { filled($0, context: context) }
        var fresh = all.filter { !recentLines.contains($0) }.shuffled()
        if fresh.count < limit { fresh = all.shuffled() }

        for text in fresh where result.count < limit {
            result.append(Suggestion(text: text, badge: nil))
        }
        return Array(result.prefix(limit))
    }

    /// A plausible reply from the other person, for the demo chat in the host app.
    func partnerReply() -> String {
        let pool = Lines.partnerReplies[sceneID] ?? ["嗯嗯，然后呢？"]
        return pool.randomElement() ?? "嗯嗯，然后呢？"
    }

    /// Substitutes `{last}` with a short, readable version of what the other
    /// person said, so a line never reads like a form letter.
    private func filled(_ template: String, context: String) -> String {
        guard template.contains("{last}") else { return template }
        let junk = CharacterSet(charactersIn: "，。！？、,.!?…~ \n\t")
        let cleaned = context
            .components(separatedBy: junk)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return template.replacingOccurrences(of: "{last}", with: "你说的那句")
        }
        let short = cleaned.count > 10 ? String(cleaned.prefix(10)) + "…" : cleaned
        return template.replacingOccurrences(of: "{last}", with: short)
    }

    private func persist() {
        defaults.set(personaID, forKey: DefaultsKey.persona)
        defaults.set(sceneID, forKey: DefaultsKey.scene)
        defaults.set(toneID, forKey: DefaultsKey.tone)
        defaults.set(advancesAutomatically, forKey: DefaultsKey.autoScene)
    }
}
