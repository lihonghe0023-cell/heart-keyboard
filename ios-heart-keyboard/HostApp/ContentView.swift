import SwiftUI

/// The host app. Apple requires a keyboard extension to ship inside a real app,
/// so this app does two jobs: it walks the user through enabling the keyboard,
/// and it lets them try the reply engine before switching keyboards.
struct ContentView: View {

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("开启键盘", systemImage: "keyboard") }
            AnalyzeView()
                .tabItem { Label("识别聊天", systemImage: "text.magnifyingglass") }
            TryItView()
                .tabItem { Label("试一试", systemImage: "heart.text.square") }
        }
        .tint(Color(red: 1.0, green: 0.30, blue: 0.47))
    }
}

private struct SetupView: View {

    private let steps = [
        "打开「设置」→「通用」→「键盘」→「键盘」",
        "点「添加新键盘」，在第三方键盘里选「心跳键盘」",
        "在任意聊天界面长按地球键 🌐，切到心跳键盘",
        "点键盘上的 💗，可以用通用话术，也可以「识别剪贴板里的聊天」",
        "想让它读懂整段对话：到这个 App 的「识别聊天」里选一张聊天截图，或直接粘贴对话",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心跳键盘")
                            .font(.title2.weight(.semibold))
                        Text("在键盘上直接给你三句能发出去的话：结合 TA 刚说的内容、你想推进的阶段和你想要的语气。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("怎么开启") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .frame(width: 20, height: 20)
                                .background(Color(red: 1.0, green: 0.30, blue: 0.47).opacity(0.15))
                                .clipShape(Circle())
                            Text(step)
                                .font(.subheadline)
                        }
                    }
                }

                Section("关于权限") {
                    Text("心跳键盘不需要「允许完全访问」，也不联网：所有话术都在设备本地。只有你想手动把 TA 的话喂给键盘时（💗 → 用剪贴板里 TA 的话），才需要在设置里打开完全访问。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("心跳键盘")
        }
    }
}

private struct TryItView: View {

    @StateObject private var model = DemoChatModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(model.messages.enumerated()), id: \.offset) { _, message in
                                ChatBubble(message: message)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.messages.count) { _ in
                        withAnimation { proxy.scrollTo(model.messages.count - 1, anchor: .bottom) }
                    }
                }

                header
                suggestionStrip
                composer
            }
            .background(Color(red: 1.0, green: 0.97, blue: 0.98))
            .navigationTitle("试一试")
        }
    }

    private var header: some View {
        HStack {
            Text(model.engine.header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.88, green: 0.11, blue: 0.32))
            Spacer()
            Button("换一批 ↻") { model.reroll() }
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button {
                        model.use(suggestion.text)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let badge = suggestion.badge {
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.88, green: 0.11, blue: 0.32))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 1.0, green: 0.89, blue: 0.93))
                                    .clipShape(Capsule())
                            }
                            Text(suggestion.text)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        .frame(width: 226, alignment: .leading)
                        .padding(10)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(suggestion.isContextAware ? Color(red: 1.0, green: 0.30, blue: 0.47) : Color.black.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("说点什么…", text: $model.draft, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))

            Button {
                model.send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        model.draft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(red: 0.94, green: 0.83, blue: 0.88)
                            : Color(red: 1.0, green: 0.30, blue: 0.47)
                    )
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.99, green: 0.94, blue: 0.96))
    }
}

private struct ChatBubble: View {

    let message: DemoChatModel.Message

    var body: some View {
        HStack {
            if message.from == .me { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.from == .me ? .white : .primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    message.from == .me
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.43, blue: 0.57), Color(red: 1.0, green: 0.25, blue: 0.44)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.white)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.from == .ta { Spacer(minLength: 40) }
        }
    }
}

final class DemoChatModel: ObservableObject {

    enum Author { case me, ta }

    struct Message {
        let from: Author
        let text: String
    }

    let engine = ReplyEngine()

    @Published var messages: [Message]
    @Published var draft = ""
    @Published private(set) var suggestions: [Suggestion] = []

    init() {
        messages = [
            Message(from: .ta, text: "你好呀，刚从群里加的你 👋"),
            Message(from: .ta, text: "你在群里说的那个话剧，好看吗？"),
        ]
        reroll()
    }

    func use(_ text: String) {
        draft = text
    }

    func reroll() {
        let context = messages.last { $0.from == .ta }?.text ?? ""
        suggestions = engine.suggestions(context: context)
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(Message(from: .me, text: text))
        draft = ""
        engine.noteSent(text)
        reroll()

        let reply = engine.partnerReply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.messages.append(Message(from: .ta, text: reply))
            self?.reroll()
        }
    }
}
