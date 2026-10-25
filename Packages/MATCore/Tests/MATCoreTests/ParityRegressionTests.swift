import XCTest
@testable import MATCore

/// 这一组全部来自 2026-10-22 那次「Windows 原版 ground truth」比对。
/// 每条对应一个真实踩过的坑，改动前先读注释——它们看起来都像"可以简化"的地方。
final class ParityRegressionTests: XCTestCase {

    // MARK: - 取整口径

    /// 精确的 .5：Windows 远离零，macOS 向偶数。
    /// 原版只在 Windows 上跑，所以必须按 Windows 来。
    func testExactHalfRoundsAwayFromZero() {
        XCTAssertEqual(Perl.f2(-0.625), "-0.63")   // CONC：(0 − 0.05)/0.08
        XCTAssertEqual(Perl.f2(3.125), "3.13")     // 2/64 词 = 3.125
        XCTAssertEqual(Perl.f2(2.125), "2.13")     // TO
        XCTAssertEqual(Perl.f2(5.625), "5.63")     // CONJ
        XCTAssertEqual(Perl.f2(-6.125), "-6.13")   // TTR：(77/4 − 51.1)/5.2
    }

    /// **不是** .5 的情况：`-1.775` 的精确二进制值是 `-1.77499999999999991…`，
    /// printf 看精确展开，给 -1.77。用 `x*100` 判边界会把它舍成 -177.5 而误判成 .5。
    func testNonTieWithTrailingNineIsNotRoundedUp() {
        XCTAssertEqual(Perl.f2(-1.775), "-1.77")   // AWL：t01_dialogue
        XCTAssertEqual(Perl.f2(1.005), "1.00")     // 经典案例：1.00499999…
        XCTAssertEqual(Perl.round2(-1.775), -1.77)
    }

    func testTrailingZerosAreKept() {
        XCTAssertEqual(Perl.f2(374), "374.00")
        XCTAssertEqual(Perl.f2(0.1 + 0.2), "0.30")
    }

    // MARK: - `\b` 词边界

    /// `$have = "have_|has_|'ve_|had_|having_|hath_"`，用于 `/\b($have)/i`。
    ///
    /// `'ve_VBP`（`We 've been waiting` 的 `'ve` 是独立 token）**不**匹配：
    /// 撇号在串首、前面没有字边界。曾经因为「去一个非单词字符再查表」而误命中，
    /// 结果 `'ve` 多了一个 `[PEAS]`，D2 被推高。
    func testApostropheInitialEntryDoesNotMatchAtStringStart() {
        let have = Lexicon(fragment: "have_|has_|'ve_|had_|having_|hath_")
        XCTAssertTrue(have.matches(Token(surface: "have", tag: "VBP")))
        XCTAssertTrue(have.matches(Token(surface: "has", tag: "VBZ")))
        XCTAssertFalse(have.matches(Token(surface: "'ve", tag: "VBP")))
        // 撇号前面是单词字符时，边界成立 → 命中
        XCTAssertTrue(have.matches(Token(surface: "we've", tag: "VBP")))
    }

    /// 反过来：词表项以单词字符开头时，撇号后面的位置**是**边界。
    /// `\bs_VBZ` 能命中 `'s_VBZ`——否则 `'s` 拿不到 `[BEMA]`。
    func testCliticSurfaceStillMatches() {
        let be = Lexicon(fragment: "be_|is_|are_|was_|were_|am_|s_|re_|m_")
        XCTAssertTrue(be.matches(Token(surface: "'s", tag: "VBZ")))
        XCTAssertTrue(be.matches(Token(surface: "it's", tag: "VBZ")))
    }

    // MARK: - 体裁参考区间

    /// `@dimN_max/min` 是 Chart::ErrorBars 的**距离**，数组里出现负数（如 `@dim1_min = -9.5`）
    /// 也是往下拉 9.5，不是往上。原版 PNG 里 Prepared speeches 就是从 2.2 拉到 -7.3 与 14.8。
    /// 抽常量时必须 `mean ± abs(err)`，否则会得到 11.7~14.8 这种完全错的短棒。
    func testGenreRangesUseAbsoluteOffsets() {
        let g = Catalog.shared.genres
        func genre(_ name: String) -> GenreRef? { g.first { $0.name == name } }

        XCTAssertEqual(genre("Prepared speeches")!.values[0], 2.2, accuracy: 1e-9)
        XCTAssertEqual(genre("Prepared speeches")!.low[0], -7.3, accuracy: 1e-9)
        XCTAssertEqual(genre("Prepared speeches")!.high[0], 14.8, accuracy: 1e-9)

        // 另外三条在源码里同样是负偏移，曾经全被算错
        XCTAssertEqual(genre("General fiction")!.low[0], -19.6, accuracy: 1e-9)
        XCTAssertEqual(genre("General fiction")!.high[0], 22.3, accuracy: 1e-9)
        XCTAssertEqual(genre("Academic prose")!.low[0], -26.5, accuracy: 1e-9)
        XCTAssertEqual(genre("Academic prose")!.high[0], 7.1, accuracy: 1e-9)

        // 每个区间都必须包住自己的均值
        for ref in g {
            for d in 0..<6 {
                XCTAssertLessThanOrEqual(ref.low[d], ref.values[d], "\(ref.name) D\(d + 1) 下界高于均值")
                XCTAssertGreaterThanOrEqual(ref.high[d], ref.values[d], "\(ref.name) D\(d + 1) 上界低于均值")
            }
        }
    }

    // MARK: - Count: All tags

    /// All-tags 模式的列集是 `sort keys`，所以标点（`.` `:`）排最前、
    /// 而 `[XXX]` 因为 `[`(0x5B) > `Z`(0x5A) 排在所有大写键之后。
    /// 逗号在计数时被改名成 `COMMA`。
    func testAllTagsModeColumns() {
        let toks = Token.parseStream(
            "The_DT report_NN was_VBD [BYPA] written_VBN ,_, he_PRP said_VBD ._.")
        let r = Analyzer().analyze([("x", toks)], corpusName: "x")
        let csv = Reports.statistics(r, allTags: true)
        let header = csv.split(separator: "\n").first.map(String.init) ?? ""

        XCTAssertTrue(header.hasPrefix("Filename,Tokens,AWL,TTR,."), "标点列应排在最前：\(header)")
        XCTAssertTrue(header.contains(",COMMA,"), "逗号应改名成 COMMA")
        XCTAssertTrue(header.contains(",VBD,"))
        XCTAssertTrue(header.contains(",[BYPA],"))
        XCTAssertFalse(header.contains(",MD,"), "All tags 模式排除 _MD")
        XCTAssertFalse(header.contains(",NULL,"), "All tags 模式排除 _NULL")
    }

    /// 默认（Only VASW tags）不该出现标点列
    func testBiberModeHasNoPunctuationColumns() {
        let toks = Token.parseStream("The_DT report_NN was_VBD [BYPA] written_VBN ._.")
        let r = Analyzer().analyze([("x", toks)], corpusName: "x")
        let header = Reports.statistics(r).split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(header.hasPrefix("Filename,Tokens,AWL,TTR,AMP,"))
        XCTAssertFalse(header.contains(",COMMA,"))
        XCTAssertFalse(header.contains(",.,"))
    }
}
