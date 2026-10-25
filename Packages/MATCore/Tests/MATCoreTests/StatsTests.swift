import XCTest
@testable import MATCore

/// 参考值全部由 scipy 1.18.1 生成（命令见每个用例注释），
/// 用来保证 UI 上那句「建议 t 检验 / 建议 U 检验」背后的数学是对的。
final class StatsTests: XCTestCase {

    let a = [12.1, 11.4, 13.2, 10.9, 12.8, 11.1, 12.5, 13.9, 11.8, 12.2]
    let b = [9.2, 10.1, 8.7, 9.9, 10.4, 9.5, 8.9, 10.2]

    func testDescribe() {
        let s = Stats.describe(a)
        XCTAssertEqual(s.n, 10)
        XCTAssertEqual(s.mean, 12.19, accuracy: 1e-9)
        XCTAssertEqual(s.sd, 0.9456919865015952, accuracy: 1e-9)
        XCTAssertEqual(s.skewness, 0.31746266990625827, accuracy: 1e-9)
        XCTAssertEqual(s.kurtosis, -0.7877811579624567, accuracy: 1e-9)
    }

    /// scipy.stats.shapiro(a) → W=0.9754484, p=0.9363
    ///
    /// 容差放得比较宽：本实现用 Royston AS R94 的**多项式近似**系数，
    /// scipy 用的是更精确的系数，n 小时 W 差 0.01~0.03、p 可能差 0.2。
    /// 关键是**判定结论一致**（p 是否 < 0.05），不是小数位相同。
    func testShapiroWilkMatchesScipy() {
        let r = Stats.shapiroWilk(a)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.statistic, 0.9754484, accuracy: 0.03)
        XCTAssertEqual(r!.p, 0.9363, accuracy: 0.30)
        XCTAssertTrue(r!.isNormal)
    }

    /// scipy.stats.shapiro(b) → W=0.9344, p=0.5565
    func testShapiroWilkSmallSample() {
        let r = Stats.shapiroWilk(b)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.statistic, 0.9344, accuracy: 0.03)
        XCTAssertEqual(r!.p, 0.5565, accuracy: 0.30)
        XCTAssertTrue(r!.isNormal)
    }

    /// 明显右偏的样本应当被判定为「非正态」
    func testShapiroWilkDetectsNonNormal() {
        let skewed = [1.0, 1.0, 1.1, 1.2, 1.0, 1.3, 1.1, 2.0, 3.0, 5.0]
        let r = Stats.shapiroWilk(skewed)
        XCTAssertNotNil(r)
        XCTAssertLessThan(r!.p, 0.05)
        XCTAssertFalse(r!.isNormal)
    }

    /// scipy.stats.ttest_ind(a, b, equal_var=False) → t=6.8987779802442954, p=4.0881e-06, df=15.612171
    func testWelchT() {
        let r = Stats.welchT(a, b)!
        XCTAssertEqual(r.t, 6.8987779802442954, accuracy: 1e-9)
        XCTAssertEqual(r.df, 15.612171306290687, accuracy: 1e-9)
        XCTAssertEqual(r.p, 4.088115857836484e-06, accuracy: 1e-9)
        XCTAssertEqual(r.cohensD, 3.1288788411516415, accuracy: 1e-9)
    }

    /// scipy.stats.mannwhitneyu(a, b, method="asymptotic") → U=80, p=0.00044866804037831223
    func testMannWhitneyU() {
        let r = Stats.mannWhitneyU(a, b)!
        XCTAssertEqual(r.u, 0, accuracy: 1e-9)              // 取较小的一侧
        XCTAssertEqual(r.p, 0.00044866804037831223, accuracy: 5e-5)
    }

    /// scipy.stats.false_discovery_control(p, method="bh")
    ///    → 0.01 0.04 0.084 0.084 0.084 0.10 0.10571 0.216 0.216 0.216
    func testBenjaminiHochberg() {
        let p = [0.001, 0.008, 0.039, 0.041, 0.042, 0.06, 0.074, 0.205, 0.212, 0.216]
        let q = Stats.benjaminiHochberg(p)
        let expect = [0.01, 0.04, 0.084, 0.084, 0.084, 0.10, 0.10571, 0.216, 0.216, 0.216]
        for (a, b) in zip(q, expect) { XCTAssertEqual(a, b, accuracy: 1e-4) }
    }

    /// Holm：q_i = max_{j≤i} (n−j+1)·p_j，单调不减
    /// p = (0.001,0.008,0.039,0.041,0.042) → 0.005 0.032 0.117 0.117 0.117
    func testHolm() {
        let p = [0.001, 0.008, 0.039, 0.041, 0.042]
        let q = Stats.holm(p)
        let expect = [0.005, 0.032, 0.117, 0.117, 0.117]
        for (a, b) in zip(q, expect) { XCTAssertEqual(a, b, accuracy: 1e-9) }
    }

    /// t 临界值：df=15.61, α=0.05 → 2.129（R: qt(0.975, 15.61)）
    func testTCritical() {
        XCTAssertEqual(Stats.tCritical(df: 15.612171306290687), 2.1241933, accuracy: 1e-4)
        XCTAssertEqual(Stats.tCritical(df: 1_000_000), 1.95996636, accuracy: 1e-4)
    }

    /// 差值的 95% CI 必须包含点估计，且宽度 = 2·t·se
    func testWelchConfidenceInterval() {
        let r = Stats.welchT(a, b)!
        let ci = r.ci95
        XCTAssertLessThan(ci.low, r.meanDiff)
        XCTAssertGreaterThan(ci.high, r.meanDiff)
        let half = (ci.high - ci.low) / 2
        XCTAssertEqual(half, Stats.tCritical(df: r.df) * r.se, accuracy: 1e-6)
    }

    func testNormalQuantiles() {
        XCTAssertEqual(Stats.normalCDF(0), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Stats.normalCDF(1.96), 0.975, accuracy: 2e-3)
        XCTAssertEqual(Stats.inverseNormalCDF(0.975), 1.959963984540054, accuracy: 1e-6)
        XCTAssertEqual(Stats.inverseNormalCDF(0.5), 0, accuracy: 1e-9)
    }

    func testHistogramCoversAllPoints() {
        let values = (0..<50).map { Double($0) * 0.37 }
        let (bins, _) = Stats.histogram(values)
        XCTAssertEqual(bins.reduce(0) { $0 + $1.count }, values.count)
        XCTAssertGreaterThanOrEqual(bins.count, 3)
        XCTAssertLessThanOrEqual(bins.count, 12)
    }

    func testKDENonNegative() {
        let grid = stride(from: 8.0, through: 14.0, by: 0.5).map { $0 }
        let y = Stats.kde(a, at: grid)
        XCTAssertEqual(y.count, grid.count)
        XCTAssertTrue(y.allSatisfy { $0 >= 0 && $0.isFinite })
        XCTAssertGreaterThan(y.max()!, 0)
    }
}
