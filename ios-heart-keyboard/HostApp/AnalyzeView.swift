import PhotosUI
import SwiftUI
import UIKit

/// 识别聊天内容 → 高情商回复.
///
/// This screen is where the reading happens, because a keyboard extension cannot
/// see another app's screen. Pick a screenshot of the chat, or paste the text,
/// and the result is handed to the keyboard through the App Group.
struct AnalyzeView: View {

    @StateObject private var model = AnalyzeModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var pasted = ""
    @State private var useLocalOnly = false
    @State private var showAdvanced = false
    @AppStorage("hk.cloud.endpoint") private var cloudEndpoint = ""
    @AppStorage("hk.cloud.model") private var cloudModel = ""
    @AppStorage("hk.cloud.key") private var cloudKey = ""

    var body: some View {
        NavigationStack {
            List {
                sourceSection
                if model.isWorking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(model.status ?? "正在读这段对话…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = model.errorText {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                if let analysis = model.analysis, let composition = model.composition {
                    readingSection(analysis)
                    strategySection(analysis)
                    repliesSection(composition)
                    avoidSection(composition)
                    syncSection
                }
                advancedSection
            }
            .navigationTitle("识别聊天内容")
        }
    }

    // MARK: - Input

    private var sourceSection: some View {
        Section {
            PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                Label("选一张聊天截图", systemImage: "photo.on.rectangle.angled")
            }
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        model.report(error: "这张图读不出来，换一张试试。")
                        return
                    }
                    await model.analyze(
                        imageData: data,
                        localOnly: useLocalOnly,
                        cloud: cloudProvider
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("或者直接粘贴聊天记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pasted)
                    .frame(minHeight: 92)
                    .font(.footnote)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.08))
                    )
                Button {
                    Task {
                        await model.analyze(
                            text: pasted,
                            localOnly: useLocalOnly,
                            cloud: cloudProvider
                        )
                    }
                } label: {
                    Label("识别这段聊天", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.30, blue: 0.47))
                .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)

            Button("用一段示例对话试试") {
                pasted = SampleTranscripts.tired
                Task {
                    await model.analyze(text: pasted, localOnly: useLocalOnly, cloud: cloudProvider)
                }
            }
            .font(.footnote)
        } header: {
            Text("这段话是谁说的，我在这个页面读")
        } footer: {
            Text("截图请先裁到气泡区域，只留对话本身，识别会更准。")
        }
    }

    // MARK: - Results

    private func readingSection(_ analysis: ConversationAnalysis) -> some View {
        Section("我读到的") {
            HStack {
                Text(analysis.headline)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("左右反了") { Task { await model.flipRoles(localOnly: useLocalOnly, cloud: cloudProvider) } }
                    .font(.caption)
            }
            if !analysis.feelings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(analysis.feelings.prefix(4).enumerated()), id: \.offset) { index, feeling in
                            Text(feeling.label)
                                .font(.caption.weight(index == 0 ? .semibold : .regular))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    index == 0
                                        ? Color(red: 1.0, green: 0.89, blue: 0.93)
                                        : Color(.secondarySystemBackground)
                                )
                                .foregroundStyle(
                                    index == 0
                                        ? Color(red: 0.88, green: 0.11, blue: 0.32)
                                        : Color.secondary
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            ForEach(Array(analysis.signals.enumerated()), id: \.offset) { _, signal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.footnote.weight(.medium))
                    Text(signal.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func strategySection(_ analysis: ConversationAnalysis) -> some View {
        Section("回复策略") {
            Text(analysis.strategy.move)
                .font(.subheadline)
            ForEach(Array(analysis.strategy.tips.enumerated()), id: \.offset) { _, tip in
                Label(tip, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(analysis.toneNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func repliesSection(_ composition: Composition) -> some View {
        Section("可以直接发的三句") {
            ForEach(Array(composition.replies.enumerated()), id: \.offset) { _, reply in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(reply.level)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(red: 1.0, green: 0.30, blue: 0.47))
                            .clipShape(Capsule())
                        Text(reply.why)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(reply.text)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = reply.text
                        model.status = "已复制，回聊天里粘贴就行"
                    } label: {
                        Label("复制这句", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func avoidSection(_ composition: Composition) -> some View {
        Section("别这样说") {
            ForEach(Array(composition.counterexamples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    Text(example.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var syncSection: some View {
        Section {
            Label(
                model.syncedAt == nil
                    ? "还没有同步"
                    : "已同步到键盘，切到心跳键盘就能看到这三句",
                systemImage: model.syncedAt == nil ? "arrow.up.circle" : "checkmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if !SharedStore.isGroupAvailable {
                Text("App Group 还没配置：键盘读不到这里的结果。按 README 里的三步在两个 target 都加上 \(SharedStore.appGroupID) 就好。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("生成方式：\(model.providerName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("给键盘")
        }
    }

    private var advancedSection: some View {
        Section {
            Toggle("只用本地引擎（不联网）", isOn: $useLocalOnly)
                .font(.subheadline)
            DisclosureGroup("接上你自己的模型（可选）", isExpanded: $showAdvanced) {
                TextField("https://…/v1/chat/completions", text: $cloudEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)
                TextField("模型名，例如 gpt-4o-mini", text: $cloudModel)
                    .autocorrectionDisabled()
                    .font(.caption)
                SecureField("API Key（只存在这台设备上）", text: $cloudKey)
                    .font(.caption)
                Text("正式产品不要把 key 放进 App：让 App 调你自己的后端。这段配置只用于本地试用。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } header: {
            Text("生成方式")
        } footer: {
            Text("默认优先用本机 Apple Intelligence（iOS 26 且设备支持），其次是你填的云端模型，最后是本地策略引擎——三层都会给出结果，只是措辞精细度不同。")
        }
    }

    private var cloudProvider: CloudReplyProvider? {
        guard
            let url = URL(string: cloudEndpoint.trimmingCharacters(in: .whitespaces)),
            !cloudModel.trimmingCharacters(in: .whitespaces).isEmpty,
            !cloudKey.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return CloudReplyProvider(
            endpoint: url,
            apiKey: cloudKey.trimmingCharacters(in: .whitespaces),
            model: cloudModel.trimmingCharacters(in: .whitespaces)
        )
    }
}

/// A couple of conversations that show what each emotional state looks like.
enum SampleTranscripts {
    static let tired = """
        TA：今天又加班到十点，累死了
        我：怎么又加班
        TA：甲方下午改了三版，全都要重做
        TA：不说了，我先睡
        """
    static let distant = """
        我：晚上一起吃饭吗
        TA：嗯
        我：你怎么了
        TA：没事
        TA：随便吧
        """
    static let clingy = """
        TA：都两点多了，你怎么还不睡
        我：刚忙完
        TA：那你都不理我，哼
        """
}

final class AnalyzeModel: ObservableObject {

    @Published var analysis: ConversationAnalysis?
    @Published var composition: Composition?
    @Published var providerName = "—"
    @Published var status: String?
    @Published var errorText: String?
    @Published var isWorking = false
    @Published var syncedAt: Date?

    private var rawMessages: [ChatMessage] = []
    private var source = ""

    func report(error: String) {
        errorText = error
        isWorking = false
    }

    func analyze(imageData: Data, localOnly: Bool, cloud: CloudReplyProvider?) async {
        isWorking = true
        errorText = nil
        status = "正在识别截图里的对话…"
        do {
            let messages = try await ChatOCR.messages(from: imageData)
            guard !messages.isEmpty else {
                report(error: "截图里没读到对话。裁到气泡区域再试一次。")
                return
            }
            await run(messages: messages, source: "聊天截图", localOnly: localOnly, cloud: cloud)
        } catch {
            report(error: "识别失败：\(error.localizedDescription)")
        }
    }

    func analyze(text: String, localOnly: Bool, cloud: CloudReplyProvider?) async {
        let messages = ChatTranscript.parse(text)
        guard !messages.isEmpty else {
            report(error: "这段文字里没读到消息。")
            return
        }
        await run(messages: messages, source: "粘贴的聊天记录", localOnly: localOnly, cloud: cloud)
    }

    func flipRoles(localOnly: Bool, cloud: CloudReplyProvider?) async {
        guard !rawMessages.isEmpty else { return }
        await run(
            messages: ChatTranscript.flipped(rawMessages),
            source: source,
            localOnly: localOnly,
            cloud: cloud
        )
    }

    private func run(
        messages: [ChatMessage],
        source: String,
        localOnly: Bool,
        cloud: CloudReplyProvider?
    ) async {
        isWorking = true
        errorText = nil
        status = "正在读这段对话…"
        rawMessages = messages
        self.source = source

        let analysis = ChatAnalyzer.analyze(messages)
        let engine = ReplyEngine()
        let provider: ReplyProvider = localOnly
            ? RuleBasedProvider()
            : ReplyProviders.best(cloud: cloud)
        status = "正在生成回复（\(provider.name)）…"
        let composition = await provider.compose(
            for: analysis,
            toneID: engine.toneID,
            personaID: engine.personaID
        )

        self.analysis = analysis
        self.composition = composition
        providerName = provider.name
        SharedStore.save(
            SharedAnalysis(analysis: analysis, composition: composition, source: source)
        )
        syncedAt = Date()
        status = nil
        isWorking = false
    }
}
