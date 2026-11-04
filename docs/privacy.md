# 隐私 / Privacy

声球（Speakorb）没有服务器，没有账号，不收集任何使用数据，也没有遥测。
Speakorb has no servers, no accounts, no telemetry, and collects no usage data.

## 录音去哪 / Where audio goes

| 听写方式 / Dictation | 录音去哪 / Audio goes to |
| --- | --- |
| 本机听写，装了离线语言包 / On-device, offline pack installed | 不离开这台 Mac / Stays on this Mac |
| 本机听写，没装离线语言包 / On-device, no offline pack | macOS 把录音交给 Apple 的在线听写 / macOS sends it to Apple's online dictation |
| Gemini、OpenAI、OpenRouter、百炼、自定义服务 / Gemini, OpenAI, OpenRouter, Bailian, custom | 只发给你选的那一家 / Only the one you choose |
| DeepSeek | 先用本机听写（规则同上两行），再只把文字发给 DeepSeek / On-device dictation first (same rules as the first two rows), then only the text goes to DeepSeek |

- 接入的服务只有在你选它做默认、并且打开「允许用我接入的服务」时才会收到内容。
  A connected service only receives anything when it's your default and "Allow connected services" is on.
- 接入的服务出错时，会自动换成本机听写（目前不会单独提示，见路线图）。
  If a connected service fails, Speakorb falls back to on-device dictation (there's no separate notice yet; see the roadmap).
- 「设置 → 隐私」会显示你现在是哪一种。
  Settings → Privacy shows which case applies to you right now.

装离线语言包 / Install the offline pack：系统设置 → 键盘 → 听写 / System Settings → Keyboard → Dictation.

## 钥匙 / Keys

- 存在 macOS 钥匙串（服务名 `app.speakorb.keys`，每家服务一项）。
  Stored in the macOS Keychain (service `app.speakorb.keys`, one item per provider).
- 不写日志、不进错误报告、不上传。
  Never logged, never included in diagnostics, never uploaded.

## 说过的话 / History

- 只存在本机：`~/Library/Application Support/Speakorb/speakorb.sqlite`。
  Stored only on your Mac at `~/Library/Application Support/Speakorb/speakorb.sqlite`.
- 可以在 App 里导出、单条删除、全部删除。「设置 → 关于 → 彻底删除」会删掉记录、常用词、钥匙和设置。
  You can export, delete single entries or delete everything. Settings → About → Delete all Speakorb data removes history, custom words, keys and settings.

## 复制错误信息 / Copy diagnostics

「帮助与反馈 → 复制错误信息」只包含版本号、系统版本、各个开关是否打开、默认听写方式和最近一次失败的错误代码，不含任何你说过的话、钥匙或窗口内容。
"Help & feedback → Copy diagnostics" contains only versions, which permissions are on, your default dictation and the last error code — never anything you said, your keys or window contents.

## 系统开关 / System permissions

| 开关 / Permission | 用来做什么 / Used for |
| --- | --- |
| 麦克风 / Microphone | 录你说的话 / Recording what you say |
| 输入监控 / Input Monitoring | 只对右 ⌥ 和 esc 有反应，其他按键直接忽略，不记录也不保存 / Reacts only to right ⌥ and esc; every other key is ignored, never recorded or stored |
| 辅助功能 / Accessibility | 模拟 ⌘V 把字放进输入框 / Simulating ⌘V to put text into fields |
| 语音识别 / Speech Recognition | macOS 系统听写 / macOS dictation |

贴字时会临时用一下剪贴板，然后把原来的内容放回去；密码框等安全输入框里不会自动贴，只复制。
Pasting briefly uses the clipboard and then restores what was there. In secure fields such as passwords, Speakorb only copies and never pastes.
