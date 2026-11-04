import AppKit
import SwiftUI

/// 界面主题：默认「日光」，可换成「夜光」或跟随系统。
enum AppTheme: String, CaseIterable, Identifiable {
    case daylight
    case night
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: return tr("Daylight", "日光")
        case .night: return tr("Night", "夜光")
        case .system: return tr("Match System", "跟随系统")
        }
    }

    /// nil = 跟随系统。
    var appearance: NSAppearance? {
        switch self {
        case .daylight: return NSAppearance(named: .aqua)
        case .night: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

extension NSColor {
    /// 跟随窗口外观自动切换的颜色（日光 / 夜光）。
    static func tt(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// 设计稿里的颜色名（见 Speakorb 全部界面 · 组件与规范）。
extension Color {
    static let ttBackground = Color(nsColor: .tt(0xFBFAFE, 0x0B0B12))
    static let ttSidebar = Color(nsColor: .tt(0xF0EEF8, 0x161622))
    static let ttCard = Color(nsColor: .tt(0xFFFFFF, 0x1A1A28))
    static let ttCardAlt = Color(nsColor: .tt(0xF6F5FB, 0x21212F))
    static let ttLine = Color(nsColor: .tt(0x1C1450, 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.08))
    static let ttField = Color(nsColor: .tt(0x1E1450, 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.06))
    static let ttText = Color(nsColor: .tt(0x1C1A33, 0xECEBFA))
    static let ttMuted = Color(nsColor: .tt(0x6E6A88, 0x8F8CAB))
    /// 文字和图标上的强调色。
    static let ttAccent = Color(nsColor: .tt(0x5546D8, 0xA99FFF))
    /// 按钮、开关的填充色。
    static let ttBrand = Color(nsColor: .tt(0x5546D8, 0x6E5BFF))
    static let ttBrand2 = Color(nsColor: .tt(0x6A5AF0, 0x9B7BFF))
    static let ttAccentSoft = Color(nsColor: .tt(0x5546D8, 0x6E5BFF, lightAlpha: 0.11, darkAlpha: 0.2))
    static let ttAccentRing = Color(nsColor: .tt(0x5546D8, 0x9682FF, lightAlpha: 0.3, darkAlpha: 0.35))
    static let ttHalo = Color(nsColor: .tt(0x6E5BFF, 0x6E5BFF, lightAlpha: 0.16, darkAlpha: 0.38))
    static let ttOK = Color(nsColor: .tt(0x1E9A60, 0x4ADE9B))
    static let ttOKSoft = Color(nsColor: .tt(0x1E9A60, 0x4ADE9B, lightAlpha: 0.12, darkAlpha: 0.12))
    static let ttWarn = Color(nsColor: .tt(0xC26A10, 0xFFB15C))
    static let ttWarnSoft = Color(nsColor: .tt(0xFFB15C, 0xFFB15C, lightAlpha: 0.2, darkAlpha: 0.12))
    static let ttBad = Color(nsColor: .tt(0xD23B3B, 0xFF7A7A))
    static let ttRec = Color(nsColor: .tt(0xE5484D, 0xFF6B8A))

    // 声球
    static let orb1 = Color(nsColor: .tt(0xE2DBFF, 0xCFC4FF))
    static let orb2 = Color(nsColor: .tt(0x6A5AF0, 0x6E5BFF))
    static let orb3 = Color(nsColor: .tt(0x3A2DB0, 0x1E1660))
    static let orbGlow = Color(nsColor: .tt(0x5B4BE0, 0x7864FF, lightAlpha: 0.42, darkAlpha: 0.85))
    static let orbWarm = Color(nsColor: .tt(0xFF9F5A, 0xFFB15C))
}

/// 首次引导固定用日光配色，不跟主题走。
enum Day {
    static let background = Color(nsColor: NSColor(hex: 0xF5F3FC))
    static let card = Color.white
    static let text = Color(nsColor: NSColor(hex: 0x1C1A33))
    static let muted = Color(nsColor: NSColor(hex: 0x6E6A88))
    static let brand = Color(nsColor: NSColor(hex: 0x5B4BE0))
    static let brandSoft = Color(nsColor: NSColor(hex: 0xEEEBFD))
    static let ok = Color(nsColor: NSColor(hex: 0x1FA971))
    static let okSoft = Color(nsColor: NSColor(hex: 0xE5F6EE))
    static let okText = Color(nsColor: NSColor(hex: 0x145C3E))
    static let line = Color(nsColor: NSColor(hex: 0xD8D3EE))
    static let quiet = Color(nsColor: NSColor(hex: 0xF0EEF9))
}

extension Font {
    static func ttMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// 日期跟界面语言：Today / 今天、Yesterday / 昨天、Nov 2 / 11月2日。
enum TTDate {
    static var locale: Locale { L10n.current.locale }

    static func dayTitle(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return tr("Today", "今天") }
        if cal.isDateInYesterday(date) { return tr("Yesterday", "昨天") }
        let f = DateFormatter()
        f.locale = locale
        let thisYear = cal.isDate(date, equalTo: now, toGranularity: .year)
        f.dateFormat = thisYear ? tr("MMM d", "M月d日") : tr("MMM d, yyyy", "yyyy年M月d日")
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func duration(ms: Int) -> String {
        let s = max(0, ms / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
