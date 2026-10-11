import Foundation
import ImageIO
import Vision

/// Reads the conversation out of a screenshot, on device, with no network.
///
/// This is what makes「识别聊天内容」possible on iOS: a keyboard extension cannot
/// see another app's screen, but the app can read a screenshot the user picked.
///
/// It takes `Data` and returns plain value types, so it stays concurrency-safe
/// under Swift 6 strict checking as well as Swift 5.
enum ChatOCR {

    enum OCRError: Error {
        case badImage
    }

    /// Text lines with their positions, so the caller can tell whose bubble is whose.
    static func lines(in imageData: Data) async throws -> [OCRBubbleLine] {
        try await Task.detached(priority: .userInitiated) { () -> [OCRBubbleLine] in
            guard
                let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw OCRError.badImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            return observations.compactMap { observation -> OCRBubbleLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return OCRBubbleLine(
                    text: candidate.string,
                    centerX: box.midX,
                    // Vision measures from the bottom left; a screenshot reads top down.
                    centerY: 1 - box.midY
                )
            }
        }.value
    }

    /// OCR output, cleaned into a conversation the analyzer can read.
    ///
    /// Tip: crop the screenshot to the bubbles first — a full screen also
    /// contains the clock, the tab bar and the keyboard.
    static func messages(from imageData: Data) async throws -> [ChatMessage] {
        let raw = try await lines(in: imageData)
        let cleaned = raw.filter { !isChrome($0.text) }
        return ChatTranscript.fromOCR(cleaned)
    }

    /// Status bar, timestamps, buttons: text that is on screen but not spoken.
    private static func isChrome(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 1 { return true }
        if trimmed.range(of: "^\\d{1,2}:\\d{2}$", options: .regularExpression) != nil { return true }
        if trimmed.contains("上午") || trimmed.contains("下午") { return true }
        if ["昨天", "今天", "星期", "微信", "取消", "发送", "语音", "表情"].contains(trimmed) {
            return true
        }
        // Needs at least one letter or CJK character to be a message.
        return !trimmed.contains { $0.isLetter }
    }
}
