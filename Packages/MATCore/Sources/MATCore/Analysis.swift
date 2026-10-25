import Foundation

// MARK: - Perl 数值格式
//
// 三个不同的格式化口径，混用就会在 CSV 上分叉：
//   round2 = sprintf "%.2f"
//   f2     = 同上，但保留尾部 0（"374.00"）
//   num    = Perl 默认的插值精度 %.15g（"5.55111512312578e-16"）
//
// ⚠️ 取整方向必须按 **Windows** 的来，不能按 macOS 的来。
//
// 原版 MAT 只在 Windows 上跑，`sprintf "%.2f"` 走的是 MSVCRT：
// 遇到精确的 .5 时**远离零**取整（-0.625 → "-0.63"）。
// macOS 的 libc 走的是「向偶数取整」（-0.625 → "-0.62"）。
//
// 这不是理论问题：GroundTruth 语料里 11 个格子正好踩在 .5 上
// （CONC 的 (0−0.05)/0.08 = −0.625、TTR 的 (77/4−51.1)/5.2 = −6.125、
//  CONJ 的 5.625、TO 的 2.125），Windows 原版全部给「远离零」的那一侧。
// 用 macOS 的规则会稳定差 0.01，并顺带把 Dimension4 推偏 0.01。

public enum Perl {
    /// `sprintf "%.2f"`（Windows/MSVCRT 语义：精确 .5 远离零）
    ///
    /// 注意**不能**用 `(x * 100).rounded() / 100` 来判边界：
    /// `-1.775` 的精确二进制值是 `-1.77499999999999991…`，乘 100 会被舍入成
    /// 恰好 `-177.5`，于是被误判成 .5 而进到 -1.78；printf 看的是精确展开，
    /// 给的是 -1.77。GroundTruth 的 AWL 列就是这么差出来的。
    ///
    /// 所以：先取 30 位十进制展开，只有「第 3 位起恰好是 5 后跟全 0」才算真 .5；
    /// 真 .5 时在最后一位加 1（远离零），其余情况交回系统 printf。
    @inline(__always) public static func f2(_ x: Double) -> String {
        guard x.isFinite else { return String(format: "%.2f", x) }
        let s = String(format: "%.30f", x)
        let neg = s.hasPrefix("-")
        let body = neg ? String(s.dropFirst()) : s
        guard let dot = body.firstIndex(of: ".") else { return String(format: "%.2f", x) }
        let intPart = String(body[body.startIndex..<dot])
        let frac = Array(body[body.index(after: dot)...])
        // 第 3 位（下标 2）是 5、其后全 0 ⇒ 精确的 .xx5
        guard frac.count >= 3, frac[2] == "5",
              frac.dropFirst(3).allSatisfy({ $0 == "0" }) else {
            return String(format: "%.2f", x)
        }
        // 精确的 .xx5 → 远离零
        let cents = (Int(intPart) ?? 0) * 100 + Int(String(frac[0...1]))! + 1
        let val = Double(cents) / 100
        return String(format: "%.2f", neg ? -val : val)
    }

    @inline(__always) public static func round2(_ x: Double) -> Double {
        Double(f2(x)) ?? x
    }

    @inline(__always) public static func num(_ x: Double) -> String { String(format: "%.15g", x) }
}

// MARK: - 计数结果

public struct Profile: Sendable {
    public let tokens: Int
    public let totalChars: Int
    public let typesInWindow: Int
    public let awl: Double
    public let raw: [String: Int]
    /// `Count: All tags` 模式的计数：除 `_NULL` / `_MD` 外的**全部** tag，
    /// 逗号映射成 `COMMA`，括号型特征也按自己的键计入。
    /// 只在报告层用，不参与维度计算。
    public let allTags: [String: Int]
}

// MARK: - 单文件结果

public struct DocumentResult: Sendable {
    public let name: String
    public let tokens: Int
    public let awl: Double
    public let types: Int
    public let raw: [String: Int]
    public let allTags: [String: Int]
    public let freq: [String: Double]
    public let z: [String: Double]
    public let dims: [Int: Double]
    public let textType: String
    public let closestGenre: [Int: String]      // 逐维度最近体裁
}

public struct AnalysisResult: Sendable {
    public let corpusName: String
    public let documents: [DocumentResult]
    public let corpusZ: [String: Double]?
    public let corpusDims: [Int: Double]?
    public let corpusTextType: String?
    public let corpusTokens: Double?
    public let corpusAWL: Double?
    public let corpusTypes: Double?
}

// MARK: - 特征计数（count_only.pl）

public struct FeatureCounter: Sendable {
    private let c: Catalog
    public init(_ catalog: Catalog = .shared) { self.c = catalog }

