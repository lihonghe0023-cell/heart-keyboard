import Foundation

/// A line that looks helpful but usually makes things worse, plus the reason.
/// These are shown as 「别这样说」 in the app and in the keyboard.
struct CounterExample {
    let text: String
    let why: String
}

/// What a high-EQ reply does for one emotional situation.
///
/// Templates use two placeholders:
///   `{quote}` — the other person's last message, trimmed
///   `{kw}`    — the concrete thing they mentioned, for example 「加班到十点」
struct Strategy {
    /// The one-line principle behind every reply in this situation.
    let move: String
    /// Openings that receive the emotion instead of arguing with it.
    let openings: [String]
    /// Specific care or a follow-up question that keeps them talking.
    let middles: [String]
    /// A light move forward — invite, meet, or take one small action.
    let push: String
    /// Things not to say.
    let avoid: [CounterExample]
    /// Rules of thumb for this emotional state.
    let tips: [String]
}

enum ReplyStrategy {

    static let neutral = Strategy(
        move: "没有明显情绪时，抓住一个细节提问，比寒暄有用。",
        openings: [
            "「{quote}」——好，我记住了。",
            "这条我想认真回你。",
        ],
        middles: [
            "你今天过得怎么样？说点细节给我听。",
            "跟我讲讲{kw}的后续，我想知道。",
        ],
        push: "找个时间见一面吧，我想听你多讲一点。",
        avoid: [
            CounterExample(text: "哦，好的。", why: "最没有温度的回复，等于把话题关掉。"),
            CounterExample(text: "在吗？", why: "「在吗」既没信息也没情绪，对方要先猜你的目的。"),
        ],
        tips: ["没有情绪信号时，用细节提问代替寒暄。"]
    )

