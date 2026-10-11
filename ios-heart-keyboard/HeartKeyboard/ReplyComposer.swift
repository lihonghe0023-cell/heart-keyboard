import Foundation

/// One ready-to-send line, with the reasoning behind it.
struct ComposedReply {
    /// 稳 / 暖 / 进 — how far the line moves the conversation.
    let level: String
    let text: String
    let why: String
}

/// The full answer to「这条消息我该怎么回」.
struct Composition {
    let replies: [ComposedReply]
    let counterexamples: [CounterExample]
    let tips: [String]

    var suggestions: [Suggestion] {
        replies.map { Suggestion(text: $0.text, badge: "🎯 " + $0.level) }
    }
}

/// Builds high-EQ replies from an analysis.
///
/// The shape is always the same, which is what makes it reliable:
///
///   opening (接住情绪) + one of {steady closer, specific care, light push}
///
/// 「稳」only receives the emotion, 「暖」 turns it into specific care, and 「进」
/// moves the conversation one step forward without overreaching.
enum ReplyComposer {

    static func compose(
        _ analysis: ConversationAnalysis,
        toneID: String,
        personaID: String
    ) -> Composition {
        let strategy = analysis.strategy
        let openings = strategy.openings.shuffled()

        func opening(_ index: Int) -> String {
            guard !openings.isEmpty else { return "" }
            return filled(openings[index % openings.count], analysis)
        }

        let steady = filled(
            ReplyStrategy.steadyClosers.randomElement() ?? "我在。",
            analysis
        )
        let middle = filled(strategy.middles.randomElement() ?? "", analysis)
        let push = filled(strategy.push, analysis) + ReplyStrategy.pushTail(persona: personaID)

        let replies = [
            ComposedReply(
                level: "稳",
                text: flavor(join(opening(0), steady), tone: toneID),
                why: "只做接情绪、不给方案 —— 最不容易出错的一档。"
            ),
            ComposedReply(
                level: "暖",
                text: flavor(join(opening(1), middle), tone: toneID),
                why: "接住情绪后，把关心落到一件具体的事上。"
            ),
            ComposedReply(
                level: "进",
                text: flavor(join(opening(2), push), tone: toneID),
                why: "接住情绪，再往前推一格：把 TA 从屏幕里拉出来。"
            ),
        ]

        var tips = strategy.tips
        tips.append("这条建议只解决「怎么回」，不解决「该不该继续」——那个你自己决定。")

        return Composition(
            replies: replies,
            counterexamples: strategy.avoid,
            tips: tips
        )
    }

    // MARK: - Text assembly

    private static func join(_ first: String, _ second: String) -> String {
        guard !first.isEmpty else { return second }
        guard !second.isEmpty else { return first }
        return first + " " + second
    }

    private static func filled(_ template: String, _ analysis: ConversationAnalysis) -> String {
        guard !template.isEmpty else { return "" }
        var text = template
        text = text.replacingOccurrences(
            of: "{quote}",
            with: analysis.quote.isEmpty ? "你说的这句" : analysis.quote
        )
        text = text.replacingOccurrences(
            of: "{kw}",
            with: analysis.keyword.isEmpty ? "这件事" : analysis.keyword
        )
        return text
    }

    /// Tone is a light touch on purpose: when TA is upset, personality matters
    /// far less than getting the structure right.
    private static func flavor(_ text: String, tone: String) -> String {
        switch tone {
        case "sweet":
            if text.hasSuffix("。") { return String(text.dropLast()) + "～" }
            return text + "～"
        case "flirt":
            return text + " 这话我是认真的。"
        case "funny":
            return text + "（我承认我有点紧张）"
        case "cool":
            return firstSentence(of: text)
        default:
            return text
        }
    }

    private static func firstSentence(of text: String) -> String {
        guard let end = text.firstIndex(of: "。") else { return text }
        return String(text[text.startIndex...end])
    }
}
