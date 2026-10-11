import UIKit

/// Keyboard colours, light and dark.
enum KeyboardPalette {

    static let background = dynamic(light: 0xD3D6DE, dark: 0x2B2B2F)
    static let key = dynamic(light: 0xFFFFFF, dark: 0x6A6A70)
    static let specialKey = dynamic(light: 0xAEB3BF, dark: 0x4A4A50)
    static let pressedKey = dynamic(light: 0xDFE2E8, dark: 0x7C7C84)
    static let pressedSpecial = dynamic(light: 0x9AA0AD, dark: 0x5C5C64)
    static let ink = dynamic(light: 0x1C1C1E, dark: 0xFFFFFF)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x3A3A40)
    static let hairline = dynamic(light: 0xE9E2E6, dark: 0x4A4A50)

    static let pink = UIColor(red: 1.0, green: 0.30, blue: 0.47, alpha: 1)
    static let pinkDeep = UIColor(red: 0.88, green: 0.11, blue: 0.32, alpha: 1)
    static let pinkSoft = UIColor(red: 1.0, green: 0.89, blue: 0.93, alpha: 1)

    private static func dynamic(light: Int, dark: Int) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? hex(dark) : hex(light)
        }
    }

    private static func hex(_ value: Int) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// What a key does when it is released.
enum KeyAction: Equatable {
    case character(String)
    /// 九宫格 key: the digit is the key, the letters below it are the hint.
    case digit(String)
    /// The 符号 key on the 九宫格 bottom row.
    case punctuation
    case shift
    case backspace
    case space
    case newline
    case numbers
    case letters
    case heart
    case nextKeyboard
}

/// One key in a row, plus how wide it should be relative to its neighbours.
struct KeySpec {
    let title: String
    let action: KeyAction
    let weight: CGFloat
}

/// A key that knows its own action, so the controller never has to guess from
/// tags or associated objects.
final class KeyButton: UIButton {

    var action: KeyAction?

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
            backgroundColor = isHighlighted ? pressedColor : restingColor
            transform = isHighlighted ? CGAffineTransform(translationX: 0, y: 1) : .identity
        }
    }

    private var restingColor: UIColor?

    func apply(brand: KeyboardPalette.Type) {
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.7
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        setTitleColor(brand.ink, for: .normal)

        switch action ?? .space {
        case .character, .digit:
            titleLabel?.font = .systemFont(ofSize: 22)
            backgroundColor = brand.key
        case .space, .punctuation:
            titleLabel?.font = .systemFont(ofSize: 14)
            backgroundColor = brand.key
        case .heart:
            titleLabel?.font = .systemFont(ofSize: 17)
            backgroundColor = brand.pink
            setTitleColor(.white, for: .normal)
            accessibilityLabel = "打开心跳话术库"
            showsMenuAsPrimaryAction = true
        default:
            titleLabel?.font = .systemFont(ofSize: 16)
            backgroundColor = brand.specialKey
        }
        restingColor = backgroundColor
    }

    /// 九宫格 key: the digit on top, the letters it carries underneath.
    func applyNineKey(digit: String, letters: String?) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = digit
        configuration.subtitle = letters
        configuration.titleAlignment = .center
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 21, weight: .regular)
            return outgoing
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 9, weight: .semibold)
            outgoing.foregroundColor = KeyboardPalette.ink.withAlphaComponent(0.45)
            return outgoing
        }
        self.configuration = configuration
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        backgroundColor = KeyboardPalette.key
        restingColor = backgroundColor
        accessibilityLabel = letters == nil ? digit : "\(digit), \(letters ?? "")"
    }

    private var pressedColor: UIColor {
        guard let action else { return KeyboardPalette.pressedSpecial }
        switch action {
        case .heart: return KeyboardPalette.pinkDeep
        case .character, .digit, .space, .punctuation: return KeyboardPalette.pressedKey
        case .shift, .backspace, .newline, .numbers, .letters, .nextKeyboard:
            return KeyboardPalette.pressedSpecial
        }
    }
}

/// A compact chip for the pinyin candidate strip: just the word, centred.
final class CandidateCell: UICollectionViewCell {

    static let reuseID = "CandidateCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 17)
        label.textColor = KeyboardPalette.ink
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = KeyboardPalette.card
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = KeyboardPalette.hairline.cgColor
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(word: String, isFirst: Bool) {
        label.text = word
        // The first candidate is what 空格 commits, so it reads as selected.
        contentView.layer.borderColor = isFirst
            ? KeyboardPalette.pink.cgColor
            : KeyboardPalette.hairline.cgColor
        contentView.backgroundColor = isFirst
            ? KeyboardPalette.pinkSoft
            : KeyboardPalette.card
        accessibilityLabel = word
    }
}

/// The 九宫格 key map, in the order Chinese keyboards use.
enum NineKeyMap {
    static let letters: [String: String] = [
        "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
        "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ",
    ]

    /// 符号 key on the 九宫格: the marks people actually type in chat.
    static let punctuation = [
        "，", "。", "？", "！", "、", "：", "；", "…", "~", "·",
        "（", "）", "「", "」", "“", "”", "《", "》", "—", "…",
    ]
}

/// One line of ready-to-send 话术 in the suggestion strip.
final class SuggestionCell: UICollectionViewCell {

    static let reuseID = "SuggestionCell"

    private let badgeLabel = UILabel()
    private let bodyLabel = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = KeyboardPalette.pinkDeep
        badgeLabel.backgroundColor = KeyboardPalette.pinkSoft
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.layer.masksToBounds = true
        badgeLabel.textAlignment = .center

        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.numberOfLines = 3
        bodyLabel.textColor = KeyboardPalette.ink

        let badgeRow = UIStackView(arrangedSubviews: [badgeLabel, UIView()])
        badgeRow.axis = .horizontal

        stack.axis = .vertical
        stack.spacing = 3
        stack.addArrangedSubview(badgeRow)
        stack.addArrangedSubview(bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.backgroundColor = KeyboardPalette.card
        contentView.layer.cornerRadius = 14
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = KeyboardPalette.hairline.cgColor
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(with suggestion: Suggestion) {
        bodyLabel.text = suggestion.text
        badgeLabel.text = suggestion.badge
        badgeLabel.isHidden = suggestion.badge == nil
        accessibilityLabel = suggestion.text
        contentView.layer.borderColor = suggestion.badge?.hasPrefix("🎯") == true
            ? KeyboardPalette.pinkDeep.cgColor
            : (suggestion.isContextAware
            ? KeyboardPalette.pink.cgColor
            : KeyboardPalette.hairline.cgColor)
    }
}
