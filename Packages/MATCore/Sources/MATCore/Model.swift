import Foundation

// MARK: - 括号型特征
//
// 只有这 24 个特征是「追加」到 token 上的；另外 41 个特征是标签本身的值
// （NN / JJ / VPRT / PIN …），不需要枚举，直接比较 tag 字符串。

public enum Bracket: String, CaseIterable, Sendable {
    case bema = "[BEMA]", bypa = "[BYPA]", cont = "[CONT]", pass = "[PASS]"
    case pastp = "[PASTP]", peas = "[PEAS]", pire = "[PIRE]", presp = "[PRESP]"
    case priv = "[PRIV]", prod = "[PROD]", pubv = "[PUBV]", sere = "[SERE]"
    case smp = "[SMP]", spau = "[SPAU]", spin = "[SPIN]", stpr = "[STPR]"
    case suav = "[SUAV]", thatd = "[THATD]", whcl = "[WHCL]", whobj = "[WHOBJ]"
    case whqu = "[WHQU]", whsub = "[WHSUB]", wzpast = "[WZPAST]", wzpres = "[WZPRES]"
}

// MARK: - Token

public struct Token: Sendable, Equatable {
    public var surface: String
    public var tag: String
    /// 倒序：后触发的特征在前（对应 Perl 的 `s/_(\w+)/_$1 [X]/` 插入语义）
    public var features: [Bracket]

    public init(surface: String, tag: String, features: [Bracket] = []) {
        self.surface = surface
        self.tag = tag
        self.features = features
    }

    /// tag 的首字符不是字母/数字 → 标点（覆盖 `.` `,` `(` `-LRB-`）
    public var isPunctuation: Bool {
        guard let c = tag.unicodeScalars.first else { return false }
        return !(c.properties.isAlphabetic || (c.value >= 48 && c.value <= 57))
    }

    /// 序列化成原版一行：`word_TAG [FEAT] [FEAT]`
    public var serialized: String {
        features.isEmpty
            ? "\(surface)_\(tag)"
            : "\(surface)_\(tag) " + features.map(\.rawValue).joined(separator: " ")
    }

    /// 解析整条 token 流。
    ///
    /// 输入形如 `The_DT report_NN was_VBD [BYPA] by_PIN`——**空白分隔、可跨行**；
    /// `[XXX]` 是紧跟其前一个词的标记，不是一个独立词。原版正是 `split(/\s+/)` 后
    /// 把 `[XXX]` 当独立 token 计数的，所以这里要还原成「词 + 特征数组」。
    public static func parseStream(_ text: String) -> [Token] {
        var out: [Token] = []
        var surface = ""
        var tag = ""
        var feats: [Bracket] = []
        var hasCurrent = false

        func flush() {
            if hasCurrent {
                out.append(Token(surface: surface, tag: tag, features: feats))
            }
        }

        for raw in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
            let field = String(raw)
            if field.hasPrefix("[") {
                if let b = Bracket(rawValue: field) { feats.append(b) }
                continue
            }
            flush()
            guard let firstUS = field.firstIndex(of: "_"),
                  let lastUS = field.lastIndex(of: "_") else { continue }
            surface = String(field[..<firstUS])
            tag = String(field[field.index(after: lastUS)...])
            feats = []
            hasCurrent = true
        }
        flush()
        return out
    }
}

// MARK: - 只折 ASCII 的小写
//
// Perl 在没有 use locale 时，`/i` 只对 ASCII 折叠。用 `lowercased()` 会把
// `İ`/`ß` 之类也改掉，导致与原版分叉。

extension String {
    public var lowerASCII: String {
        if utf8.allSatisfy({ $0 < 0x80 }) { return lowercased() }
        var out = String(); out.reserveCapacity(count)
        for u in unicodeScalars {
            if u.value >= 65 && u.value <= 90 {
                out.unicodeScalars.append(Unicode.Scalar(u.value + 32)!)
            } else {
                out.unicodeScalars.append(u)
            }
        }
        return out
    }

    /// 最长连续 `\w` 片段长度（Perl 的 `\w` = 字母数字下划线，按字节）
    public var maxWordRun: Int {
        var best = 0, cur = 0
        for b in utf8 {
            let isWord = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95
            if isWord { cur += 1; if cur > best { best = cur } } else { cur = 0 }
        }
        return best
    }
}

// MARK: - TagStream
//
// 复刻 Perl 的 `@word`：负索引回绕到末尾，越界为 undef（返回 nil）。

public struct TagStream {
    public var tokens: [Token]
    public init(_ tokens: [Token]) { self.tokens = tokens }
    public var count: Int { tokens.count }

