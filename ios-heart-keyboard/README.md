# 心跳键盘 · iOS 键盘扩展

一个真的能装进 iOS 的输入法，两件事：

1. **识别聊天内容 + 高情商回复**：截图或粘贴一段聊天记录，判断 TA 的情绪和意图，给出三句能直接发的话，外加「别这样说」。
2. **九宫格拼音输入**：全拼、简拼、首音节联想、尾字联想、模糊音、上屏学习，67,000 条词库，全部离线。

零依赖、不联网（除非你自己接模型）、不需要「允许完全访问」（剪贴板识别和网络生成除外）。

## 怎么装到 iPhone 上

iOS 不允许直接装自定义键盘，必须先用 Xcode 编译签名一次。按你的设备选一条路：

### 有 Mac：5 分钟

```bash
brew install xcodegen
cd ios-heart-keyboard && xcodegen generate && open HeartKeyboard.xcodeproj
```

Xcode 里给两个 target 都选上你的 Apple ID（Team），手机插上，选 `HeartKeyboard` scheme 点 Run。
手机上先信任：设置 → 通用 → VPN 与设备管理 → 信任你的开发者。
然后加键盘：设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 心跳键盘。

### 只有 Windows：GitHub Actions 编译 + Sideloadly 安装

不需要 Mac。编译交给免费的 GitHub macOS runner，签名交给 Sideloadly。

1. 把这个目录放到一个 GitHub 仓库根目录（`.github/workflows/build-ipa.yml` 和 `ios-heart-keyboard/` 同级）：

   ```bash
   git init && git add . && git commit -m "heart keyboard"
   gh repo create heart-keyboard --public --source=. --push   # 或手动建仓库再 push
   ```