    /// 复刻 count_only.pl 的 104-126 行
    public func count(_ tokens: [Token], ttrWindow: Int) -> Profile {
        var tokensCount = 0
        var totalChars = 0
        var eligible: [String] = []
        var counts: [String: Int] = [:]

        var allTags: [String: Int] = [:]

        for t in tokens {
            // Count: All tags —— 除 _NULL / _MD 外全收，逗号写成 COMMA。
            // 原版这一支在 split 之后按 token 处理，所以括号型特征是独立的键。
            if t.tag != "NULL", t.tag != "MD" {
                allTags[t.tag == "," ? "COMMA" : t.tag, default: 0] += 1
            }
            for f in t.features { allTags[f.rawValue, default: 0] += 1 }

            // 分母与 AWL/TTR 样本是同一个集合：排除标点与 POS；_NULL 照常计入
            if t.isPunctuation || t.tag == "POS" { continue }
            tokensCount += 1
            totalChars += t.surface.utf8.count          // 原版按字节计长
            eligible.append(t.surface)
            if t.tag != "NULL", c.tagFeatures.contains(t.tag) {
                counts[t.tag, default: 0] += 1
            }
            for f in t.features { counts[f.rawValue, default: 0] += 1 }
        }

        // TTR：前 N 个有效词的去重数；样本不足时复刻 lc(undef) 的 +1 缺陷
        var seen = Set<String>()
        var types = 0
        for i in 0..<max(ttrWindow, 0) {
            if i < eligible.count {
                if seen.insert(eligible[i].lowerASCII).inserted { types += 1 }
            } else if i == eligible.count {
                types += 1
            }
        }

        let awl = Perl.round2(Double(totalChars) / Double(max(tokensCount, 1)))
        return Profile(tokens: tokensCount, totalChars: totalChars,
                       typesInWindow: types, awl: awl, raw: counts, allTags: allTags)
    }
}

// MARK: - 统计（calc_dimensions.pl）

public struct Scorer: Sendable {
    private let c: Catalog
    public init(_ catalog: Catalog = .shared) { self.c = catalog }

    /// 归一化 + z 分数：三次取整链的第一、二环
    public func score(_ p: Profile, ttrWindow: Int) -> (freq: [String: Double], z: [String: Double]) {
        var freq: [String: Double] = [:]
        var z: [String: Double] = [:]
        for f in c.featureOrder where f != "AWL" && f != "TTR" {
            let raw = p.raw[f] ?? 0
            let per100 = Perl.round2(Double(raw) / Double(max(p.tokens, 1)) * 100)
            freq[f] = per100
            z[f] = Perl.round2((per100 - (c.means[f] ?? 0)) / (c.sds[f] ?? 1))
        }
        z["AWL"] = Perl.round2((p.awl - (c.means["AWL"] ?? 0)) / (c.sds["AWL"] ?? 1))
        // 原版只在窗口恰好等于 400 时才给 TTR 的 z，否则直接 0
        z["TTR"] = ttrWindow == 400
            ? Perl.round2((Double(p.typesInWindow) / 4.0 - (c.means["TTR"] ?? 0)) / (c.sds["TTR"] ?? 1))
            : 0
        return (freq, z)
    }

    /// 维度分：只求和，不再取整（原版就是这样，会带浮点噪声）
    public func dimensions(_ z: [String: Double], clamp: Bool) -> [Int: Double] {
        var zz = z
        if clamp {
            for k in zz.keys { zz[k] = min(5, max(-5, zz[k]!)) }
        }
        func pick(_ f: String) -> Double { zz[f] ?? 0 }
        func sum(_ fs: [String]) -> Double {
            var acc = 0.0
            for f in fs { acc += pick(f) }        // 顺序与原版表达式一致
            return acc
        }
        // 正向 / 负向特征的书写顺序必须与 calc_dimensions.pl:184-205 完全相同
        let d1p = ["[PRIV]", "[THATD]", "[CONT]", "VPRT", "SPP2", "[PROD]", "XX0", "DEMP",
                   "EMPH", "FPP1", "PIT", "[BEMA]", "CAUS", "DPAR", "INPR", "AMP", "POMD",
                   "ANDC", "[STPR]"]
        let d1n = ["NN", "AWL", "PIN", "TTR", "JJ"]
        return [
            1: sum(d1p) - sum(d1n),
            2: sum(["VBD", "TPP3", "[PEAS]", "[PUBV]", "SYNE", "[PRESP]"]),
            3: sum(["[WHOBJ]", "[WHSUB]", "PHC", "NOMZ"]) - sum(["TIME", "PLACE", "RB"]),
            4: sum(["TO", "PRMD", "[SUAV]", "COND", "NEMD", "[SPAU]"]),
            5: sum(["CONJ", "[PASS]", "[WZPAST]", "OSUB"]),
            6: sum(["THVC", "DEMO"]),
        ]
    }

