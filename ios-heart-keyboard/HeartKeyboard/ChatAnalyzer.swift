import Foundation

/// Words that point at one emotional state.
struct FeelingRule {
    let id: String
    let label: String
    let keywords: [String]
}

struct FeelingScore {
    let id: String
    let label: String
    let score: Double
}

/// Something worth knowing before you type, with the evidence behind it.
struct AnalysisSignal {
    let title: String
    let detail: String
}

/// The result of reading a conversation.
struct ConversationAnalysis {
    let messages: [ChatMessage]
    let lastFromThem: String
    /// Their last message, trimmed, for quoting back to them.
    let quote: String
    /// The concrete thing they mentioned, for example 「加班到十点」.
    let keyword: String
    let feelings: [FeelingScore]
    let primaryFeeling: String
    let feelingLabel: String
    let intentLabel: String
    let headline: String
    let signals: [AnalysisSignal]
    let strategy: Strategy
    let toneNote: String

    var isHeavyMood: Bool {
        ["tired", "upset", "sad", "anxious", "chilly", "sick"].contains(primaryFeeling)
    }

    var summaryLine: String {
        "🎯 已识别 · \(feelingLabel)"
    }
}

/// Reads a conversation and decides what the other person is feeling, what they
/// want, and which reply structure is most likely to land well.
///
/// It is deliberately rule based: runs offline, needs no model download, and can
/// explain every conclusion it draws. `ReplyProvider` layers an on-device or
/// cloud model on top when you want richer wording.
enum ChatAnalyzer {

    static let feelings: [FeelingRule] = [
        FeelingRule(id: "tired", label: "疲惫·压力", keywords: [
            "累", "好累", "加班", "忙", "忙死", "开会", "赶", "deadline", "熬夜",
            "通宵", "压力", "头疼", "项目", "甲方", "领导", "客户", "卷", "撑不住",
        ]),
        FeelingRule(id: "upset", label: "委屈·生气", keywords: [
            "气死", "生气", "讨厌", "烦人", "凭什么", "过分", "无语", "哼", "真行",
            "随便你", "受不了", "什么人", "什么意思", "不用来了",
        ]),
        FeelingRule(id: "sad", label: "低落·难过", keywords: [
            "难过", "想哭", "委屈", "不开心", "低落", "丧", "难受", "崩溃", "孤单",
            "一个人", "没意思", "提不起劲",
        ]),
        FeelingRule(id: "anxious", label: "焦虑·不安", keywords: [
            "焦虑", "慌", "担心", "紧张", "睡不着", "失眠", "怎么办", "会不会",
            "来不及", "万一", "怕",
        ]),
        FeelingRule(id: "happy", label: "开心·兴奋", keywords: [
            "哈哈", "开心", "太好了", "爽", "笑死", "耶", "终于", "赢了", "好吃",
            "舒服", "绝了", "爱了", "好棒",
        ]),
        FeelingRule(id: "bored", label: "无聊·想找你", keywords: [
            "无聊", "好闲", "没事干", "在干嘛", "干嘛呢", "睡了吗", "在吗", "刷手机",
        ]),
        FeelingRule(id: "cute", label: "撒娇·要关注", keywords: [
            "哼", "不理你了", "你真坏", "讨厌啦", "人家", "抱抱", "亲亲", "呜呜",
            "好不好", "陪我", "不理我", "你都不", "坏", "就你不知道",
        ]),
        FeelingRule(id: "chilly", label: "冷淡·在退开", keywords: [
            "随便", "没事", "不用了", "算了", "还行", "嗯嗯", "知道了",
        ]),
        FeelingRule(id: "flirty", label: "暧昧·在试探", keywords: [
            "想你", "想见你", "梦到", "要不要", "什么时候", "突然想到", "你猜",
            "还没睡", "还不睡", "没睡", "这么晚", "两点",
        ]),
        FeelingRule(id: "sick", label: "身体不舒服", keywords: [
            "感冒", "发烧", "低烧", "不舒服", "嗓子", "咳嗽", "拉肚子", "吃药",
            "医院", "体温",
        ]),
        FeelingRule(id: "hungry", label: "饿·想吃东西", keywords: [
            "饿", "饿死", "想吃", "外卖", "火锅", "奶茶", "馋", "夜宵",
        ]),
    ]

