# 心跳键盘 · 恋爱聊天输入法

两个东西：一个能马上点开玩，一个能装进 iPhone。

| 位置 | 是什么 |
| --- | --- |
| [heartbeat-keyboard.html](heartbeat-keyboard.html) | 可交互原型：iPhone 外壳里的聊天界面 + 自定义键盘 + 话术库面板，双击即可在浏览器里用手指玩。 |
| [ios-heart-keyboard/](ios-heart-keyboard/) | 真实的 iOS 键盘扩展源码（Swift，iOS 16+）：九宫格拼音输入法 + 识别聊天内容的高情商回复，含词库、Info.plist、宿主 App 与 XcodeGen 配置。 |

原型共用通用话术库（7 场景 × 5 语气 = 105 句 + 11 条上下文钩子）；iOS 端在此之上多了九宫格词库（63,408 条）和情绪识别引擎。
