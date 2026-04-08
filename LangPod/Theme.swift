import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    // MARK: - App Colors

    /// 页面背景色
    static let appBackground = Color(hex: "F7F8FC")

    /// 主色调蓝
    static let appPrimary = Color(hex: "3B82F6")

    /// 深色文字
    static let textPrimary = Color(hex: "1E293B")
    /// 次要文字
    static let textSecondary = Color(hex: "64748B")
    /// 辅助文字 / placeholder
    static let textTertiary = Color(hex: "94A3B8")
    /// 更浅的文字
    static let textQuaternary = Color(hex: "CBD5E1")

    /// 分割线 / 边框
    static let border = Color(hex: "E2E8F0")
    /// 浅色分割线
    static let divider = Color(hex: "F1F5F9")

    /// 成功绿
    static let success = Color(hex: "22C55E")
    /// 警告橙
    static let warning = Color(hex: "F59E0B")
    /// 错误红
    static let danger = Color(hex: "EF4444")
    /// 橙色（Hard 级别）
    static let hardOrange = Color(hex: "F97316")

    /// 蓝色浅底
    static let primaryLight = Color(hex: "EFF6FF")
    /// 蓝色中间底
    static let primaryLighter = Color(hex: "DBEAFE")
    /// 绿色浅底
    static let successLight = Color(hex: "DCFCE7")
    /// 黄色浅底
    static let warningLight = Color(hex: "FEF3C7")
    /// 红色浅底
    static let dangerLight = Color(hex: "FEF2F2")

    /// 深蓝色（Paywall 标题）
    static let navyTitle = Color(hex: "1E3A5F")
    /// 深色正文
    static let bodyText = Color(hex: "475569")
    /// 金色（Pro 徽章/成就）
    static let gold = Color(hex: "92400E")
    /// 紫色（渐变辅助）
    static let accentPurple = Color(hex: "6366F1")
}

extension DateFormatter {
    /// Format matching episode date strings: "2026-04-02"
    static let episodeDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