    static func analyze(_ messages: [ChatMessage]) -> ConversationAnalysis {
        let theirs = messages.filter { $0.speaker == .ta }
        let last = theirs.last?.text ?? ""
        let recentMessages = Array(theirs.suffix(3))
        let window = recentMessages.map(\.text).joined(separator: " ")

        // The last message matters most, but people often close with a short
        // line ("不说了，我先睡") right after saying the real thing one message
        // earlier, so the two before it still carry weight.
        var scores: [String: Double] = [:]
        for (offset, message) in recentMessages.enumerated() {
            let distance = recentMessages.count - 1 - offset
            let factor: Double = distance == 0 ? 1 : 0.6
            for rule in feelings {
                for keyword in rule.keywords
                where message.text.localizedCaseInsensitiveContains(keyword) {
                    scores[rule.id, default: 0] += (keyword.count >= 2 ? 3 : 1.5) * factor
                }
            }
        }

        // Structure says as much as vocabulary does. These look at the recent
        // window as a whole, not just the final line.
        let shortReplies = recentMessages.filter { $0.text.count <= 4 }.count
        if shortReplies >= 2 { scores["chilly", default: 0] += 3 }
        if containsAny(window, ["算了", "没事", "随便", "不用了"]) {
            scores["chilly", default: 0] += 2
            scores["upset", default: 0] += 1
        }
        if containsAny(window, blameMarkers) {
            scores["upset", default: 0] += 4.5
        }
        if containsAny(window, ["不理我", "不理你了", "你都不"]) {
            scores["cute", default: 0] += 3
        }
        if containsAny(window, ["睡不着", "失眠", "还没睡", "还不睡", "这个点", "这么晚"]) {
            scores["anxious", default: 0] += 2.5
            scores["flirty", default: 0] += 1.5
        }
        if last.contains("！") || last.contains("!") {
            scores["happy", default: 0] += 1.5
            scores["upset", default: 0] += 1
        }
        if containsAny(last, ["哈哈", "hhh", "233"]) { scores["happy", default: 0] += 2.5 }

        let ranked = scores
            .map { FeelingScore(id: $0.key, label: label(for: $0.key), score: $0.value) }
            .sorted { $0.score > $1.score }
        let best = ranked.first
        let enoughEvidence = (best?.score ?? 0) >= 3
        let primaryID = enoughEvidence ? (best?.id ?? "neutral") : "neutral"
        let primaryLabel = enoughEvidence ? (best?.label ?? "没有明显情绪") : "没有明显情绪"
        let strategy = ReplyStrategy.all[primaryID] ?? ReplyStrategy.neutral

        let keyword = extractKeyword(from: recentMessages.reversed().map(\.text))
        let intentLabel = detectIntent(
            last: last,
            window: window,
            messageCount: theirs.count,
            primary: primaryID
        )
        let signals = buildSignals(
            theirs: theirs,
            last: last,
            recent: recentMessages.map(\.text),
            all: messages,
            keyword: keyword
        )

        return ConversationAnalysis(
            messages: messages,
            lastFromThem: last,
            quote: quote(from: preferredQuoteSource(theirs)),
            keyword: keyword,
            feelings: ranked,
            primaryFeeling: primaryID,
            feelingLabel: primaryLabel,
            intentLabel: intentLabel,
            headline: "\(primaryLabel) · \(intentLabel)",
            signals: signals,
            strategy: strategy,
            toneNote: toneNote(for: primaryID)
        )
    }

    // MARK: - Pieces

