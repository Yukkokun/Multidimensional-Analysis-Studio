import Foundation

/// 复刻 `curly_correct.pl`：把 Word 常见弯引号折成 ASCII。
///
/// 原版是**就地覆写用户源文件**（curly_correct.pl:20-24），我们不那么干——
/// 只在内存里转换，源文件保持原样。
///
/// 为什么必须有这一步：Stanford 的 `-textFile` 会做 PTB 分词，
/// `don’t`（弯撇号）与 `don't`（ASCII）分出来的 token 不一样，
/// 后者的 `n't` 才能命中 P2.1 的 `\bn't_RB` 拿到 XX0，进而影响 [CONT] 与 D1。
public enum TextPreparer {
    /// 与原版一致，只处理这四个字符；不改 en/em dash。
    public static func normalize(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value >= 0x2018 && $0.value <= 0x201D }) else {
            return text
        }
        var s = text
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")   // ‘
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")   // ’
        s = s.replacingOccurrences(of: "\u{201C}", with: "\"")  // “
        s = s.replacingOccurrences(of: "\u{201D}", with: "\"")  // ”
        return s
    }

    /// 是否含弯引号（用于给用户提示"已自动转换"）
    public static func needsNormalization(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x2018 && $0.value <= 0x201D }
    }
}