    static let all: [String: Strategy] = [
        "tired": Strategy(
            move: "先接住累，别急着给办法；把关心落到一件具体的小事上。",
            openings: [
                "先说结论：你不是不努力，你是真的太累了。",
                "「{quote}」——我看着都替你累，别急着说「还行」。",
                "辛苦了。这三个字听着轻，但我是认真在说。",
            ],
            middles: [
                "先别管剩下的，今晚只办一件事：跟我要句安慰，或者干脆骂两句，我接得住。",
                "你现在最想先解决哪一件？说出来我帮你分一半。",
                "别撑着说没事，在我这儿你可以直接说「我累了」。",
            ],
            push: "这周找个晚上，我请你吃顿热的，什么都不用聊。",
            avoid: [
                CounterExample(text: "别想那么多，早点睡。", why: "否定情绪 + 讲道理，TA 要的是被看见，不是被开导。"),
                CounterExample(text: "你要学会拒绝啊。", why: "TA 已经累到没力气了，此刻的建议都是负担。"),
            ],
            tips: ["情绪差的时候先接情绪，不给方案。"]
        ),
        "upset": Strategy(
            move: "先认领情绪，不辩解；对方要的是站在同一边。",
            openings: [
                "这事换我我也得炸，你气是有道理的。",
                "「{quote}」——你不是小题大做，是确实过分。",
                "先别管谁对谁错，我站你这边。",
            ],
            middles: [
                "你想让我听着就好，还是想跟我一起想个办法？你说，我配合。",
                "我不跟你讲道理，我只要你现在舒服一点。",
                "想骂就骂，我这边不用过滤。",
            ],
            push: "要不今晚出来走走，你想骂多久我都听着。",
            avoid: [
                CounterExample(text: "你先冷静一下。", why: "「冷静」听起来像站在对面，先承认 TA 有理由。"),
                CounterExample(text: "这有什么好生气的。", why: "否定情绪等于火上浇油，TA 会更孤立。"),
            ],
            tips: ["对方生气时，先认领情绪，不要辩解。"]
        ),
        "sad": Strategy(
            move: "在场感优先：陪着比解决重要，提问要轻。",
            openings: [
                "我在。",
                "「{quote}」——看完有点难受，别一个人扛。",
                "你现在不用装没事，我这边不需要你坚强。",
            ],
            middles: [
                "想说话我一直在，不想说我就安静陪着你。",
                "要不要跟我说说，是哪一刻开始觉得撑不住的？",
                "先不想以后，我们先把今天过完。",
            ],
            push: "我现在过去找你，不说话也行，就想跟你坐一会儿。",
            avoid: [
                CounterExample(text: "开心点，都会过去的。", why: "空头安慰会让人觉得自己的难过被草草打发了。"),
                CounterExample(text: "你要坚强一点。", why: "难过的当下最不需要的就是「要求」。"),
            ],
            tips: ["陪伴 > 建议，提问要轻。"]
        ),
        "anxious": Strategy(
            move: "先稳情绪，再把大问题拆成一小步，明确你陪哪一段。",
            openings: [
                "我在，先深呼吸。",
                "「{quote}」——别一个人想，说出来我们一起拆。",
                "不管结果怎么样，你都不用一个人面对。",
            ],
            middles: [
                "我们就拆一小步：你现在做完哪件事，天就塌不下来？",
                "你最怕的那部分交给我，剩下的你自己走，我陪着。",
                "把最坏的情况写出来，我们一起看一遍，通常没那么可怕。",
            ],
            push: "今晚出来喝点东西，把最坏的情况摊在桌上讲一遍。",
            avoid: [
                CounterExample(text: "你想太多了。", why: "这句话会让 TA 觉得连焦虑都不配拥有。"),
                CounterExample(text: "别焦虑了，没用。", why: "焦虑不是开关，先接住再拆解。"),
            ],
            tips: ["先稳情绪，再拆步骤，别劝「别想」。"]
        ),
        "happy": Strategy(
            move: "把开心放大，追问一个具体细节，让 TA 继续讲。",
            openings: [
                "哈哈哈我就知道，你开心隔着屏幕都能看出来。",
                "「{quote}」！这个必须展开讲。",
                "看到你这条消息，我心情都跟着好了。",
            ],
            middles: [
                "快讲细节，我当时不在场，得补完整版。",
                "所以最后到底是怎么成的？我想听你吹这一段。",
                "这事值得庆祝，你想怎么庆祝，我配合。",
            ],
            push: "那就定下来，我请你吃一顿好的，庆祝这件事。",
            avoid: [
                CounterExample(text: "哦，挺好。", why: "两个字浇灭分享欲，下次 TA 就不想跟你说了。"),
                CounterExample(text: "这算什么，我上次更厉害。", why: "把话题抢回自己身上，是分享欲的杀手。"),
            ],
            tips: ["对方开心时，放大情绪 + 追问细节。"]
        ),
        "bored": Strategy(
            move: "别问「在干嘛」，给一件具体的小事和一个时间。",
            openings: [
                "来得正好，我刚好也想找你。",
                "「{quote}」——那我们两个无聊的人凑一起就不无聊了。",
                "我这边刚闲下来，信号满格。",
            ],
            middles: [
                "你现在最想干的三件事是什么？我挑一件陪你做。",
                "跟我说说你最近有什么想做还没做的，我们挑一件。",
                "别刷手机了，刷我不香吗。",
            ],
            push: "出来晃一圈吧，就半小时，我下楼接你。",
            avoid: [
                CounterExample(text: "嗯，在。", why: "这种回复等于告诉 TA「别来烦我」。"),
                CounterExample(text: "你可以找我聊天啊。", why: "把主动权全推回去，TA 会更没劲。"),
            ],
            tips: ["别问「在干嘛」，给一件具体的事。"]
        ),
        "cute": Strategy(
            move: "接住撒娇，顺着玩，给一句有画面的话。",
            openings: [
                "好，我认错，你说什么都对。",
                "「{quote}」这种话一出，我基本没有抵抗力。",
                "行行行，我哄，哄到你满意为止。",
            ],
            middles: [
                "再气两秒可以，第三秒要给我回一个抱抱。",
                "那你现在最想让我做哪件事？我照做。",
                "你撒起娇来我一点原则都没有，你自己知道吗。",
            ],
            push: "现在就想见你，我过去抱一下就走。",
            avoid: [
                CounterExample(text: "别闹了，说正事。", why: "撒娇是在要安全感，被打断会直接缩回去。"),
                CounterExample(text: "幼稚。", why: "一句话就能让 TA 以后不再跟你撒娇。"),
            ],
            tips: ["接住撒娇，顺着玩，别讲道理。"]
        ),
        "chilly": Strategy(
            move: "降压力：不追问原因，给一件具体的小事，留出空间。",
            openings: [
                "好，我不问。你想说的时候我都在。",
                "「{quote}」，收到了，我不催你。",
                "行，那我先不打扰，就留一句：我在。",
            ],
            middles: [
                "我周末的下午空出来了，你想来就来，不来也不影响。",
                "今天没心情说话也没关系，我发个好吃的给你看，不用回。",
                "要是不知道怎么开口，就发个句号给我，我懂。",
            ],
            push: "这个周末见一面吧，你不想说话，我就陪你走一段路。",
            avoid: [
                CounterExample(text: "你怎么了？你是不是不想理我？", why: "连环追问会把距离越推越远。"),
                CounterExample(text: "我们聊聊吧。", why: "「聊聊」两个字压力太大，TA 会先逃。"),
            ],
            tips: ["变冷时降压力，给具体的小事，不追问原因。"]
        ),
        "flirty": Strategy(
            move: "接住暧昧，往前一格，但别越级，留一句话给 TA 接。",
            openings: [
                "你这句话我不接住，今晚就别想睡了。",
                "「{quote}」——你确定要在这个时间点跟我说这个？",
                "行，我上钩了，你满意了？",
            ],
            middles: [
                "有件事我还没跟你说：我最近刷手机，第一个想看的就是你。",
                "这种事别用文字，当面说给我听。",
                "那我认真问一句：你想见我吗？",
            ],
            push: "那就见一面吧，把下半句说完。",
            avoid: [
                CounterExample(text: "你想太多了吧。", why: "把暧昧当玩笑处理，等于关门。"),
                CounterExample(text: "我们还是做朋友吧。", why: "没到那一步就别自己先退，会显得在逃。"),
            ],
            tips: ["暧昧要接住 + 前进一格，但别越级。"]
        ),
        "sick": Strategy(
            move: "问清具体症状，给一个具体的照顾动作，别啰嗦。",
            openings: [
                "哪不舒服？说具体点，我这边好判断。",
                "「{quote}」——别撑，难受就是难受。",
                "你先别自己扛，我过去还是寄过去，你选一个。",
            ],
            middles: [
                "药吃了吗？家里有退烧的吗，没有我现在下单。",
                "今天别喝凉的，也别熬夜，我盯着你。",
                "体温多少？超过 38.5 就不是多喝水的事了。",
            ],
            push: "我现在把药和粥送过去，地址发我，放门口也行。",
            avoid: [
                CounterExample(text: "多喝热水。", why: "四个字约等于「我不想管」。"),
                CounterExample(text: "你怎么不早说。", why: "先责怪再关心，顺序反了。"),
            ],
            tips: ["生病时的关心要具体：症状、药、要不要送过去。"]
        ),
        "hungry": Strategy(
            move: "别讲道理也别扫兴，直接给一个具体的行动。",
            openings: [
                "别忍了，想吃什么，我请。",
                "「{quote}」——这话一听就饿，说吧哪家。",
                "正好我也饿，我们算凑一起了。",
            ],
            middles: [
                "我给你点，把地址发我。",
                "这顿我请，下顿你请，这样我们就有下一次了。",
                "要是懒得动，我去买回来。",
            ],
            push: "现在就吃，我过去接你。",
            avoid: [
                CounterExample(text: "那你吃啊。", why: "敷衍到看不出一点在乎。"),
                CounterExample(text: "你不是在减肥吗。", why: "扫兴 + 说教，两样都占了。"),
            ],
            tips: ["饿的时候别讲道理，直接给行动。"]
        ),
    ]

    /// Concrete things worth quoting back, so a reply sounds like it read the chat.
    static let topics = [
        "加班", "甲方", "老板", "领导", "同事", "客户", "项目", "方案", "汇报",
        "考试", "面试", "论文", "答辩", "期末", "作业",
        "感冒", "发烧", "低烧", "咳嗽", "嗓子", "头疼", "胃", "医院", "体温", "拉肚子",
        "出差", "搬家", "健身", "跑步", "减肥", "相亲",
        "房租", "工资", "奖金", "提成", "离职", "升职", "爸妈",
        "旅游", "演唱会", "话剧", "电影",
        "奶茶", "火锅", "夜宵", "外卖", "喝酒", "生日",
    ]

    /// Endings that keep the door open without asking for anything back.
    static let steadyClosers = [
        "不用急着回我，我在。",
        "你先照顾好自己的情绪，别的我来想。",
        "我随时都在。",
    ]

    /// A light, persona-aware tail for the 「进」 reply.
    static func pushTail(persona: String) -> String {
        switch persona {
        case "lover": return "（我安排，你只负责出现）"
        case "ex": return "（你要是不方便，就当我没说）"
        default: return "（时间你定，我不催你）"
        }
    }
}