    static func label(for feelingID: String) -> String {
        feelings.first { $0.id == feelingID }?.label ?? "没有明显情绪"
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.localizedCaseInsensitiveContains($0) }
    }

    /// Phrases that mean "you did something to me" rather than "I had a bad day".
    /// Kept narrow on purpose: 「你怎么」 alone usually is not an accusation.
    static let blameMarkers = [
        "你昨天", "你不是说", "你说好的", "你答应", "你忘了", "你到底",
        "你怎么能", "你就是不",
    ]

    private static func toneNote(for feelingID: String) -> String {
        switch feelingID {
        case "tired", "upset", "sad", "anxious", "chilly", "sick":
            return "TA 情绪不高：句子越短越好，先接情绪，别再抛新话题。"
        case "happy":
            return "TA 心情好：可以放大情绪、开玩笑，也可以顺势推进一件事。"
        case "flirty":
            return "TA 在给你留口子：可以往前一格，但别一次走三步。"
        case "bored", "cute":
            return "TA 在等你接：给具体的回应，别用「嗯」「在」把话堵回去。"
        default:
            return "没有明显情绪：抓住一个细节提问，比寒暄管用。"
        }
    }

    private static func detectIntent(
        last: String,
        window: String,
        messageCount: Int,
        primary: String
    ) -> String {
        // 撒娇 also sounds like a complaint, but it wants attention, not repair.
        if primary == "cute" {
            return "想要你的注意"
        }
        if containsAny(window, blameMarkers) {
            return "在表达对你的不满"
        }
        if containsAny(last, ["怎么办", "要不要", "该不该", "你说我", "帮我看看"]) {
            return "在问你怎么办"
        }
        if containsAny(last, ["？", "?"]) {
            return "在等你回答"
        }
        switch primary {
        case "flirty": return "在试探你的态度"
        case "happy": return "想跟你分享"
        case "bored", "cute": return "想要你的注意"
        case "chilly": return "有点想退开"
        case "tired", "upset", "sad", "anxious", "sick": return "想被接住情绪"
        default:
            return messageCount > 1 ? "在讲一件事" : "在跟你说话"
        }
    }

    private static func buildSignals(
        theirs: [ChatMessage],
        last: String,
        recent: [String],
        all: [ChatMessage],
        keyword: String
    ) -> [AnalysisSignal] {
        var signals: [AnalysisSignal] = []

        if containsAny(last, ["？", "?"]) {
            signals.append(AnalysisSignal(
                title: "最后一句是问句",
                detail: "必须正面回答，绕过去会显得在躲。"
            ))
        }
        let trailingRuns = Array(all.reversed().prefix { $0.speaker == .ta }).count
        if trailingRuns >= 2 {
            signals.append(AnalysisSignal(
                title: "TA 连发了 \(trailingRuns) 条",
                detail: "TA 在等回应，先回一句，别让 TA 悬着。"
            ))
        }
        if recent.count >= 2 {
            let average = Double(recent.map(\.count).reduce(0, +)) / Double(recent.count)
            if average <= 4 {
                signals.append(AnalysisSignal(
                    title: "回复在变短",
                    detail: "TA 收着说，这时候连环追问是大忌。"
                ))
            }
        }
        if let hit = ["算了", "没事", "随便", "不用了"].first(where: { last.contains($0) }) {
            signals.append(AnalysisSignal(
                title: "出现了「\(hit)」",
                detail: "通常是反话，别照字面接。"
            ))
        }
        if containsAny(last, ["睡不着", "失眠", "还没睡", "这个点", "半夜"]) {
            signals.append(AnalysisSignal(
                title: "深夜信号",
                detail: "这个时间点的情绪会被放大，别说教。"
            ))
        }
        if !keyword.isEmpty {
            signals.append(AnalysisSignal(
                title: "抓住了具体的事：「\(keyword)」",
                detail: "回复里带上它，TA 会觉得你真的看了。"
            ))
        }
        return Array(signals.prefix(4))
    }

    /// Looks at the most recent messages first, so a closing line that mentions
    /// nothing still lets an earlier detail be quoted back.
    private static func extractKeyword(from messages: [String]) -> String {
        for text in messages {
            for topic in ReplyStrategy.topics {
                guard let range = text.range(of: topic) else { continue }
                // Extend into a natural phrase only when the next characters
                // keep it readable: 「加班到十点」 yes, 「甲方下午改」 no — half a
                // sentence reads worse than the bare topic.
                let after = text[range.upperBound...]
                let tail = String(after.prefix(while: { !"，。！？!?…、".contains($0) }))
                guard let first = tail.first, "到了的得好完成太".contains(first) else {
                    return topic
                }
                return topic + String(tail.prefix(5))
            }
        }
        return ""
    }

    /// People often end with a throwaway line ("不说了，我先睡"). Quoting that
    /// back sounds like nobody was listening, so a very short closer borrows the
    /// previous message instead.
    private static func preferredQuoteSource(_ theirs: [ChatMessage]) -> String {
        guard let last = theirs.last else { return "" }
        guard theirs.count >= 2 else { return last.text }
        let previous = theirs[theirs.count - 2].text
        let isClosingLine = last.text.count < 6
            || closingPatterns.contains { last.text.contains($0) }
        guard isClosingLine, previous.count > last.text.count else { return last.text }
        return previous
    }

    /// Ways people sign off right after saying the real thing.
    private static let closingPatterns = [
        "不说了", "不聊了", "先睡", "我睡了", "晚安", "别管我", "算了",
    ]

    private static func quote(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = trimmed.first, !first.isLetter && !first.isNumber {
            trimmed.removeFirst()
        }
        guard trimmed.count > 14 else { return trimmed }
        return String(trimmed.prefix(14)) + "…"
    }
}