    /// 文本类型：D1–D5 欧氏距离，平局按声明顺序（原版是哈希序，不确定）
    public func textType(_ dims: [Int: Double]) -> String {
        var best: (String, Double)?
        for t in c.textTypes {
            var acc = 0.0
            for i in 0..<5 {
                let d = dims[i + 1] ?? 0
                let e = d - t.values[i]
                acc += e * e
            }
            let dist = acc.squareRoot()
            if best == nil || dist < best!.1 { best = (t.name, dist) }
        }
        return best?.0 ?? ""
    }

    /// 体裁：**逐维度**一维最近邻（原版就是这么粗糙）
    public func closestGenre(_ dims: [Int: Double]) -> [Int: String] {
        var out: [Int: String] = [:]
        for d in 1...6 {
            let v = dims[d] ?? 0
            var best: (String, Double)?
            for g in c.genres {
                let dist = abs(v - g.values[d - 1])
                if best == nil || dist < best!.1 { best = (g.name, dist) }
            }
            out[d] = best?.0 ?? ""
        }
        return out
    }
}

// MARK: - 全流程

public struct Analyzer: Sendable {
    public let catalog: Catalog
    private let engine: RuleEngine
    private let counter: FeatureCounter
    private let scorer: Scorer

    public init(catalog: Catalog = .shared) {
        self.catalog = catalog
        self.engine = RuleEngine(catalog)
        self.counter = FeatureCounter(catalog)
        self.scorer = Scorer(catalog)
    }

    /// 只跑标注（L1 比对用）
    public func annotateOnly(_ tokens: [Token]) -> [Token] { engine.annotate(tokens) }

    /// - Parameter documents: (文件名, 已标注 token)
    public func analyze(
        _ documents: [(name: String, tokens: [Token])],
        corpusName: String = "",
        ttrWindow: Int = 400,
        clamp: Bool = false
    ) -> AnalysisResult {
        var docs: [DocumentResult] = []
        for doc in documents {
            let annotated = engine.annotate(doc.tokens)
            let profile = counter.count(annotated, ttrWindow: ttrWindow)
            let (freq, z) = scorer.score(profile, ttrWindow: ttrWindow)
            let dims = scorer.dimensions(z, clamp: clamp)
            docs.append(DocumentResult(
                name: doc.name, tokens: profile.tokens, awl: profile.awl,
                types: profile.typesInWindow, raw: profile.raw, allTags: profile.allTags,
                freq: freq, z: z,
                dims: dims, textType: scorer.textType(dims),
                closestGenre: scorer.closestGenre(dims)))
        }

        guard docs.count > 1 else {
            return AnalysisResult(corpusName: corpusName, documents: docs, corpusZ: nil,
                                  corpusDims: nil, corpusTextType: nil,
                                  corpusTokens: nil, corpusAWL: nil, corpusTypes: nil)
        }

        // 语料级：z 逐个累加（特征每次累加都取整，AWL/TTR 不取整——原版的怪癖）
        let n = Double(docs.count)
        var acc: [String: Double] = [:]
        for d in docs {
            for f in catalog.featureOrder where f != "AWL" && f != "TTR" {
                acc[f] = Perl.round2((acc[f] ?? 0) + (d.z[f] ?? 0))
            }
            acc["AWL"] = (acc["AWL"] ?? 0) + (d.z["AWL"] ?? 0)
            if ttrWindow == 400 {
                acc["TTR"] = (acc["TTR"] ?? 0) + (d.z["TTR"] ?? 0)
            } else {
                acc["TTR"] = 0
            }
        }
        var corpusZ: [String: Double] = [:]
        for (k, v) in acc { corpusZ[k] = Perl.round2(v / n) }

        var dimAcc: [Int: Double] = [:]
        for i in 1...6 { dimAcc[i] = docs.reduce(0.0) { $0 + ($1.dims[i] ?? 0) } }
        var corpusDims: [Int: Double] = [:]
        for i in 1...6 { corpusDims[i] = Perl.round2(dimAcc[i]! / n) }

        let tokensAvg = Perl.round2(docs.reduce(0.0) { $0 + Double($1.tokens) } / n)
        let awlAvg = Perl.round2(docs.reduce(0.0) { $0 + $1.awl } / n)
        let typesAvg = Perl.round2(docs.reduce(0.0) { $0 + Double($1.types) } / n)

        return AnalysisResult(
            corpusName: corpusName, documents: docs, corpusZ: corpusZ, corpusDims: corpusDims,
            corpusTextType: scorer.textType(corpusDims),
            corpusTokens: tokensAvg, corpusAWL: awlAvg, corpusTypes: typesAvg)
    }
}
