import Foundation

/// One row in the candidate strip.
struct T9Candidate {
    enum Source: String {
        case exact = "全拼"
        case prefix = "未完"
        case shorthand = "简拼"
        case fuzzy = "模糊"
    }

    let word: String
    let weight: Int
    let source: Source
    let score: Double
}

/// 九宫格拼音 engine: digits in, candidates out.
///
/// The habits it follows are the ones that make a Chinese phone keyboard feel
/// right:
///   - 全拼, 简拼 and 首音节联想 in one list, best guess first
///   - 上屏过的词往前排, and the word you chose for this exact digit string comes
///     back first the next time you type those digits
///   - 尾字联想 after committing, so you can keep tapping instead of retyping
///   - 模糊音 n↔l and f↔h — off by default, marked and de-ranked when on
final class T9Engine {

    private enum DefaultsKey {
        static let seen = "t9.seen"
        static let lastChoice = "t9.lastChoice"
        static let fuzzy = "t9.fuzzy"
    }

    private let dictionary = T9Dictionary.shared
    private let defaults: UserDefaults

    /// What the user has typed on the 九宫格 so far.
    private(set) var digits = ""
    /// The last word that went into the text field, for 尾字联想.
    private(set) var lastCommittedWord = ""
    private(set) var isFuzzyEnabled: Bool

    /// word -> how many times the user actually sent it.
    private var seen: [String: Int]
    /// digits -> the word the user picked for them last time.
    private var lastChoice: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seen = defaults.dictionary(forKey: DefaultsKey.seen) as? [String: Int] ?? [:]
        lastChoice = defaults.dictionary(forKey: DefaultsKey.lastChoice) as? [String: String] ?? [:]
        isFuzzyEnabled = defaults.bool(forKey: DefaultsKey.fuzzy)
    }

    var isComposing: Bool { !digits.isEmpty }

    var isReady: Bool { dictionary.isReady }

    // MARK: - Composing

    func append(_ digit: String) {
        guard digits.count < 24 else { return }
        digits += digit
    }

    /// Returns false when there was nothing left to delete, so the caller can
    /// fall through to deleting real text.
    @discardableResult
    func deleteLast() -> Bool {
        guard !digits.isEmpty else { return false }
        digits.removeLast()
        return true
    }

    func clear() {
        digits = ""
    }

    /// Called once a word actually lands in the text field.
    func commit(_ word: String) {
        lastCommittedWord = word
        if !digits.isEmpty {
            lastChoice[digits] = word
        }
        seen[word, default: 0] += 1
        digits = ""
        persist()
    }

    func forgetChain() {
        lastCommittedWord = ""
    }

    func setFuzzy(_ enabled: Bool) {
        isFuzzyEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.fuzzy)
    }

    /// Forget everything learned on this device: word frequencies and the
    /// per-digit choices.
    func resetLearning() {
        seen.removeAll()
        lastChoice.removeAll()
        lastCommittedWord = ""
        defaults.removeObject(forKey: DefaultsKey.seen)
        defaults.removeObject(forKey: DefaultsKey.lastChoice)
    }

    private func persist() {
        // Keep the learning tables small enough for a keyboard extension.
        if seen.count > 400 {
            seen = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(300))
        }
        if lastChoice.count > 400 {
            lastChoice = Dictionary(uniqueKeysWithValues: lastChoice.prefix(300))
        }
        defaults.set(seen, forKey: DefaultsKey.seen)
        defaults.set(lastChoice, forKey: DefaultsKey.lastChoice)
    }

    // MARK: - Candidates

    func candidates(limit: Int = 9) -> [T9Candidate] {
        let key = digits
        guard !key.isEmpty, dictionary.isReady else { return [] }

        var pool: [T9Candidate] = []

        for entry in dictionary.exact(key, limit: limit) {
            pool.append(candidate(entry, source: .exact, coverage: 1, penalty: 1))
        }
        // 首音节: what people mean when they keep tapping after 2-3 keys.
        for word in dictionary.wordsStarting(withSyllable: key, limit: limit) {
            pool.append(T9Candidate(
                word: word,
                weight: 0,
                source: .prefix,
                score: 900 * 0.75
            ))
        }
        for entry in dictionary.shorthand(key, limit: limit) {
            pool.append(candidate(entry, source: .shorthand, coverage: 0.5, penalty: 1))
        }
        if isFuzzyEnabled {
            for variant in fuzzyVariants(of: key) {
                for entry in dictionary.exact(variant, limit: 4) {
                    pool.append(candidate(entry, source: .fuzzy, coverage: 0.45, penalty: 1))
                }
            }
        }

        // One row per word, keeping its strongest source.
        var best: [String: T9Candidate] = [:]
        for item in pool where (best[item.word]?.score ?? -1) < item.score {
            best[item.word] = item
        }

        let ranked = best.values.map { item -> T9Candidate in
            var score = item.score
            let uses = seen[item.word, default: 0]
            if uses > 0 {
                score *= 1 + 2.2 * min(1.6, log1p(Double(uses)))
            }
            if lastChoice[key] == item.word { score *= 1.8 }
            return T9Candidate(word: item.word, weight: item.weight, source: item.source, score: score)
        }
        .sorted { $0.score > $1.score }

        return Array(ranked.prefix(limit))
    }

    /// 尾字联想 for the strip when nothing is being composed.
    func chainSuggestions(limit: Int = 8) -> [String] {
        guard !isComposing, let last = lastCommittedWord.last else { return [] }
        return dictionary.chain(after: String(last), limit: limit)
    }

    // MARK: - Ranking

    private func candidate(
        _ entry: T9Entry,
        source: T9Candidate.Source,
        coverage: Double,
        penalty: Double
    ) -> T9Candidate {
        // Longer words win a little when they cover the same digits, and the
        // dictionary weight decides the rest.
        let lengthBonus = 1 + Double(max(0, entry.word.count - 1)) * 0.12
        return T9Candidate(
            word: entry.word,
            weight: entry.weight,
            source: source,
            score: Double(entry.weight) * coverage * penalty * lengthBonus
        )
    }

    /// 模糊音: one substitution per key position, so 你 (64) also offers 里 (54).
    private func fuzzyVariants(of digits: String) -> [String] {
        var variants: [String] = []
        for (index, character) in digits.enumerated() {
            let swapped: Character?
            switch character {
            case "5": swapped = "6"
            case "6": swapped = "5"
            case "3": swapped = "4"
            case "4": swapped = "3"
            default: swapped = nil
            }
            guard let swapped else { continue }
            var characters = Array(digits)
            characters[index] = swapped
            variants.append(String(characters))
        }
        return variants
    }
}