    @inline(__always) public func at(_ i: Int) -> Token? {
        let n = tokens.count
        if n == 0 { return nil }
        if i < 0 { let m = i % n; return tokens[m < 0 ? m + n : m] }
        return i < n ? tokens[i] : nil
    }

    @inline(__always) public func tag(_ i: Int) -> String? { at(i)?.tag }
    @inline(__always) public func w(_ i: Int) -> String? { at(i)?.surface.lowerASCII }
    @inline(__always) public func punct(_ i: Int) -> Bool { at(i)?.isPunctuation ?? false }

    /// `_XXX` 在原版里等价于「tag 以 XXX 开头」（下划线紧贴 tag 首字符）
    @inline(__always) public func tp(_ i: Int, _ prefix: String) -> Bool {
        tag(i)?.hasPrefix(prefix) ?? false
    }

    @inline(__always) public func tp(_ i: Int, any prefixes: [String]) -> Bool {
        guard let t = tag(i) else { return false }
        for p in prefixes where t.hasPrefix(p) { return true }
        return false
    }

    @inline(__always) public func wIs(_ i: Int, _ word: String) -> Bool { w(i) == word }

    mutating func setTag(_ i: Int, _ new: String) {
        if i >= 0 && i < tokens.count { tokens[i].tag = new }
    }

    /// 插入到 tag 之后 = 数组最前，从而复刻多特征的倒序
    mutating func add(_ f: Bracket, at i: Int) {
        if i >= 0 && i < tokens.count { tokens[i].features.insert(f, at: 0) }
    }
}

private func isWordScalar(_ u: Unicode.Scalar) -> Bool {
    (u.value >= 48 && u.value <= 57) || (u.value >= 65 && u.value <= 90)
        || (u.value >= 97 && u.value <= 122) || u.value == 95
}

// MARK: - Lexicon
//
// 统一处理所有 Perl 词表：`add_V` / `be_` / `ca_MD` 三种形状。
// 语义 = surface 精确相等 且 tag 以给定前缀开头（空前缀表示不限 tag）。

public struct Lexicon: Sendable {
    private var bySurface: [String: [String]]

    public init(fragment: String) {
        var map: [String: [String]] = [:]
        for item in fragment.split(separator: "|") {
            let s = String(item)
            guard !s.isEmpty else { continue }
            if let r = s.range(of: "_", options: .backwards) {
                let surface = String(s[..<r.lowerBound]).lowerASCII
                let prefix = String(s[r.upperBound...])
                map[surface, default: []].append(prefix)
            } else {
                map[s.lowerASCII, default: []].append("")
            }
        }
        bySurface = map
    }

    public init(words: [String]) {
        var map: [String: [String]] = [:]
        for w in words { map[w.lowerASCII, default: []].append("") }
        bySurface = map
    }

    /// 复刻 Perl 的 `\b(word1_|word2_|…)` 语义。
    ///
    /// 关键是**真正的词边界**，不是「前缀 / 去一个非单词字符」这种近似：
    /// - `'s_VBZ` 命中 `\bs_VBZ`：撇号后 s 前是边界 → 成立。
    /// - `'ve_VBP` **不**命中 `\b've_`：第 0 位是撇号（非单词字符）与串首之间**没有**边界 → 不成立。
    ///   这一条曾让我在 `'ve been waiting` 上多标了一个 `[PEAS]`。
    /// - `we've_VBP` 则**命中** `\b've_`：e→' 之间是边界。
    ///
    /// 实现方式：枚举串内所有边界位置 p，取 p 到下一个 `_` 之间的片段去查表。
    /// 每 token 的边界数极少（撇号/连字符），所以比逐个词表项扫描快得多。
    public func matches(_ t: Token?) -> Bool {
        guard let t else { return false }
        let cand = t.surface.lowerASCII + "_" + t.tag
        let scalars = Array(cand.unicodeScalars)
        var p = 0
        while p < scalars.count {
            let curIsWord = isWordScalar(scalars[p])
            let prevIsWord = p > 0 && isWordScalar(scalars[p - 1])
            if curIsWord != prevIsWord {                       // Perl 的 \b 成立
                var q = p
                while q < scalars.count, scalars[q] != "_" { q += 1 }
                if q < scalars.count {
                    let surface = String(String.UnicodeScalarView(scalars[p..<q]))
                    if let prefixes = bySurface[surface] {
                        for pref in prefixes where pref.isEmpty || t.tag.hasPrefix(pref) {
                            return true
                        }
                    }
                }
            }
            p += 1
        }
        return false
    }

    @inline(__always) public func matches(_ s: TagStream, _ i: Int) -> Bool { matches(s.at(i)) }
}
