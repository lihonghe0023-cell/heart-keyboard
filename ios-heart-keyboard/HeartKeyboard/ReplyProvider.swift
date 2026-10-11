import Foundation

/// Turns an analysis into ready-to-send lines.
///
/// The keyboard never calls a model directly: it reads what the app produced
/// through `SharedStore`. Swapping in a better model is therefore a change in
/// one place, and the keyboard stays small and offline.
protocol ReplyProvider {
    var name: String { get }
    func compose(
        for analysis: ConversationAnalysis,
        toneID: String,
        personaID: String
    ) async -> Composition
}

/// The guaranteed floor: offline, instant, and it can explain every line.
struct RuleBasedProvider: ReplyProvider {
    let name = "本地策略引擎"

    func compose(
        for analysis: ConversationAnalysis,
        toneID: String,
        personaID: String
    ) async -> Composition {
        ReplyComposer.compose(analysis, toneID: toneID, personaID: personaID)
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Rewrites the rule-based lines with the on-device model.
///
/// The rules still decide the strategy, the guardrails, the counterexamples and
/// the structure; the model only improves the wording. If anything fails, the
/// caller keeps the rule-based lines — this provider never returns nothing.
@available(iOS 26.0, *)
struct AppleIntelligenceProvider: ReplyProvider {

    let name = "Apple Intelligence（本机模型）"

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
        你是中文恋爱聊天顾问。你的任务是帮用户回复暧昧对象或伴侣，要求「高情商」：
        先接住对方的情绪，不辩论、不说教、不否定对方的感受，再给具体关心或轻推进。
        句子要短、口语化、像真人发的，必须引用对话里的具体细节。
        禁止使用「别想太多」「开心点」「多喝热水」「你要坚强」这类话。
        """

    func compose(
        for analysis: ConversationAnalysis,
        toneID: String,
        personaID: String
    ) async -> Composition {
        let baseline = ReplyComposer.compose(analysis, toneID: toneID, personaID: personaID)
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: Self.prompt(for: analysis, toneID: toneID, personaID: personaID)
            )
            let lines = Self.parse(response.content)
            guard lines.count == 3 else { return baseline }
            var rewritten: [ComposedReply] = []
            for (index, original) in baseline.replies.enumerated() where index < lines.count {
                rewritten.append(ComposedReply(
                    level: original.level,
                    text: lines[index],
                    why: original.why + "（本机模型改写）"
                ))
            }
            return Composition(
                replies: rewritten,
                counterexamples: baseline.counterexamples,
                tips: baseline.tips
            )
        } catch {
            return baseline
        }
    }

    private static func prompt(
        for analysis: ConversationAnalysis,
        toneID: String,
        personaID: String
    ) -> String {
        let transcript = analysis.messages
            .map { ($0.speaker == .ta ? "TA：" : "我：") + $0.text }
            .joined(separator: "\n")
        return """
            对话记录：
            \(transcript)

            我读到的信息：对方情绪是「\(analysis.feelingLabel)」，意图是「\(analysis.intentLabel)」，策略重点是：\(analysis.strategy.move)
            语气要求：\(Lines.tone(toneID).label)
            关系：\(Lines.persona(personaID).name)

            请写 3 条可以直接发出的回复，每条不超过 45 字：
            稳：只接住情绪，不给建议
            暖：接住情绪，再加一件具体的关心
            进：接住情绪，再轻推一格（约见面或把话题往前带），但不能越界

            严格按下面格式输出三行，不要任何其他文字：
            稳：……
            暖：……
            进：……
            """
    }

    private static func parse(_ text: String) -> [String] {
        let markers = ["稳：", "暖：", "进："]
        var found: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            for marker in markers where line.hasPrefix(marker) {
                let body = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { found[marker] = body }
            }
        }
        return markers.compactMap { found[$0] }
    }
}
#endif

/// Optional: bring your own model.
///
/// Works with any OpenAI-compatible `/chat/completions` endpoint. Call it from
/// the app, not from the keyboard: an extension needs Full Access to open a
/// socket, and no API key should live inside a keyboard.
struct CloudReplyProvider: ReplyProvider {

    let name = "云端模型"
    let endpoint: URL
    let apiKey: String
    let model: String

    func compose(
        for analysis: ConversationAnalysis,
        toneID: String,
        personaID: String
    ) async -> Composition {
        let baseline = ReplyComposer.compose(analysis, toneID: toneID, personaID: personaID)
        do {
            let transcript = analysis.messages
                .map { ($0.speaker == .ta ? "TA：" : "我：") + $0.text }
                .joined(separator: "\n")
            let system = """
                你是中文恋爱聊天顾问，帮用户回复暧昧对象或伴侣。要求高情商：先接住情绪，\
                不辩论、不说教、不否定对方感受，再给具体关心或轻推进。句子短、口语化、\
                引用对话里的具体细节。禁止「别想太多」「开心点」「多喝热水」这类话。
                """
            let user = """
                对话记录：
                \(transcript)

                情绪：\(analysis.feelingLabel)；意图：\(analysis.intentLabel)；策略：\(analysis.strategy.move)
                语气：\(Lines.tone(toneID).label)；关系：\(Lines.persona(personaID).name)

                输出三行，格式严格如下，不要其他文字：
                稳：…（只接情绪）
                暖：…（接情绪 + 具体关心）
                进：…（接情绪 + 轻推进）
                """

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "temperature": 0.8,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = root["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                return baseline
            }

            let lines = Self.parse(content)
            guard lines.count == 3 else { return baseline }
            var rewritten: [ComposedReply] = []
            for (index, original) in baseline.replies.enumerated() where index < lines.count {
                rewritten.append(ComposedReply(
                    level: original.level,
                    text: lines[index],
                    why: original.why + "（云端模型改写）"
                ))
            }
            return Composition(
                replies: rewritten,
                counterexamples: baseline.counterexamples,
                tips: baseline.tips
            )
        } catch {
            return baseline
        }
    }

    private static func parse(_ text: String) -> [String] {
        let markers = ["稳：", "暖：", "进："]
        var found: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            for marker in markers where line.hasPrefix(marker) {
                let body = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { found[marker] = body }
            }
        }
        return markers.compactMap { found[$0] }
    }
}

/// Picks the best provider that is actually available right now.
enum ReplyProviders {

    static func best(cloud: CloudReplyProvider? = nil) -> ReplyProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceProvider.isAvailable {
            return AppleIntelligenceProvider()
        }
        #endif
        if let cloud { return cloud }
        return RuleBasedProvider()
    }
}
