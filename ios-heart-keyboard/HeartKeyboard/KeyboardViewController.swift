import UIKit

/// 心跳键盘 — a keyboard that suggests replies for dating and relationship chats.
///
/// Layout, top to bottom:
///   1. a header naming the active tone and scene,
///   2. a horizontally scrolling strip of ready-to-send lines,
///   3. a QWERTY (or number) keypad whose pink heart key opens the 话术库 menu.
///
/// No network, no analytics, no full access required.
final class KeyboardViewController: UIInputViewController {

    private enum Metrics {
        static let keyHeight: CGFloat = 40
        static let keySpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 8
        static let suggestionHeight: CGFloat = 74
        static let headerHeight: CGFloat = 24
        static let verticalPadding: CGFloat = 6
        static var keypadHeight: CGFloat { keyHeight * 4 + rowSpacing * 3 }
        static var totalHeight: CGFloat {
            verticalPadding * 2 + headerHeight + suggestionHeight + rowSpacing + keypadHeight
        }
    }

    private let engine = ReplyEngine()
    private let t9 = T9Engine()
    private var suggestions: [Suggestion] = []
    private var chainWords: [String] = []
    private var isPunctuationShowing = false

    private enum LayoutMode {
        case nineKey
        case qwerty
    }

    private enum StripMode {
        case candidates
        case punctuation
        case chain
        case analysis
        case library
    }

    private var layoutMode: LayoutMode = .nineKey
    private var stripMode: StripMode = .library
    /// Set when the app (or this keyboard) has read a real conversation.
    private var shared: SharedAnalysis?
    private var isNumeric = false
    private var isShifted = false
    private var contextOverride = ""
    private var deleteHoldTimer: Timer?
    private var deleteRepeatTimer: Timer?

