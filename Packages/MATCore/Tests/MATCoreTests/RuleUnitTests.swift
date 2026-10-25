import XCTest
@testable import MATCore

/// 逐条钉住那些「读代码看不出来、只有 golden 会抓」的行为。
/// 每个用例都对应 Docs/RuleTable.md 里的一条口径（D1–D7）或一个规则 id。
final class RuleUnitTests: XCTestCase {

    private let engine = RuleEngine()
    private let analyzer = Analyzer()

    /// 从紧凑写法直接造一条流：`"The_DT book_NN ._."`
    private func tokens(_ s: String) -> [Token] { Token.parseStream(s) }
    private func annotate(_ s: String) -> [Token] { engine.annotate(tokens(s)) }
    private func find(_ ts: [Token], _ surface: String) -> Token? {
        ts.first { $0.surface.lowerASCII == surface }
    }

    // MARK: D1 · 负索引回绕

    func testNegativeIndexWrapsToEnd() {
        var s = TagStream(tokens("a_X b_Y c_Z"))
        XCTAssertEqual(s.at(-1)?.surface, "c")
        XCTAssertEqual(s.at(-2)?.surface, "b")
        XCTAssertEqual(s.at(-4)?.surface, "c", "Perl 的 -4 % 3 = -1，仍指向末尾")
        XCTAssertNil(s.at(3), "越界是 undef")
        XCTAssertNil(s.at(99))
        // 写操作**不**回绕（规则里没有 `$word[-1] = ...` 这种写法），越界一律忽略
        s.setTag(-1, "Q"); XCTAssertEqual(s.at(2)?.tag, "Z")
        s.setTag(3, "Q"); XCTAssertEqual(s.count, 3)
    }

    /// 09_negative_index 语料的核心：句首 token 的 `$word[$j-2]` 回绕到文末的 there_EX，
    /// 于是 BEMA 的守卫 `$word[$j-2] !~ /_EX/` 失败，Was_VBD 拿不到 [BEMA]。
    func testNegativeIndexChangesRuleOutcome() {
        let withEX = annotate("Was_VBD the_DT report_NN finished_VBN ?_. The_DT papers_NNS were_VBD there_EX by_IN")
        XCTAssertEqual(find(withEX, "was")?.features, [],
                       "文末第二个词是 there_EX，句首 Was 不应有 BEMA")

        let clean = annotate("Was_VBD the_DT report_NN finished_VBN ?_. The_DT papers_NNS were_VBD fine_JJ by_IN")
        XCTAssertEqual(find(clean, "was")?.features, [.bema],
                       "同样的句首 Was，文末不是 EX 时应当拿到 BEMA")
    }

    // MARK: D6 · 词边界允许一个前置非单词字符

    func testLexiconMatchesClitic() {
        let be = Catalog.shared.lexBe
        XCTAssertTrue(be.matches(Token(surface: "'s", tag: "VBZ")))
        XCTAssertTrue(be.matches(Token(surface: "'re", tag: "VBP")))
        XCTAssertFalse(be.matches(Token(surface: "'s", tag: "POS")), "s_VBZ 只认 VBZ")
        XCTAssertFalse(be.matches(Token(surface: "his", tag: "PRP$")), "his 不能因为后缀是 is 就命中")
    }

    /// `'s` 走完 P3 应当拿到 [BEMA]，并且后面的形容词变 PRED（golden 04_contraction）
    func testCliticGetsBEMAAndPredicateAdjective() {
        let ts = annotate("She_PRP 's_VBZ not_RB happy_JJ ._.")
        let clitic = ts.first { $0.surface == "'s" }
        XCTAssertEqual(clitic?.features, [.cont, .bema], "倒序：[CONT] 后加所以在左")
        XCTAssertEqual(find(ts, "happy")?.tag, "PRED")
    }

    // MARK: D7 · 无锚点子串匹配

    /// 原式 `/is_/` 是子串匹配，`this_DT` 里含 `is_` → that 变 DEMP。
    /// 这条不是笔误修正，是原版行为，必须保留。
    func testDemonstrativePronounMatchesBySubstring() {
        let ts = annotate("I_PRP think_VBP that_IN this_DT is_VBZ wrong_JJ ._.")
        XCTAssertEqual(find(ts, "that")?.tag, "DEMP", "this_DT 含 is_ → that 走 P4.2")
        XCTAssertEqual(find(ts, "think")?.features, [.priv, .thatd])
    }

    // MARK: P2.3 / P2.5 · INPR 被 QUPR 覆盖

    func testQuantifierPronounOverridesIndefinitePronoun() {
        XCTAssertEqual(find(annotate("Everybody_PRP came_VBD ._."), "everybody")?.tag, "QUPR")
        XCTAssertEqual(find(annotate("Nobody_PRP came_VBD ._."), "nobody")?.tag, "INPR")
    }

    // MARK: P3.22 / P3.23 · PASS 与 BYPA 互斥

    func testPassiveVersusByPassive() {
        let ts = annotate("The_DT report_NN was_VBD written_VBN by_IN them_PRP ._.")
        XCTAssertEqual(find(ts, "written")?.features, [.pubv])
        XCTAssertEqual(find(ts, "was")?.features, [.bypa], "后面是 by → BYPA")

        let ts2 = annotate("The_DT door_NN was_VBD opened_VBN ._.")
        XCTAssertEqual(find(ts2, "was")?.features, [.pass])
    }

    // MARK: TSUB 被 TOBJ 覆盖

