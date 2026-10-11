import Foundation

/// One message in a conversation, with the speaker resolved.
struct ChatMessage: Equatable {
    enum Speaker: String {
        case ta
        case me
    }

    let speaker: Speaker
    let text: String
}

/// A line of text found by OCR, with enough geometry to tell whose bubble it was.
struct OCRBubbleLine {
    /// Text of the line.
    let text: String
    /// Horizontal centre as a fraction of the image width, 0...1.
    let centerX: CGFloat
    /// Vertical position as a fraction of the image height, 0...1, measured from the top.
    let centerY: CGFloat
}

/// Turns pasted text or OCR output into a speaker-attributed conversation.
enum ChatTranscript {

    /// Accepts the shapes people actually paste:
    ///
    ///     1. `TA：今天加班到十点` / `我: 辛苦了`
    ///     2. WeChat multi-select copy, where the name sits on its own line
    ///        (optionally with a timestamp on the same line)
    ///     3. A bare run of messages, which are treated as the other person's,
    ///        because that is what pasting "the thing they said" usually means.
    static func parse(_ raw: String) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var rolesByName: [String: ChatMessage.Speaker] = [:]
        var currentName: String?

        // A short line is only a sender name if it shows up more than once
        // (names repeat, short replies like "嗯" usually do not).
        var occurrences: [String: Int] = [:]
        let rawLines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in rawLines {
            occurrences[line, default: 0] += 1
        }

        func role(for name: String) -> ChatMessage.Speaker {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let known = rolesByName[trimmed] { return known }
            if isSelfName(trimmed) {
                rolesByName[trimmed] = .me
                return .me
            }
            // First unknown name in a pasted transcript is the other person.
            let role: ChatMessage.Speaker = rolesByName.isEmpty ? .ta : .me
            rolesByName[trimmed] = role
            return role
        }

        for (index, line) in rawLines.enumerated() {
            if let match = labeled(line, prefixes: ["ta", "TA", "Ta", "对方", "他", "她", "TA说"]) {
                messages.append(ChatMessage(speaker: .ta, text: match))
                continue
            }
            if let match = labeled(line, prefixes: ["我", "me", "Me", "自己", "本人"]) {
                messages.append(ChatMessage(speaker: .me, text: match))
                continue
            }
            // WeChat's "复制" prefix form: `小林同学：你好呀`
            if let (name, body) = namedLine(line), !isSelfName(name) {
                _ = role(for: name)
                messages.append(ChatMessage(speaker: rolesByName[name] ?? .ta, text: body))
                continue
            }
            if let name = nameOnlyLine(line, counts: occurrences, isFirst: index == 0) {
                currentName = name
                continue
            }
            if let name = nameWithTimestamp(line) {
                currentName = name
                continue
            }
            if separatorLine(line) { continue }

            let speaker = currentName.map(role(for:)) ?? .ta
            messages.append(ChatMessage(speaker: speaker, text: line))
        }

        return messages
    }

    static func flipped(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.map {
            ChatMessage(speaker: $0.speaker == .ta ? .me : .ta, text: $0.text)
        }
    }

    /// Lays out OCR lines into messages. Chat apps put the other person on the
    /// left and you on the right, so the horizontal centre decides the speaker.
    static func fromOCR(_ lines: [OCRBubbleLine]) -> [ChatMessage] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.centerY < $1.centerY }
        return sorted.map { line in
            ChatMessage(
                speaker: line.centerX < 0.5 ? .ta : .me,
                text: line.text.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    // MARK: - Line shapes

    private static func labeled(_ line: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            for separator in [": ", ":", "："] {
                let head = prefix + separator
                if line.hasPrefix(head) {
                    let body = String(line.dropFirst(head.count)).trimmingCharacters(in: .whitespaces)
                    return body.isEmpty ? nil : body
                }
            }
        }
        return nil
    }

    private static func isSelfName(_ name: String) -> Bool {
        ["我", "me", "Me", "自己", "本人"].contains(name)
    }

    private static func namedLine(_ line: String) -> (String, String)? {
        guard let separatorIndex = line.firstIndex(where: { $0 == "：" || $0 == ":" }) else {
            return nil
        }
        let name = String(line[line.startIndex..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let body = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 12, !body.isEmpty else { return nil }
        return (name, body)
    }

    private static func nameOnlyLine(_ line: String, counts: [String: Int], isFirst: Bool) -> String? {
        guard line.count <= 12 else { return nil }
        guard !line.contains(where: { "，。！？!?…、".contains($0) }) else { return nil }
        guard !line.contains(where: { $0.isNumber }) else { return nil }
        guard !commonReplies.contains(line) else { return nil }
        guard isFirst || (counts[line] ?? 0) > 1 else { return nil }
        return line
    }

    /// Short replies that would otherwise look like a sender name.
    private static let commonReplies: Set<String> = [
        "嗯", "嗯嗯", "哦", "哦哦", "好", "好的", "行", "对", "是", "是的", "不",
        "啊", "在", "没事", "哈哈", "知道了", "随便",
    ]

    private static func nameWithTimestamp(_ line: String) -> String? {
        let patterns = ["\\d{1,2}:\\d{2}", "昨天", "今天", "星期.", "上午", "下午", "晚上"]
        for pattern in patterns where line.range(of: pattern, options: .regularExpression) != nil {
            let name = line
                .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name.count <= 12 { return name }
        }
        return nil
    }

    private static func separatorLine(_ line: String) -> Bool {
        line.hasPrefix("---") || line.hasPrefix("===")
    }
}