    private let headerLabel = UILabel()
    private let rerollButton = UIButton(type: .system)
    private let layoutToggle = UIButton(type: .system)
    private let keypadStack = UIStackView()
    private weak var heartButton: KeyButton?
    private let suggestionStrip: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 226, height: Metrics.suggestionHeight - 12)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.showsHorizontalScrollIndicator = false
        view.backgroundColor = .clear
        view.register(SuggestionCell.self, forCellWithReuseIdentifier: SuggestionCell.reuseID)
        view.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseID)
        return view
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViews()
        refreshSuggestions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSuggestions()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Re-reads whatever the host app exposes around the cursor so the strip
        // can answer the current message instead of falling back to a guess.
        refreshSuggestions()
    }

    // MARK: - Setup

    private func setUpViews() {
        view.backgroundColor = KeyboardPalette.background

        headerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = KeyboardPalette.pinkDeep
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var configuration = UIButton.Configuration.plain()
        configuration.title = "换一批 ↻"
        configuration.baseForegroundColor = KeyboardPalette.pinkDeep
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 11)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 12, weight: .medium)
            return outgoing
        }
        rerollButton.configuration = configuration
        rerollButton.backgroundColor = KeyboardPalette.card
        rerollButton.layer.cornerRadius = 12
        rerollButton.layer.borderWidth = 1
        rerollButton.layer.borderColor = KeyboardPalette.hairline.cgColor
        rerollButton.translatesAutoresizingMaskIntoConstraints = false
        rerollButton.addTarget(self, action: #selector(rerollTapped), for: .touchUpInside)

        // 九宫格 and 26 键 are two habits, not two apps: the switch sits in the
        // header so neither layout loses a key to it.
        var toggleConfiguration = UIButton.Configuration.plain()
        toggleConfiguration.title = "26键"
        toggleConfiguration.baseForegroundColor = .secondaryLabel
        toggleConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)
        toggleConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 11.5, weight: .medium)
            return outgoing
        }
        layoutToggle.configuration = toggleConfiguration
        layoutToggle.translatesAutoresizingMaskIntoConstraints = false
        layoutToggle.addTarget(self, action: #selector(layoutToggleTapped), for: .touchUpInside)

        suggestionStrip.translatesAutoresizingMaskIntoConstraints = false
        suggestionStrip.dataSource = self
        suggestionStrip.delegate = self

        keypadStack.axis = .vertical
        keypadStack.spacing = Metrics.rowSpacing
        keypadStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerLabel)
        view.addSubview(layoutToggle)
        view.addSubview(rerollButton)
        view.addSubview(suggestionStrip)
        view.addSubview(keypadStack)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: Metrics.totalHeight),

            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Metrics.verticalPadding),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerLabel.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            rerollButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            rerollButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            rerollButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: headerLabel.trailingAnchor,
                constant: 8
            ),

            layoutToggle.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            layoutToggle.trailingAnchor.constraint(equalTo: rerollButton.leadingAnchor, constant: -6),

            suggestionStrip.topAnchor.constraint(equalTo: headerLabel.bottomAnchor),
            suggestionStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionStrip.heightAnchor.constraint(equalToConstant: Metrics.suggestionHeight),

            keypadStack.topAnchor.constraint(
                equalTo: suggestionStrip.bottomAnchor,
                constant: Metrics.rowSpacing
            ),
            keypadStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            keypadStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            keypadStack.heightAnchor.constraint(equalToConstant: Metrics.keypadHeight),
        ])

        rebuildKeypad()
    }

    // MARK: - Keypad layout

    private var letterRows: [[KeySpec]] {
        let letters = isShifted
            ? [["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
               ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
               ["Z", "X", "C", "V", "B", "N", "M"]]
            : [["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
               ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
               ["z", "x", "c", "v", "b", "n", "m"]]

        var rows: [[KeySpec]] = []
        rows.append(letters[0].map { KeySpec(title: $0, action: .character($0), weight: 1) })
        rows.append(letters[1].map { KeySpec(title: $0, action: .character($0), weight: 1) })

        var third: [KeySpec] = [KeySpec(title: "⇧", action: .shift, weight: 1.5)]
        third += letters[2].map { KeySpec(title: $0, action: .character($0), weight: 1) }
        third.append(KeySpec(title: "⌫", action: .backspace, weight: 1.5))
        rows.append(third)
        rows.append(bottomRow(leading: "123", leadingAction: .numbers))
        return rows
    }

    private var numericRows: [[KeySpec]] {
        var rows: [[KeySpec]] = []
        rows.append("1234567890".map {
            KeySpec(title: String($0), action: .character(String($0)), weight: 1)
        })
        rows.append(["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""].map {
            KeySpec(title: $0, action: .character($0), weight: 1)
        })

        var third: [KeySpec] = [KeySpec(title: "ABC", action: .letters, weight: 1.5)]
        third += ["。", "，", "、", "？", "！", "~", "…"].map {
            KeySpec(title: $0, action: .character($0), weight: 1)
        }
        third.append(KeySpec(title: "⌫", action: .backspace, weight: 1.5))
        rows.append(third)
        rows.append(bottomRow(leading: "ABC", leadingAction: .letters))
        return rows
    }

    private func bottomRow(leading: String, leadingAction: KeyAction) -> [KeySpec] {
        var row: [KeySpec] = [KeySpec(title: leading, action: leadingAction, weight: 1.3)]
        if needsInputModeSwitchKey {
            row.append(KeySpec(title: "🌐", action: .nextKeyboard, weight: 1))
        }
        row.append(KeySpec(title: "💗", action: .heart, weight: 1.1))
        row.append(KeySpec(title: "空格", action: .space, weight: 4.2))
        row.append(KeySpec(title: "换行", action: .newline, weight: 1.7))
        return row
    }

    /// The 九宫格 people actually type Chinese on: digits with the Latin letters
    /// underneath, 符号 on the left, 空格 in the middle so it can also 分词.
    private var nineKeyRows: [[KeySpec]] {
        var rows: [[KeySpec]] = []
        for start in stride(from: 2, through: 8, by: 3) {
            rows.append((start...(start + 2)).map { digit in
                KeySpec(title: String(digit), action: .digit(String(digit)), weight: 1)
            })
        }
        rows.append([
            KeySpec(title: "符号", action: .punctuation, weight: 1),
            KeySpec(title: "💗", action: .heart, weight: 1),
            KeySpec(title: "空格", action: .space, weight: 2.6),
            KeySpec(title: "⌫", action: .backspace, weight: 1),
        ])
        return rows
    }

    private func rebuildKeypad() {
        keypadStack.arrangedSubviews.forEach {
            keypadStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let rows: [[KeySpec]]
        switch layoutMode {
        case .nineKey:
            rows = nineKeyRows
        case .qwerty:
            rows = isNumeric ? numericRows : letterRows
        }
        for (index, specs) in rows.enumerated() {
            let inset = layoutMode == .nineKey ? 0 : rowInset(for: index)
            keypadStack.addArrangedSubview(makeRow(specs, inset: inset))
        }
    }

    /// Rows 2 and 3 are inset the way iOS is, so the keys read as a keypad.
    private func rowInset(for index: Int) -> CGFloat {
        switch index {
        case 1: return 16
        case 2: return 30
        default: return 0
        }
    }

    private func makeRow(_ specs: [KeySpec], inset: CGFloat = 0) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Metrics.keySpacing
        row.distribution = .fill
        row.isLayoutMarginsRelativeArrangement = inset > 0
        row.layoutMargins = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)

        var buttons: [KeyButton] = []
        for spec in specs {
            let button = makeKey(spec)
            row.addArrangedSubview(button)
            buttons.append(button)
        }
        guard let first = buttons.first else { return row }

        first.heightAnchor.constraint(equalToConstant: Metrics.keyHeight).isActive = true
        for (index, button) in buttons.enumerated() where index > 0 {
            button.heightAnchor.constraint(equalToConstant: Metrics.keyHeight).isActive = true
            button.widthAnchor.constraint(
                equalTo: first.widthAnchor,
                multiplier: specs[index].weight / specs[0].weight
            ).isActive = true
        }
        return row
    }

    private func makeKey(_ spec: KeySpec) -> KeyButton {
        let button = KeyButton()
        button.action = spec.action
        if case .digit(let digit) = spec.action {
            button.applyNineKey(digit: digit, letters: NineKeyMap.letters[digit])
            // 长按上屏数字, the way every Chinese 九宫格 does it.
            let press = UILongPressGestureRecognizer(
                target: self,
                action: #selector(digitHeld(_:))
            )
            press.minimumPressDuration = 0.35
            press.cancelsTouchesInView = true
            button.addGestureRecognizer(press)
        } else {
            button.setTitle(spec.title, for: .normal)
            button.accessibilityLabel = spec.title
            button.apply(brand: KeyboardPalette.self)
        }
        button.addTarget(self, action: #selector(keyTouchUpInside(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(keyTouchedDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyCancelled(_:)), for: [.touchUpOutside, .touchCancel])

        switch spec.action {
        case .heart:
            heartButton = button
        case .nextKeyboard:
            button.addGestureRecognizer(
                UILongPressGestureRecognizer(target: self, action: #selector(globeHeld(_:)))
            )
        default:
            break
        }
        return button
    }

    // MARK: - Key handling

    @objc private func keyTouchedDown(_ sender: KeyButton) {
        guard sender.action == .backspace else { return }
        deleteHoldTimer?.invalidate()
        deleteHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.textDocumentProxy.deleteBackward()
            }
            if let timer = self.deleteRepeatTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
        }
        if let timer = deleteHoldTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    @objc private func keyCancelled(_ sender: KeyButton) {
        stopRepeatingDelete()
    }

    @objc private func keyTouchUpInside(_ sender: KeyButton) {
        stopRepeatingDelete()
        guard let action = sender.action else { return }
        perform(action)
    }

    private func stopRepeatingDelete() {
        deleteHoldTimer?.invalidate()
        deleteHoldTimer = nil
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    private func perform(_ action: KeyAction) {
        switch action {
        case .character(let value):
            textDocumentProxy.insertText(value)
            if isShifted {
                isShifted = false
                rebuildKeypad()
            }
        case .digit(let value):
            isPunctuationShowing = false
            t9.append(value)
            refreshSuggestions()
        case .punctuation:
            isPunctuationShowing = true
            refreshSuggestions()
        case .space:
            // 空格 commits the highlighted candidate, the way Chinese keyboards do.
            if commitFirstCandidate() { return }
            if commitFirstChainWord() { return }
            textDocumentProxy.insertText(" ")
        case .newline:
            if commitFirstCandidate() { return }
            textDocumentProxy.insertText("\n")
        case .backspace:
            // 删除先删拼音，再删正文.
            if t9.deleteLast() {
                isPunctuationShowing = false
                refreshSuggestions()
                return
            }
            if !chainWords.isEmpty {
                t9.forgetChain()
                refreshSuggestions()
                return
            }
            textDocumentProxy.deleteBackward()
        case .shift:
            isShifted.toggle()
            rebuildKeypad()
        case .numbers:
            isNumeric = true
            rebuildKeypad()
        case .letters:
            isNumeric = false
            rebuildKeypad()
        case .nextKeyboard:
            advanceToNextInputMode()
        case .heart:
            refreshMenu()
        }
    }

    /// 长按数字键直接上屏数字.
    @objc private func digitHeld(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? KeyButton else { return }
        guard case .digit(let digit) = button.action ?? .space else { return }
        textDocumentProxy.insertText(digit)
    }

    @objc private func layoutToggleTapped() {
        layoutMode = layoutMode == .nineKey ? .qwerty : .nineKey
        isShifted = false
        rebuildKeypad()
        refreshSuggestions()
    }

    @objc private func globeHeld(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view else { return }
        handleInputModeList(from: button, with: gesture)
    }

    // MARK: - Suggestions

    @objc private func rerollTapped() {
        refreshSuggestions()
    }

    /// One strip above the keys, five things it can be. Priority follows what the
    /// user is doing right now:
    ///
    ///   1. 正在打拼音 → 候选字
    ///   2. 刚敲了符号键 → 标点
    ///   3. 有刚识别出来的聊天 → 高情商回复
    ///   4. 刚上屏了一个词 → 尾字联想
    ///   5. 其他 → 通用话术
    private func refreshSuggestions() {
        if let loaded = SharedStore.load(), !isFresh(loaded) {
            SharedStore.clear()
            shared = nil
        }
        chainWords = t9.chainSuggestions(limit: 8)

        let items: [Suggestion]
        let header: String
        if t9.isComposing {
            stripMode = .candidates
            items = t9.candidates(limit: 9).map { candidate in
                Suggestion(
                    text: candidate.word,
                    badge: candidate.source == .exact ? nil : candidate.source.rawValue
                )
            }
            header = "拼音 \(t9.digits)"
        } else if isPunctuationShowing {
            stripMode = .punctuation
            items = NineKeyMap.punctuation.map { Suggestion(text: $0, badge: nil) }
            header = "符号"
        } else if let loaded = SharedStore.load(), isFresh(loaded) {
            shared = loaded
            stripMode = .analysis
            items = loaded.suggestions
            header = "🎯 已识别 · \(loaded.feelingLabel) · \(loaded.intentLabel)"
        } else if !chainWords.isEmpty {
            stripMode = .chain
            items = chainWords.map { Suggestion(text: $0, badge: "联想") }
            header = "联想 · 接着点就行"
        } else {
            shared = nil
            stripMode = .library
            items = engine.suggestions(context: currentContext())
            header = engine.header
        }

        suggestions = items
        headerLabel.text = header
        rerollButton.isHidden = stripMode == .candidates || stripMode == .punctuation
        layoutToggle.isHidden = t9.isComposing
        layoutToggle.configuration?.title = layoutMode == .nineKey ? "26键" : "九宫格"
        if let flow = suggestionStrip.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.sectionInset = UIEdgeInsets(
                top: stripMode == .candidates || stripMode == .punctuation
                    ? (Metrics.suggestionHeight - 44) / 2
                    : 0,
                left: 10,
                bottom: 0,
                right: 10
            )
        }
        suggestionStrip.reloadData()
        suggestionStrip.setContentOffset(.zero, animated: false)
        refreshMenu()
    }

    /// 空格 / 回车 commit the first candidate, like every Chinese keyboard.
    private func commitFirstCandidate() -> Bool {
        guard t9.isComposing, let first = t9.candidates(limit: 1).first else { return false }
        insertCandidate(first.word)
        return true
    }

    private func commitFirstChainWord() -> Bool {
        guard let first = chainWords.first else { return false }
        textDocumentProxy.insertText(first)
        t9.forgetChain()
        refreshSuggestions()
        return true
    }

    private func insertCandidate(_ word: String) {
        textDocumentProxy.insertText(word)
        // Learning happens here: the word is remembered, and so is the choice
        // this exact digit string produced.
        t9.commit(word)
        isPunctuationShowing = false
        refreshSuggestions()
    }

    private func isFresh(_ analysis: SharedAnalysis) -> Bool {
        !analysis.replies.isEmpty
            && Date().timeIntervalSince(analysis.updatedAt) < 3600
    }

    /// Reads whatever the user just copied — the last few messages of the chat —
    /// and analyzes it right here, with no app switch.
    ///
    /// Reading the pasteboard in an extension requires「允许完全访问」.
    private func analyzeClipboard() {
        guard let clipboard = UIPasteboard.general.string, !clipboard.isEmpty else { return }
        let messages = ChatTranscript.parse(clipboard)
        guard !messages.isEmpty else { return }
        let analysis = ChatAnalyzer.analyze(messages)
        let composition = ReplyComposer.compose(
            analysis,
            toneID: engine.toneID,
            personaID: engine.personaID
        )
        let payload = SharedAnalysis(
            analysis: analysis,
            composition: composition,
            source: "剪贴板识别"
        )
        SharedStore.save(payload)
        shared = payload
        refreshSuggestions()
    }

    /// Context prefers a message the user explicitly handed over (paste, via
    /// the 话术库 menu). Otherwise it falls back to whatever text the host app
    /// exposes before the cursor, which for many chat apps is only the draft.
    private func currentContext() -> String {
        if !contextOverride.isEmpty { return contextOverride }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return String(before.suffix(120))
    }

    private func insert(_ text: String) {
        textDocumentProxy.insertText(text)
        engine.noteSent(text)
        refreshSuggestions()
    }

    // MARK: - 话术库 menu

    private func refreshMenu() {
        heartButton?.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu {
        let personas = Lines.personas.map { persona in
            UIAction(
                title: persona.name,
                state: persona.id == engine.personaID ? .on : .off
            ) { [weak self] _ in
                self?.engine.select(persona: persona.id)
                self?.refreshSuggestions()
            }
        }

        let scenes = Lines.scenes.map { scene in
            UIAction(
                title: scene.emoji + " " + scene.label,
                state: scene.id == engine.sceneID ? .on : .off
            ) { [weak self] _ in
                self?.engine.select(scene: scene.id)
                self?.refreshSuggestions()
            }
        }

        let tones = Lines.tones.map { tone in
            UIAction(
                title: tone.emoji + " " + tone.label,
                subtitle: "甜度 \(tone.sweetness)/5 · 油腻风险 \(tone.risk)",
                state: tone.id == engine.toneID ? .on : .off
            ) { [weak self] _ in
                self?.engine.select(tone: tone.id)
                self?.refreshSuggestions()
            }
        }

        let tip = UIAction(title: "💡 " + engine.tip, attributes: .disabled) { _ in }

        // Reading the conversation. The keyboard cannot see other apps' screens,
        // so the two honest paths are the clipboard (here) and a screenshot
        // analyzed in the app (which arrives through SharedStore).
        var brain: [UIMenuElement] = []
        if let shared {
            brain.append(UIAction(
                title: "🎯 \(shared.feelingLabel) · \(shared.intentLabel)",
                subtitle: "来自\(shared.source) · \(shared.move)",
                attributes: .disabled
            ) { _ in })
            if !shared.counterexamples.isEmpty {
                let avoid = shared.counterexamples.prefix(3).map { example in
                    UIAction(
                        title: "「\(example.text)」",
                        subtitle: example.why,
                        attributes: .disabled
                    ) { _ in }
                }
                brain.append(UIMenu(title: "🚫 别这样说", options: .displayInline, children: avoid))
            }
            brain.append(UIAction(title: "↺ 回到通用话术", attributes: .destructive) { [weak self] _ in
                SharedStore.clear()
                self?.shared = nil
                self?.refreshSuggestions()
            })
        }
        brain.append(UIAction(
            title: "🔍 识别剪贴板里的聊天",
            subtitle: "先在聊天里复制几句 TA 的话"
        ) { [weak self] _ in
            self?.analyzeClipboard()
        })

        // Chat apps whose composer hides the conversation still work: hand the
        // keyboard one line to answer.
        let paste = UIAction(title: "📋 只读剪贴板里的一句话") { [weak self] _ in
            guard let self, let clipboard = UIPasteboard.general.string, !clipboard.isEmpty else {
                return
            }
            self.contextOverride = String(clipboard.suffix(120))
            self.refreshSuggestions()
        }

        let reset = UIAction(title: "↺ 清空参考，回到当前对话", attributes: .destructive) { [weak self] _ in
            self?.contextOverride = ""
            self?.refreshSuggestions()
        }

        return UIMenu(title: "心跳话术库", children: [
            UIMenu(title: "读懂这段聊天", options: .displayInline, children: brain),
            UIMenu(title: "打字方式", options: .displayInline, children: [
                UIAction(
                    title: "九宫格",
                    state: layoutMode == .nineKey ? .on : .off
                ) { [weak self] _ in
                    self?.layoutMode = .nineKey
                    self?.rebuildKeypad()
                    self?.refreshSuggestions()
                },
                UIAction(
                    title: "26 键全键盘",
                    state: layoutMode == .qwerty ? .on : .off
                ) { [weak self] _ in
                    self?.layoutMode = .qwerty
                    self?.rebuildKeypad()
                    self?.refreshSuggestions()
                },
                UIAction(
                    title: "模糊音 n↔l / f↔h",
                    subtitle: "南方口音常用，打开后会标「模糊」",
                    state: t9.isFuzzyEnabled ? .on : .off
                ) { [weak self] _ in
                    guard let self else { return }
                    self.t9.setFuzzy(!self.t9.isFuzzyEnabled)
                    self.refreshSuggestions()
                },
                UIAction(
                    title: "清空我学过的词",
                    subtitle: "删掉本地记住的词频和上次选择",
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.t9.resetLearning()
                    self?.refreshSuggestions()
                },
            ]),
            UIMenu(title: "对方是谁", options: .displayInline, children: personas),
            UIMenu(title: "现在想干嘛", options: .displayInline, children: scenes),
            UIMenu(title: "用什么语气说", options: .displayInline, children: tones),
            UIMenu(title: "参考", options: .displayInline, children: [tip, paste, reset]),
        ])
    }
}

// MARK: - Suggestion strip data source

extension KeyboardViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private var isCompactStrip: Bool {
        stripMode == .candidates || stripMode == .punctuation
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        suggestions.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let item = suggestions[indexPath.item]
        if isCompactStrip {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CandidateCell.reuseID,
                for: indexPath
            )
            (cell as? CandidateCell)?.configure(word: item.text, isFirst: indexPath.item == 0)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SuggestionCell.reuseID,
            for: indexPath
        )
        (cell as? SuggestionCell)?.configure(with: item)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard isCompactStrip else {
            return CGSize(width: 226, height: Metrics.suggestionHeight - 12)
        }
        let text = suggestions[indexPath.item].text
        return CGSize(width: max(46, CGFloat(text.count) * 19 + 20), height: 44)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        let item = suggestions[indexPath.item]
        switch stripMode {
        case .candidates:
            insertCandidate(item.text)
        case .punctuation:
            textDocumentProxy.insertText(item.text)
            isPunctuationShowing = false
            refreshSuggestions()
        case .chain:
            textDocumentProxy.insertText(item.text)
            t9.forgetChain()
            refreshSuggestions()
        case .analysis, .library:
            insert(item.text)
        }
    }
}