    func testTsubIsOverwrittenByTobj() {
        let unstable = annotate("The_DT idea_NN that_IN he_PRP lied_VBD ._.")
        XCTAssertEqual(find(unstable, "that")?.tag, "TOBJ", "后接代词 → 被 P3.47 覆盖")

        let stable = annotate("The_DT claim_NN that_IN matters_VBZ ._.")
        XCTAssertEqual(find(stable, "that")?.tag, "TSUB", "后接动词时 TSUB 得以保留")
    }

    // MARK: 计数 · TTR 的 undef 缺陷

    func testShortTextTTRAddsPhantomType() {
        // 10 个互不相同的有效词，窗口 400 → 原版会多算一个 "" 类型
        let ts = tokens("A_DT small_JJ corpus_NN is_VBZ useful_JJ It_PRP tests_VBZ the_DT short_JJ path_NN ._.")
        let p = FeatureCounter().count(ts, ttrWindow: 400)
        XCTAssertEqual(p.tokens, 10)
        XCTAssertEqual(p.typesInWindow, 11, "distinct(10) + undef 的 1 个假类型")
    }

    func testFullWindowTTRHasNoPhantomType() {
        let words = (0..<50).map { "w\($0)_NN" }.joined(separator: " ")
        let p = FeatureCounter().count(tokens(words), ttrWindow: 20)
        XCTAssertEqual(p.typesInWindow, 20, "窗口小于样本数时不该出现 +1")
    }

    // MARK: 数值格式 · 三个不同口径

    func testPerlNumberFormatting() {
        XCTAssertEqual(Perl.f2(14.285), "14.29")
        XCTAssertEqual(Perl.f2(1), "1.00")
        XCTAssertEqual(Perl.num(1), "1", "%.15g 不补小数点")
        XCTAssertEqual(Perl.num(5.551115123125783e-16), "5.55111512312578e-16")
        XCTAssertEqual(Perl.num(0.00999999999999979), "0.00999999999999979")
    }

    func testNormalizationIsPerHundredTokens() {
        // 3 个有效词里有 1 个 NN → 33.33，不是 333.33（per-1000）
        let ts = tokens("a_DT book_NN c_JJ ._.")
        let p = FeatureCounter().count(ts, ttrWindow: 400)
        let (freq, _) = Scorer().score(p, ttrWindow: 400)
        XCTAssertEqual(freq["NN"], 33.33)
    }

    /// 维度分只求和、不再取整：所以可能出现 15 位有效数字的尾巴
    func testDimensionSumIsNotRounded() {
        let z: [String: Double] = ["[WHOBJ]": 1.0 / 3.0, "[WHSUB]": 0.0, "PHC": 0.0, "NOMZ": 0.0,
                                   "TIME": 0.0, "PLACE": 0.0, "RB": 0.0]
        let d3 = Scorer().dimensions(z, clamp: false)[3]!
        XCTAssertEqual(Perl.f2(d3), "0.33", "两位小数口径")
        XCTAssertEqual(Perl.num(d3), "0.333333333333333",
                       "维度列走 %.15g，不做 round2 —— 与 Statistics 列的口径不同")
    }

    func testClampLimitsEachZScore() {
        let z: [String: Double] = ["THVC": 370000, "DEMO": -8]
        XCTAssertEqual(Scorer().dimensions(z, clamp: true)[6]!, 0.0, "+5 + (−5) = 0")
        XCTAssertEqual(Scorer().dimensions(z, clamp: false)[6]!, 369992.0)
    }

    // MARK: 分类

    func testTextTypeUsesEuclideanOverD1ToD5() {
        let scorer = Scorer()
        // 落在 Learned exposition (-20,-2,5,-3,2) 上
        let dims: [Int: Double] = [1: -20, 2: -2, 3: 5, 4: -3, 5: 2, 6: 0]
        XCTAssertEqual(scorer.textType(dims), "Learned exposition")
        // D6 不参与：改 D6 不影响结论
        var dims2 = dims; dims2[6] = 999
        XCTAssertEqual(scorer.textType(dims2), "Learned exposition")
    }

    // MARK: 预处理（curly_correct）

    func testCurlyQuotesAreNormalized() {
        let curly = "I don\u{2019}t know \u{201C}why\u{201D}."
        XCTAssertTrue(TextPreparer.needsNormalization(curly))
        XCTAssertEqual(TextPreparer.normalize(curly), "I don't know \"why\".")
        XCTAssertFalse(TextPreparer.needsNormalization("plain \"text\""), "ASCII 引号不该被再处理")
    }

    // MARK: 常量表

    func testCatalogShape() {
        let c = Catalog.shared
        XCTAssertEqual(c.featureOrder.count, 65)
        XCTAssertEqual(c.tagFeatures.count, 41)
        XCTAssertEqual(c.means.count, 67)
        XCTAssertEqual(c.sds.count, 67)
        XCTAssertEqual(c.textTypes.count, 8)
        XCTAssertEqual(c.genres.count, 8)
        XCTAssertEqual(c.means["NN"], 18.05)
        XCTAssertEqual(c.sds["[SPIN]"], 0.00001)
    }

    /// JSON 里的括号型特征必须和 Bracket 枚举一一对应，否则计数会静默丢特征
    func testBracketFeatureIDsMatchEnum() {
        let fromJSON = Set(Catalog.shared.featureOrder.filter { $0.hasPrefix("[") })
        let fromEnum = Set(Bracket.allCases.map(\.rawValue))
        XCTAssertEqual(fromJSON, fromEnum)
    }
}
