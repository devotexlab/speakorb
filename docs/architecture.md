# 架构 / Architecture

```
SpeakorbApp（SwiftUI + AppKit，菜单栏 App）
├─ FloatingBar：不抢焦点的 NSPanel 悬浮条，声球跟音量
├─ Onboarding / MainWindow / SettingsViews：界面
├─ Language：tr("English", "中文")，界面语言默认英文
├─ Theme / Components：日光 / 夜光配色、声球、按钮等组件
├─ LegacyMigration：从内部代号 Talktype 搬数据（一次）
└─ AppModel：把下面几个模块串起来，给界面发布状态

SpeakorbCapture
├─ HotkeyMonitor：CGEventTap，右 Option 切换 / Esc 取消
├─ AudioRecorder：AVAudioEngine → 16 kHz 单声道 Int16 → WAV，音量 level 0…1
├─ SpeechTranscriber：SFSpeechRecognizer，按听写语言（中文 / 英文）选识别器，有离线包时强制离线
├─ Paster：剪贴板 + ⌘V，安全输入框只复制，贴完恢复剪贴板
└─ Permissions：麦克风 / 辅助功能 / 输入监控检测与系统设置入口

SpeakorbCore（不依赖 AppKit / AVFoundation，可单测）
├─ SessionController：idle → listening → transcribing → injecting → idle / failed
├─ Router：本机 / 接入服务直出 / 接入服务整理（DeepSeek）/ 不可用
├─ Refiner：中文 / 英文两套提示词、常用词、后处理（中文去句尾句号，英文保留）
└─ Errors：每种失败的中文说法（界面层另有英文）

SpeakorbProviders：Gemini、OpenAI、OpenRouter、DeepSeek、百炼、OpenAI 兼容；HTTPTransport 可注入
SpeakorbStorage：钥匙串（app.speakorb.keys）、SQLite 记录、UserDefaults 设置
```

## 约束 / Constraints

- 没有服务器：直接连你选的服务；App 不收集音频或文字。
- Core 不依赖系统框架，单元测试不发真实网络请求。
- 所有系统开关按需检查，缺了给人话提示和修复按钮。
- 界面文案不说技术词；每句英文和中文写在同一处（`tr`），改一处两种语言一起看。

## 数据流 / Flow

1. 热键或按钮 → `SessionController.begin()`，悬浮条出现，声球跟 `AudioRecorder.level`。
2. 再按一次 → 得到 `AudioPayload(.wav)`，悬浮条变成“正在整理”。
3. `Router` 决定本机还是接入的服务；服务失败且本机可用时自动换成本机。
4. `Refiner` 后处理 → `Paster` 贴进当前输入框 → 存进记录。
5. 悬浮条的声球缩成光标，1.2 秒后收起；没成就停在“这次没成”，给“重说”。
