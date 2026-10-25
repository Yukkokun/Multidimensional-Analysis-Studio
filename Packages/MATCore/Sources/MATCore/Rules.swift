import Foundation

// MARK: - 规则引擎
//
// 每个 pass 对应 Tagger_MAT.pl 的一个循环；注释里的 `P3.22 行362` 是
// Docs/RuleTable.md 里的规则 id 与 Perl 行号。**数组顺序即规格**，不许重排、不许合并。
//
// 两条贯穿全局的语义：
//   `_XXX` ⇒ tag.hasPrefix("XXX")（下划线紧贴 tag 首字符）
//   nil（越界）⇒ 正向条件为假、取反条件为真（Perl 的 undef 语义）

public struct RuleEngine: Sendable {
    private let c: Catalog
    public init(_ catalog: Catalog = .shared) { self.c = catalog }

    public func annotate(_ tokens: [Token]) -> [Token] {
        var s = TagStream(tokens)
        pass0(&s); pass1(&s); pass2(&s); pass3(&s)
        pass4(&s); pass5(&s); pass6(&s); pass7(&s); pass8(&s)
        return s.tokens
    }

    // MARK: P0 · 符号修正（行 159-165）

    private func pass0(_ s: inout TagStream) {
        for i in 0..<s.count {
            // 原版是 /PRP./ → s/PRP./PRPS/，PTB 里只有 PRP$ 会命中
            if s.tokens[i].tag == "PRP$" { s.tokens[i].tag = "PRPS" }   // P0.1 行162
            if s.tokens[i].tag == "WP$" { s.tokens[i].tag = "WPS" }     // P0.2 行163
        }
    }

    // MARK: P1 · to 作介词（行 168-174）

    private static let toNextPrefixes = ["IN", "CD", "DT", "JJ", "PRPS", "WPS",
                                         "NN", "NNP", "PDT", "PRP", "WDT", "WRB"]

    private func pass1(_ s: inout TagStream) {
        for j in 0..<s.count where s.wIs(j, "to") {                     // P1.1 行170
            if s.tp(j + 1, any: Self.toNextPrefixes)
                || c.lexWP.matches(s, j + 1) || c.lexWho.matches(s, j + 1) {
                s.setTag(j, "PIN")
            }
        }
    }

    // MARK: P2 · 基础标签（行 177-206）

    private func pass2(_ s: inout TagStream) {
        for j in 0..<s.count {
            if let w = s.w(j), (w == "not" || w == "n't"), s.tp(j, "RB") {
                s.setTag(j, "XX0")                                      // P2.1 行180
            }
            if c.lexPrep.matches(s, j) { s.setTag(j, "PIN") }            // P2.2 行186
            guard let w = s.w(j) else { continue }
            if c.inpr.contains(w) { s.setTag(j, "INPR") }                // P2.3 行192
            if c.quan.contains(w) { s.setTag(j, "QUAN") }                // P2.4 行197
            if c.qupr.contains(w) { s.setTag(j, "QUPR") }                // P2.5 行202（覆盖 P2.3）
        }
    }

    // MARK: P3 · 复杂标签主循环（行 210-584，57 条）

    private static let emphish = ["just", "really", "most", "more"]
    private static let jjPred = ["JJ", "PRED"]
    private static let rbXX0 = ["RB", "XX0"]
    private static let notNN = ["JJ", "RB", "NN", "NNP"]
    private static let askTell: Set<String> = ["ask", "asks", "asked", "asking",
                                              "tell", "tells", "told", "telling"]
    private static let conjGuardPrefixes = ["OSUB", "DPAR", "CONJ"]

    /// `/_MD|do|have|be|_V/` 的联合判定（多个规则共用）
    @inline(__always)
    private func isVerbish(_ s: TagStream, _ i: Int) -> Bool {
        s.tp(i, "MD") || c.lexDo.matches(s, i) || c.lexHave.matches(s, i)
            || c.lexBe.matches(s, i) || s.tp(i, "V")
    }