2. 仓库 → Actions → **Build unsigned IPA** → Run workflow。跑完在 Artifacts 下载 zip，解压得到 `HeartKeyboard-unsigned.ipa`。
3. iPhone 打开开发者模式：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启。
4. Windows 装 [Sideloadly](https://sideloadly.io/) → 连线 → 把 `.ipa` 拖进去 → 填你的 Apple ID → Start。
   提示 bundle ID 冲突时，把 Bundle ID 改成 `com.你的名字.heartkeyboard`（扩展会自动跟着改）。
5. 手机上信任证书（设置 → 通用 → VPN 与设备管理），再加键盘。

### 免费 Apple ID 的三个限制（这条要看清）

1. **7 天过期**：到期后 App 和键盘一起失效，用 Sideloadly 重签一次就行（不用重新编译）。
2. **App Group 不可用**：App Group 是付费账号（$99/年）才有的能力。免费账号下「App 里识别整段对话 → 键盘直接显示」这条链路走不通，但键盘自己该会的都会：九宫格、通用话术，以及 💗 →「识别剪贴板里的聊天」——在聊天里复制几句，键盘就地完成情绪识别 + 高情商回复，不需要 App。
3. 键盘的「允许完全访问」要在设置里手动打开，剪贴板识别需要它；九宫格和通用话术不需要。

付费账号（$99/年）换来的是：有效期 1 年、App Group 可用（截图 OCR 那条路打通）、能上 TestFlight / App Store。

---

## 一、先说一个绕不过去的限制

**iOS 的键盘扩展读不到别的 App 的聊天界面。** 系统没有这个 API，微信/iMessage 里的对话内容键盘拿不到，这不是权限问题，是平台设计。

所以「识别聊天内容」在 iOS 上有三条能跑通的路，这个项目三条都做了：

| 路径 | 怎么用 | 需要什么 | 在哪实现 |
| --- | --- | --- | --- |
| 截图识别 | 在聊天里截图 → 打开 App → 选图 → Vision OCR 分左右气泡 → 出回复 | 无 | `HostApp/ChatOCR.swift` |
| 粘贴识别 | 复制聊天记录 → 粘到 App 里 → 出回复 | 无 | `ChatTranscript.parse` |
| 剪贴板就地识别 | 聊天里复制几句 → 切到键盘 → 💗 → 「识别剪贴板里的聊天」 | 允许完全访问 | `KeyboardViewController.analyzeClipboard` |

App 识别完把结果写进 App Group，键盘上方直接就是那三句。这是 iOS 上唯一能"读懂整段对话"的可行架构。

## 二、文件结构

```
ios-heart-keyboard/
├── HeartKeyboard/                      # 键盘扩展 target
│   ├── KeyboardViewController.swift    键盘本体：话术条 / 候选条 + 九宫格 + 26 键 + 💗 菜单
│   ├── KeyboardViews.swift             调色板、按键、话术卡片、候选卡片、九宫格键位表
│   ├── T9Dictionary.swift              词库读取（二分查找，不建内存字典）
│   ├── T9Engine.swift                  九宫格引擎：候选、排序、联想、模糊音、上屏学习
│   ├── ChatTranscript.swift            对话解析：粘贴文本 / OCR 行 → 带说话人的消息
│   ├── ChatAnalyzer.swift              情绪 / 意图 / 信号识别 + 策略选择
│   ├── ReplyComposer.swift             高情商回复组装（稳 / 暖 / 进 + 别这样说）
│   ├── ReplyStrategy.swift             11 种情绪 × 开场 / 关心 / 推进 / 反例 / 提示
│   ├── ReplyEngine.swift               通用话术库（没有聊天记录时的兜底）
│   ├── ReplyProvider.swift             三层生成：本地规则 / Apple Intelligence / 你自己的模型
│   ├── SharedStore.swift               App ↔ 键盘 的 App Group 交接
│   ├── Lines.swift                     通用话术数据（脚本生成）
│   ├── Resources/                      九宫格词库（见其 README-dictionary.txt）
│   └── Info.plist
├── HostApp/                            # 宿主 App target
│   ├── HeartKeyboardApp.swift
│   ├── ContentView.swift               开启指引 + 试聊页
│   ├── AnalyzeView.swift               识别聊天：截图 / 粘贴 → 情绪、策略、三句回复、反例
│   └── ChatOCR.swift                   Vision 文字识别 + 左右气泡判说话人
└── project.yml                         XcodeGen 工程文件（可选）
```

## 三、跑起来

### 方式 A：XcodeGen

```bash
brew install xcodegen
cd ios-heart-keyboard && xcodegen generate && open HeartKeyboard.xcodeproj
```

### 方式 B：Xcode 手搓（5 分钟）

1. 新建 iOS App 工程 `HeartKeyboard`（SwiftUI / Swift），再 New → Target → **Keyboard Extension**，名叫 `HeartKeyboardExtension`。
2. 把文件拖进工程：
   - `KeyboardViewController / KeyboardViews / T9Dictionary / T9Engine` → 只勾 **Ext**
   - `ChatTranscript / ChatAnalyzer / ReplyComposer / ReplyStrategy / ReplyProvider / SharedStore / Lines` → **两个 target 都勾**
   - `HostApp/*` → 只勾 **App**
   - `HeartKeyboard/Resources` → 勾 **Ext**（App 也勾一份也没问题），确保在 **Copy Bundle Resources** 里
3. 用仓库里的 `HeartKeyboard/Info.plist` 覆盖模板生成的（确认 `NSExtensionPointIdentifier` = `com.apple.keyboard-service`、`NSExtensionPrincipalClass` = `$(PRODUCT_MODULE_NAME).KeyboardViewController`）。
4. **两个 target 都加 App Group**：Signing & Capabilities → + Capability → App Groups → 新建 `group.com.example.heartkeyboard`（要和 `SharedStore.appGroupID` 完全一致）。
5. 部署目标 iOS 16.0（想用本机模型生成回复要 iOS 26 + Apple Intelligence 设备）。

### 打开键盘

设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 心跳键盘。聊天界面点输入框，长按 🌐 切过来。
模拟器记得关掉 I/O → Keyboard → Connect Hardware Keyboard。

## 四、九宫格是怎么工作的

**词库**：Rime 简体拼音词库（Apache-2.0，源自 AOSP PinyinIME），63,408 条有效词条，生成 3MB 资源：

| 文件 | 内容 | 用途 |
| --- | --- | --- |
| `t9.dict` | 数字串 → 词 | 全拼候选 |
| `t9.initials` | 首字母数字串 → 词 | 简拼（25 → 北京） |
| `t9.syllable` | 首音节 → 常用词 | 输入 54 → 技术/里面/继续 |
| `t9.chain` | 字 → 常用词 | 上屏"你好"后联想"好像/好看" |

**打字习惯**（都做了）：

- 全拼 / 简拼 / 首音节联想混在一个候选条里，按"覆盖度 × 词频 × 词长"排序
- **空格键 = 上屏第一个候选**，回删优先删拼音、再删正文
- **长按数字键直接上屏数字**
- **符号键**调出聊天常用标点
- **上屏学习**：发过的词会往前排；同一个数字串上次选了哪个词，下次它排第一
- **尾字联想**：上屏一个词后，候选条换成以它末尾字开头的词，接着点就行
- **模糊音 n↔l / f↔h**：可在 💗 菜单开启，命中的标「模糊」并降权
- **26 键 ↔ 九宫格**：候选条右上角一键切换，两种键盘都保留

实测（`work/build-t9.mjs` 跑真实词库）：

```
64426      → 你好 / 你敢 / 米高            + 你好啊 你好吗
542226     → 加班 / 甲板 / 假扮            + 加班费 加班加点
9426464    → 想你 / 向你 / 像你
24         → 比 爱 唉 次 哎               + 比较 必须 比如  + 简拼 不过 不会 不好
54         → 里 及 级 即 几               + 技术 里面 继续
25         → 简拼 比较 出来 北京 处理
```

已知取舍：多音节输入到一半时（比如打了 4 位但词还没完整），主要靠全拼精确匹配和简拼，不会穷举所有音节切分；前后鼻音（an/ang）模糊音还没做。

## 五、识别 + 高情商回复是怎么工作的

```
截图/粘贴/剪贴板
   → ChatTranscript    分说话人（OCR 按气泡左右；文本按 TA：/名字/微信格式）
   → ChatAnalyzer      情绪（11 类词库 + 标点、句长、连发、深夜、反话等结构信号）
                       意图（求安慰 / 在问你怎么办 / 在表达不满 / 在试探 / 想分享…）
                       信号（最后一句是问句、回复在变短、出现"算了"、抓住了具体的事）
   → ReplyStrategy     选策略：该共情还是该认领，别说什么
   → ReplyComposer     组装三句：稳（只接情绪）/ 暖（接情绪 + 具体关心）/ 进（接情绪 + 轻推进）
                       外加「别这样说」和理由
   → SharedStore       App Group 交给键盘
```

**生成分三层，永远给得出结果**：

1. `RuleBasedProvider` —— 本地策略引擎，离线、即时、能解释每一句为什么。这是保底。
2. `AppleIntelligenceProvider` —— iOS 26 本机模型（`FoundationModels`），只改写措辞，结构、反例、红线仍由规则引擎决定，失败就回退。
3. `CloudReplyProvider` —— 任何 OpenAI 兼容接口，在 App 里填 endpoint / model / key 即用（正式产品请走自己的后端，别把 key 放进 App）。

真实的识别结果（在 `work/test-analyzer.mjs` 里跑同一套词典逻辑验证过）：

| 对话 | 识别 | 生成（稳 / 暖 / 进 摘录） |
| --- | --- | --- |
| 加班到十点，累死了 / 甲方改了三版 / 不说了我先睡 | 疲惫·压力 · 想被接住情绪 · 关键词「甲方」 | 「先说结论：你不是不努力，你是真的太累了。」/「「甲方下午改了三版」——我看着都替你累」/「这周找个晚上，我请你吃顿热的，什么都不用聊。」 |
| 嗯 / 没事 / 随便吧 | 冷淡·在退开 · 有点想退开 | 「好，我不问。你想说的时候我都在。」/「我周末的下午空出来了，你想来就来」/「这个周末见一面吧，你不想说话，我就陪你走一段路。」 |
| 都两点多了，你怎么还不睡 / 那你都不理我，哼 | 撒娇·要关注 · 想要你的注意 | 「好，我认错，你说什么都对。」/「再气两秒可以，第三秒要给我回一个抱抱。」/「现在就想见你，我过去抱一下就走。」 |
| 你昨天说好要来看我的 / 算了，我不说了 | 委屈·生气 · 在表达对你的不满 | 认领情绪，不辩解，给台阶 |

反例会直接告诉你为什么，比如「别想那么多，早点睡。」→ 否定情绪 + 讲道理，TA 要的是被看见，不是被开导。

## 六、验证状态（重要）

诚实说明，避免你按错误的预期验收：

- **词库和识别逻辑是真跑过的**：`work/build-t9.mjs` 用真实词库验证了九宫格候选质量，`work/test-analyzer.mjs` 用六段对话验证了情绪识别（这三个 bug 就是这轮抓出来并修掉的：疲惫被误判成"没情绪"、"算了"被误判成冷淡、撒娇没识别出来）。
- **Swift 代码没有编译过**：这台机器是 Windows，没有 Xcode。接口都按 iOS 16+ 标准写法，`FoundationModels` 的签名我去 Apple 官方文档核对过（`SystemLanguageModel.default.availability`、`LanguageModelSession(instructions:)`、`await session.respond(to:)`、`response.content`）。第一次编译如果有报错，贴回来我改。
- 最可能需要你确认的两处：`Resources` 有没有进 Copy Bundle Resources；App Group 的字符串在两个 target 是否一致（App 的识别页会直接提示你）。

## 七、还能继续做

- 前后鼻音模糊音、双拼、自定义短语（打 `dz` 出地址）
- 用户词库导入导出，跟自己的口头禅走
- 把 `ReplyStrategy` 的措辞换成你自己的说话风格（改一个文件就够）