    private func pass3(_ s: inout TagStream) {
        for j in 0..<s.count {
            // P3.1 行213 从属连词
            if let w = s.w(j), ["since", "while", "whilst", "whereupon", "whereas", "whereby"].contains(w) {
                s.setTag(j, "OSUB")
            }

            // P3.2 行216 多词从属连词
            if let w = s.w(j) {
                if (w == "such" && s.wIs(j + 1, "that"))
                    || (w == "inasmuch" && s.wIs(j + 1, "as"))
                    || (w == "forasmuch" && s.wIs(j + 1, "as"))
                    || (w == "insofar" && s.wIs(j + 1, "as"))
                    || (w == "insomuch" && s.wIs(j + 1, "as"))
                    || (w == "so" && s.wIs(j + 1, "that") && !s.tp(j + 2, any: ["NN", "NNP", "JJ"])) {
                    s.setTag(j, "OSUB"); s.setTag(j + 1, "NULL")
                }
                // P3.3 行225
                if (w == "as" && s.wIs(j + 1, "long") && s.wIs(j + 2, "as"))
                    || (w == "as" && s.wIs(j + 1, "soon") && s.wIs(j + 2, "as")) {
                    s.setTag(j, "OSUB"); s.setTag(j + 1, "NULL"); s.setTag(j + 2, "NULL")
                }
            }

            // P3.4-3.7 行235-246 谓语形容词
            if c.lexBe.matches(s, j) {
                if s.tp(j + 1, "JJ") && !s.tp(j + 2, any: Self.notNN) {
                    s.setTag(j + 1, "PRED")
                }
                if s.tp(j + 1, "RB") && s.tp(j + 2, "JJ") && !s.tp(j + 3, any: Self.notNN) {
                    s.setTag(j + 2, "PRED")
                }
                if s.tp(j + 1, "XX0") && s.tp(j + 2, "JJ") && !s.tp(j + 3, any: Self.notNN) {
                    s.setTag(j + 2, "PRED")
                }
                if s.tp(j + 1, "XX0") && s.tp(j + 2, "RB") && s.tp(j + 3, "JJ")
                    && !s.tp(j + 4, any: Self.notNN) {
                    s.setTag(j + 3, "PRED")
                }
            }
            // P3.8 行247 PRED + PHC 之后的 JJ
            if s.tp(j - 2, "PRED") && s.tp(j - 1, "PHC") && s.tp(j, "JJ") {
                s.setTag(j, "PRED")
            }

            // P3.9 行254
            if s.punct(j), let w1 = s.w(j + 1), ["else", "altogether", "rather"].contains(w1) {
                s.setTag(j + 1, "CONJ")
            }
            // P3.10 行259
            if c.listConj.matches(s, j) { s.setTag(j, "CONJ") }

            // P3.11 行262（两词）
            if let w = s.w(j) {
                let w1 = s.w(j + 1)
                if (w == "in" && w1.map { ["comparison", "contrast", "particular", "addition",
                                           "conclusion", "consequence", "sum", "summary"].contains($0) } == true)
                    || (w == "for" && (w1 == "example" || w1 == "instance"))
                    || (w == "instead" && w1 == "of")
                    || (w == "by" && (w1 == "contrast" || w1 == "comparison")) {
                    s.setTag(j, "CONJ"); s.setTag(j + 1, "NULL")
                }
                // P3.12 行269（三词）
                if (w == "in" && s.wIs(j + 1, "any") && (s.wIs(j + 2, "event") || s.wIs(j + 2, "case")))
                    || (w == "in" && s.wIs(j + 1, "other") && s.wIs(j + 2, "words"))
                    || (w == "as" && s.wIs(j + 1, "a") && (s.wIs(j + 2, "result") || s.wIs(j + 2, "consequence")))
                    || (w == "on" && s.wIs(j + 1, "the") && s.wIs(j + 2, "contrary")) {
                    s.setTag(j, "CONJ"); s.setTag(j + 1, "NULL"); s.setTag(j + 2, "NULL")
                }
                // P3.13 行277（四词）
                if w == "on" && s.wIs(j + 1, "the") && s.wIs(j + 2, "other") && s.wIs(j + 3, "hand") {
                    s.setTag(j, "CONJ")
                    s.setTag(j + 1, "NULL"); s.setTag(j + 2, "NULL"); s.setTag(j + 3, "NULL")
                }
            }

            // P3.14 行287
            if let w = s.w(j), Self.emphish.contains(w) { s.setTag(j, "EMPH") }
            // P3.15 行290
            if let w = s.w(j) {
                if (w == "real" && s.tp(j + 1, any: Self.jjPred))
                    || (w == "so" && s.tp(j + 1, any: Self.jjPred))
                    || (c.lexDo.matches(s, j) && s.tp(j + 1, "V")) {
                    s.setTag(j, "EMPH")
                }
            }
            // P3.16 行295
            if let w = s.w(j) {
                if (w == "for" && s.wIs(j + 1, "sure"))
                    || (w == "a" && s.wIs(j + 1, "lot"))
                    || (w == "such" && s.wIs(j + 1, "a")) {
                    s.setTag(j, "EMPH"); s.setTag(j + 1, "NULL")
                }
            }

            // P3.17 行305 短语并列
            if s.wIs(j, "and") {
                if (s.tp(j - 1, "RB") && s.tp(j + 1, "RB"))
                    || (s.tp(j - 1, any: Self.jjPred) && s.tp(j + 1, any: Self.jjPred))
                    || (s.tp(j - 1, "V") && s.tp(j + 1, "V"))
                    || (s.tp(j - 1, "NN") && s.tp(j + 1, "NN")) {
                    s.setTag(j, "PHC")
                }
            }

            // P3.18 行316 代动词 do
            if c.lexDo.matches(s, j) {
                let c1 = !s.tp(j + 1, "V")
                let c2 = !s.tp(j + 1, "XX0")
                let c3 = !s.tp(j + 1, any: Self.rbXX0) && !s.tp(j + 2, "V")
                let c4 = !s.tp(j + 1, any: Self.rbXX0) && !s.tp(j + 2, "RB") && !s.tp(j + 3, "V")
                let c5 = !s.punct(j - 1)
                let c6 = !(c.lexWP.matches(s, j - 1) || c.lexWho.matches(s, j - 1))
                if c1 && c2 && c3 && c4 && c5 && c6 { s.add(.prod, at: j) }
            }

            // P3.19 行331 WH 疑问
            if s.punct(j), s.at(j)?.tag.contains(",") == false {
                let wh1 = s.w(j + 1)
                let ok1 = wh1 != "however" && wh1 != "whatever"
                let wh2 = s.w(j + 2)
                let ok2 = wh2 != "however" && wh2 != "whatever"
                let hit = (ok1 && c.lexWho.matches(s, j + 1)
                           && (s.tp(j + 2, "MD") || c.lexDo.matches(s, j + 2)
                               || c.lexHave.matches(s, j + 2) || c.lexBe.matches(s, j + 2)))
                    || (ok2 && c.lexWho.matches(s, j + 2) && c.lexBe.matches(s, j + 3))
                if hit { s.add(.whqu, at: j + 1) }
            }

            // P3.20 行342 句子关系词
            if s.punct(j) && s.wIs(j + 1, "which") { s.add(.sere, at: j + 1) }

            // P3.21 行349 完成时
            if c.lexHave.matches(s, j) {
                let a = s.tp(j + 1, any: ["VBD", "VBN"])
                let b = s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: ["VBD", "VBN"])
                let d = s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: Self.rbXX0)
                        && s.tp(j + 3, any: ["VBD", "VBN"])
                let e = s.tp(j + 1, any: ["NN", "NNP", "PRP"]) && s.tp(j + 2, any: ["VBD", "VBN"])
                let f = s.tp(j + 1, "XX0") && s.tp(j + 2, any: ["NN", "NNP", "PRP"])
                        && s.tp(j + 3, any: ["VBD", "VBN"])
                if a || b || d || e || f { s.add(.peas, at: j) }
            }
            // P3.22 行362 被动
            if c.lexBe.matches(s, j) {
                let a = s.tp(j + 1, any: ["VBD", "VBN"]) && !s.wIs(j + 2, "by")
                let b = s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: ["VBD", "VBN"]) && !s.wIs(j + 3, "by")
                let d = s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: Self.rbXX0)
                        && s.tp(j + 3, any: ["VBD", "VBN"]) && !s.wIs(j + 4, "by")
                let e = s.tp(j + 1, any: ["NN", "NNP", "PRP"]) && s.tp(j + 2, any: ["VBD", "VBN"])
                        && !s.wIs(j + 3, "by")
                let f = s.tp(j + 1, "XX0") && s.tp(j + 2, any: ["NN", "NNP", "PRP"])
                        && s.tp(j + 3, any: ["VBD", "VBN"]) && !s.wIs(j + 4, "by")
                if a || b || d || e || f { s.add(.pass, at: j) }
            }
            // P3.23 行375 by 被动
            if c.lexBe.matches(s, j) {
                let a = s.tp(j + 1, any: ["VBD", "VBN"]) && s.wIs(j + 2, "by")
                let b = s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: ["VBD", "VBN"]) && s.wIs(j + 3, "by")
                let d = s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: Self.rbXX0)
                        && s.tp(j + 3, any: ["VBD", "VBN"]) && s.wIs(j + 4, "by")
                let e = s.tp(j + 1, any: ["NN", "NNP", "PRP"]) && s.tp(j + 2, any: ["VBD", "VBN"])
                        && s.wIs(j + 3, "by")
                let f = s.tp(j + 1, "XX0") && s.tp(j + 2, any: ["NN", "NNP", "PRP"])
                        && s.tp(j + 3, any: ["VBD", "VBN"]) && s.wIs(j + 4, "by")
                if a || b || d || e || f { s.add(.bypa, at: j) }
            }

            // P3.24 行388 be 作主动词
            if !s.tp(j - 2, "EX") && !s.tp(j - 1, "EX") && c.lexBe.matches(s, j) {
                let set = ["CD", "DT", "PDT", "PRPS", "PRP", "JJ", "PRED", "PIN", "QUAN"]
                if s.tp(j + 1, any: set)
                    || (s.tp(j + 1, any: Self.rbXX0) && s.tp(j + 2, any: set)) {
                    s.add(.bema, at: j)
                }
            }

            // P3.25 行397 wh 从句
            if (c.lexPublic.matches(s, j) || c.lexPrivate.matches(s, j) || c.lexSuasive.matches(s, j)),
               c.lexWP.matches(s, j + 1) || c.lexWho.matches(s, j + 1),
               !(s.tp(j + 2, "MD") || c.lexDo.matches(s, j + 2)
                 || c.lexHave.matches(s, j + 2) || c.lexBe.matches(s, j + 2)) {
                s.add(.whcl, at: j + 1)
            }
            // P3.26 行404 介词前置关系从句
            if s.tp(j, "PIN"), let w1 = s.w(j + 1), ["who", "whom", "whose", "which"].contains(w1) {
                s.add(.pire, at: j + 1)
            }
            // P3.27 行411 悬空介词
            if s.tp(j, "PIN"), s.w(j) != "besides", (s.tp(j + 1, ".") || s.tp(j + 1, ",")) {
                s.add(.stpr, at: j)
            }
            // P3.28 行418 分裂不定式
            do {
                let e1 = s.tp(j + 1, any: ["RB", "AMPLIF", "DOWNTON"])
                    || (s.w(j + 1).map { Self.emphish.contains($0) } ?? false)
                if s.wIs(j, "to") && e1 && s.tp(j + 2, "V") { s.add(.spin, at: j) }
                if s.wIs(j, "to") && e1 && s.tp(j + 2, any: ["RB", "AMPLIF", "DOWNTON"])
                    && s.tp(j + 3, "V") { s.add(.spin, at: j) }
            }
            // P3.29 行426 分裂助动词
            do {
                let aux = s.tp(j, "MD") || c.lexDo.matches(s, j)
                    || c.lexHave.matches(s, j) || c.lexBe.matches(s, j)
                let e1 = s.tp(j + 1, any: ["RB", "AMPLIF", "DOWNTON"])
                    || (s.w(j + 1).map { Self.emphish.contains($0) } ?? false)
                if aux && e1 && s.tp(j + 2, "V") { s.add(.spau, at: j) }
                if aux && e1 && s.tp(j + 2, "RB") && s.tp(j + 3, "V") { s.add(.spau, at: j) }
            }

            // P3.30 行434 合成否定
            if let w = s.w(j) {
                if (w == "no" && s.tp(j + 1, any: ["JJ", "PRED", "NN", "NNP"]))
                    || w == "neither" || w == "nor" {
                    s.setTag(j, "SYNE")
                }
            }
            // P3.31 行443 / P3.32 行446 时间副词
            if c.listTime.matches(s, j) { s.setTag(j, "TIME") }
            if s.wIs(j, "soon") && !s.wIs(j + 1, "as") { s.setTag(j, "TIME") }
            // P3.33 行453 地点副词
            if c.listPlace.matches(s, j) && !s.tp(j, "NNP") { s.setTag(j, "PLACE") }

            // P3.34 行461 that 动词补语（一）
            if s.wIs(j, "that") {
                let prev = s.w(j - 1)
                let prevOK = s.punct(j - 1) || ["and", "nor", "but", "or", "also"].contains(prev ?? "")
                let nextOK = s.tp(j + 1, any: ["DT", "QUAN", "CD", "PRP", "NNS", "NNP"]) || s.wIs(j + 1, "there")
                if prevOK && nextOK { s.setTag(j, "THVC") }
            }
            // P3.35 行464 that 动词补语（二）
            if s.wIs(j, "that") {
                let prevOK = c.lexPublic.matches(s, j - 1) || c.lexPrivate.matches(s, j - 1)
                    || c.lexSuasive.matches(s, j - 1) || c.listSmp.matches(s, j - 1)
                let nextBad = s.tp(j + 1, "V") || s.tp(j + 1, "MD") || c.lexDo.matches(s, j + 1)
                    || c.lexHave.matches(s, j + 1) || c.lexBe.matches(s, j + 1)
                    || s.wIs(j + 1, "and") || s.punct(j + 1)
                if prevOK && !nextBad { s.setTag(j, "THVC") }
            }
            // P3.36-38 行467-475 长距离 that 补语
            if s.wIs(j, "that"),
               c.lexPublic.matches(s, j - 4) || c.lexPrivate.matches(s, j - 4) || c.lexSuasive.matches(s, j - 4),
               s.tp(j - 3, "PIN"), !s.tp(j - 2, "N"), s.tp(j - 1, "N") {
                s.setTag(j, "THVC")
            }
            if s.wIs(j, "that"),
               c.lexPublic.matches(s, j - 5) || c.lexPrivate.matches(s, j - 5) || c.lexSuasive.matches(s, j - 5),
               s.tp(j - 4, "PIN"), !s.tp(j - 3, "N"), !s.tp(j - 2, "N"), s.tp(j - 1, "N") {
                s.setTag(j, "THVC")
            }
            if s.wIs(j, "that"),
               c.lexPublic.matches(s, j - 6) || c.lexPrivate.matches(s, j - 6) || c.lexSuasive.matches(s, j - 6),
               s.tp(j - 5, "PIN"), !s.tp(j - 4, "N"), !s.tp(j - 3, "N"), !s.tp(j - 2, "N"),
               s.tp(j - 1, "N") {
                s.setTag(j, "THVC")
            }
            // P3.39 行480 that 形容词补语
            if s.wIs(j, "that") && s.tp(j - 1, any: Self.jjPred) { s.setTag(j, "THAC") }

            // P3.40 行487 现在分词从句
            if s.punct(j - 1), s.tp(j, "VBG") {
                let ok = s.tp(j + 1, any: ["PIN", "DT", "QUAN", "CD", "PRP", "RB"])
                    || c.lexWP.matches(s, j + 1) || s.tp(j + 1, "WPS") || c.lexWho.matches(s, j + 1)
                if ok { s.add(.presp, at: j) }
            }
            // P3.41 行494 过去分词从句
            if s.punct(j - 1), s.tp(j, "VBN"), s.tp(j + 1, any: ["PIN", "RB"]) {
                s.add(.pastp, at: j)
            }
            // P3.42 行501 过去分词 WHIZ 删略
            if (s.tp(j - 1, "N") || s.tp(j - 1, "QUPR")), s.tp(j, "VBN") {
                if s.tp(j + 1, any: ["PIN", "RB"]) || c.lexBe.matches(s, j + 1) {
                    s.add(.wzpast, at: j)
                }
            }
            // P3.43 行508 现在分词 WHIZ 删略
            if s.tp(j - 1, "N"), s.tp(j, "VBG") { s.add(.wzpres, at: j) }

            // P3.44-46 行515-523 that 关系从句（主语位）
            if s.wIs(j, "that"), s.tp(j - 1, "N") {
                if isVerbish(s, j + 1) { s.setTag(j, "TSUB") }
                else if s.tp(j + 1, any: Self.rbXX0), isVerbish(s, j + 2) { s.setTag(j, "TSUB") }
                else if s.tp(j + 1, any: Self.rbXX0), s.tp(j + 2, any: Self.rbXX0), isVerbish(s, j + 3) {
                    s.setTag(j, "TSUB")
                }
            }
            // P3.47-48 行528-533 that 关系从句（宾语位）
            if s.wIs(j, "that"), s.tp(j - 1, "N") {
                let w1 = s.w(j + 1)
                let pron = ["it", "i", "we", "he", "she", "they"].contains(w1 ?? "")
                if s.tp(j + 1, any: ["DT", "QUAN", "CD", "JJ", "NNS", "NNP", "PRPS"]) || pron {
                    s.setTag(j, "TOBJ")
                }
                if s.tp(j + 1, "N"), s.tp(j + 2, "POS") { s.setTag(j, "TOBJ") }
            }

            // P3.49-51 行538-546 wh 关系从句（主语位）
            if c.lexWP.matches(s, j), s.tp(j - 1, "N"),
               !Self.askTell.contains(s.w(j - 3) ?? "") {
                if isVerbish(s, j + 1) { s.add(.whsub, at: j) }
                else if s.tp(j + 1, any: Self.rbXX0), isVerbish(s, j + 2) { s.add(.whsub, at: j) }
                else if s.tp(j + 1, any: Self.rbXX0), s.tp(j + 2, any: Self.rbXX0), isVerbish(s, j + 3) {
                    s.add(.whsub, at: j)
                } else if !s.tp(j + 1, any: ["RB", "XX0", "MD", "V"])
                            && !c.lexDo.matches(s, j + 1) && !c.lexHave.matches(s, j + 1)
                            && !c.lexBe.matches(s, j + 1) {
                    s.add(.whobj, at: j)                                // P3.52 行551
                }
            }

            // P3.53 行558 / P3.54 行561 模糊限制语
            if s.wIs(j, "maybe") { s.setTag(j, "HDG") }
            if let w = s.w(j) {
                if (w == "at" && s.wIs(j + 1, "about")) || (w == "something" && s.wIs(j + 1, "like")) {
                    s.setTag(j, "HDG"); s.setTag(j + 1, "NULL")
                }
            }
            // P3.55 行566
            if s.wIs(j, "more") && s.wIs(j + 1, "or") && s.wIs(j + 2, "less") {
                s.setTag(j, "HDG"); s.setTag(j + 1, "NULL"); s.setTag(j + 2, "NULL")
            }
            // P3.56 行571 sort of / kind of
            if !s.tp(j - 2, any: ["DT", "QUAN", "CD", "JJ", "PRED", "PRPS"]),
               !c.lexWho.matches(s, j - 2),
               (s.wIs(j - 1, "sort") || s.wIs(j - 1, "kind")),
               s.wIs(j, "of") {
                s.setTag(j, "HDG"); s.setTag(j - 1, "NULL")
            }
            // P3.57 行580 话语小品词
            if s.punct(j - 1), let w = s.w(j), ["well", "now", "anyhow", "anyways"].contains(w) {
                s.setTag(j, "DPAR")
            }
        }
    }

    // MARK: P4 · 指示代词 DEMP（行 591-600）

    private static let thatSet: Set<String> = ["that", "this", "these", "those"]

    private func pass4(_ s: inout TagStream) {
        for j in 0..<s.count {
            guard let w = s.w(j), Self.thatSet.contains(w) else { continue }
            if s.tp(j, "NULL") || s.tp(j, any: ["TOBJ", "TSUB", "THAC", "THVC"]) { continue }
            let nextOK = s.tp(j + 1, "V") || s.tp(j + 1, "MD") || c.lexDo.matches(s, j + 1)
                || c.lexHave.matches(s, j + 1) || c.lexBe.matches(s, j + 1)
                || s.punct(j + 1) || c.lexWP.matches(s, j + 1) || s.wIs(j + 1, "and")
            if nextOK { s.setTag(j, "DEMP") }                              // P4.1 行593
        }
        for j in 0..<s.count {
            guard s.wIs(j, "that") else { continue }
            // 原式是 /'s_/ 与 /is_/ —— **无锚点子串匹配**，所以 "this_DT" 也会命中 "is_"
            // （golden 里 "that this is wrong" 的 that 因此变成 DEMP）。不要加锚点。
            if let nxt = s.at(j + 1) {
                let raw = nxt.surface + "_" + nxt.tag
                if raw.contains("'s_") || raw.contains("is_") { s.setTag(j, "DEMP") }
            }
        }
    }

    // MARK: P5 · 指示词 DEMO（行 605-610）

    private func pass5(_ s: inout TagStream) {
        for j in 0..<s.count {
            guard let w = s.w(j), Self.thatSet.contains(w) else { continue }
            if s.tp(j, any: ["DEMP", "TOBJ", "TSUB", "THAC", "THVC", "NULL"]) { continue }
            s.setTag(j, "DEMO")                                            // P5.1 行607
        }
    }

    // MARK: P6 · THATD（行 615-623，四个分支）

    private func pass6(_ s: inout TagStream) {
        for j in 0..<s.count {
            guard c.lexPublic.matches(s, j) || c.lexPrivate.matches(s, j) || c.lexSuasive.matches(s, j) else { continue }
            let w1 = s.w(j + 1)
            let pron1 = ["i", "we", "he", "she", "they"].contains(w1 ?? "")

            let a = s.tp(j + 1, "DEMP") || pron1
            let b = s.tp(j + 1, any: ["PRP", "N"]) && isVerbish(s, j + 2)
            let lead = s.tp(j + 1, any: ["JJ", "PRED", "RB", "DT", "QUAN", "CD", "PRPS"])
            let d = lead && s.tp(j + 2, "N") && isVerbish(s, j + 3)
            let e = lead && s.tp(j + 2, any: Self.jjPred) && s.tp(j + 3, "N") && isVerbish(s, j + 4)
            if a || b || d || e { s.add(.thatd, at: j) }
        }
    }

    // MARK: P7 · ANDC（行 628-642）

    private static let andcNext: Set<String> = ["and", "because", "although", "tho", "if", "unless"]

    private func pass7(_ s: inout TagStream) {
        for j in 0..<s.count where s.wIs(j, "and") {
            let comma = s.tp(j - 1, ",")
            let w1 = s.w(j + 1)
            let pron = ["it", "so", "then", "you", "i", "we", "he", "she", "they"].contains(w1 ?? "")

            if comma, (pron || s.tp(j + 1, "DEMP")) { s.setTag(j, "ANDC") }      // P7.1 行630
            if comma, s.wIs(j + 1, "there"), c.lexBe.matches(s, j + 2) {
                s.setTag(j, "ANDC")                                              // P7.2 行633
            }
            if s.punct(j - 1) { s.setTag(j, "ANDC") }                            // P7.3 行636
            if c.lexWP.matches(s, j + 1) || c.lexWho.matches(s, j + 1)
                || Self.andcNext.contains(s.w(j + 1) ?? "")
                || s.tp(j + 1, any: Self.conjGuardPrefixes) {                    // P7.4 行639
                s.setTag(j, "ANDC")
            }
        }
    }

    // MARK: P8 · 词表与派生标签（行 648-767，23 条，顺序即语义）

    private static let nomzSuffixes = ["tion", "tions", "ment", "ments", "ness", "nesses", "ity", "ities"]

    private func pass8(_ s: inout TagStream) {
        for j in 0..<s.count {
            if c.listAmp.matches(s, j) { s.setTag(j, "AMP") }                // P8.1 行651
            if c.listDwnt.matches(s, j) { s.setTag(j, "DWNT") }              // P8.2 行657

            if s.tp(j, "NN"), let w = s.w(j),                                // P8.3 行662
               Self.nomzSuffixes.contains(where: { w.hasSuffix($0) }) {
                s.setTag(j, "NOMZ")
            }
            if s.tp(j, "NN"), let t = s.at(j) {                              // P8.4 行667
                let run = (t.surface + "_" + t.tag).maxWordRun
                if (t.surface.hasSuffix("ing") && run >= 10)
                    || (t.surface.hasSuffix("ings") && run >= 11) {
                    s.setTag(j, "GER")
                }
            }
            if s.tp(j, "NNS") || s.tp(j, "NNP") { s.setTag(j, "NN") }         // P8.5 行673
            if s.tp(j, "JJS") || s.tp(j, "JJR") { s.setTag(j, "JJ") }         // P8.6 行678
            if s.tp(j, "RBS") || s.tp(j, "RBR") || s.tp(j, "WRB") { s.setTag(j, "RB") } // P8.7 行683
            if s.tp(j, "VBP") || s.tp(j, "VBZ") { s.setTag(j, "VPRT") }       // P8.8 行688

            if c.listFpp1.matches(s, j) { s.setTag(j, "FPP1") }               // P8.9 行693
            if c.listSpp2.matches(s, j) { s.setTag(j, "SPP2") }               // P8.10 行698
            if c.listTpp3.matches(s, j) { s.setTag(j, "TPP3") }               // P8.11 行703
            if c.listPit.matches(s, j) { s.setTag(j, "PIT") }                 // P8.12 行708

            if c.listCaus.matches(s, j) { s.setTag(j, "CAUS") }               // P8.13 行713
            if c.listConc.matches(s, j) { s.setTag(j, "CONC") }               // P8.14 行718
            if c.listCond.matches(s, j) { s.setTag(j, "COND") }               // P8.15 行723
            if c.listPomd.matches(s, j) { s.setTag(j, "POMD") }               // P8.16 行728
            if c.listNemd.matches(s, j) { s.setTag(j, "NEMD") }               // P8.17 行733

            // P8.18 行738
            if let w = s.w(j), let tag = s.tag(j) {
                let md = tag == "MD"
                if (w == "will" && md) || (w.hasSuffix("ll") && md) || (w == "wo" && md)
                    || w == "would" || w == "shall" || (w == "sha" && md) || (w == "'d" && md) {
                    s.setTag(j, "PRMD")
                }
            }

            if c.lexPublic.matches(s, j) { s.add(.pubv, at: j) }              // P8.19 行743
            if c.lexPrivate.matches(s, j) { s.add(.priv, at: j) }             // P8.20 行748
            if c.lexSuasive.matches(s, j) { s.add(.suav, at: j) }             // P8.21 行753
            if c.listSmp.matches(s, j) { s.add(.smp, at: j) }                 // P8.22 行758

            // P8.23 行763 缩写
            if let t = s.at(j) {
                let sfc = t.surface
                if (sfc.contains("'") && t.tag.hasPrefix("V"))
                    || (sfc == "n't" && t.tag == "XX0")
                    || sfc.contains("'ll") || sfc.contains("'d") {
                    s.add(.cont, at: j)
                }
            }
        }
    }
}
