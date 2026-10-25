import Foundation

// MARK: - 描述统计与假设检验
//
// 只做 UI 需要的部分：给「两个语料库某维度/某特征是否有差异」提供判断依据，
// 并且用正态性检验回答「该用 t 检验还是 Mann–Whitney U」。
//
// 这些数字不参与 MAT 的分数计算，所以不需要和 Perl 逐字节对齐；
// 但算法本身必须正确，否则会把人引向错误的检验。

public enum Stats {

    // MARK: 基础分布函数

    /// 标准正态 CDF
    public static func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / 2.0.squareRoot()))
    }

    public static func normalPDF(_ x: Double, mean: Double = 0, sd: Double = 1) -> Double {
        guard sd > 0 else { return 0 }
        let z = (x - mean) / sd
        return exp(-0.5 * z * z) / (sd * (2 * Double.pi).squareRoot())
    }

    /// 正则化不完全 Beta 函数 I_x(a,b)（连分式，Numerical Recipes 6.4）
    public static func incompleteBeta(_ a: Double, _ b: Double, _ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let lbeta = lgamma(a + b) - lgamma(a) - lgamma(b)
        let front = exp(lbeta + a * log(x) + b * log(1 - x))
        if x < (a + 1) / (a + b + 2) {
            return front * betaCF(a, b, x) / a
        }
        return 1 - front * betaCF(b, a, 1 - x) / b
    }

    private static func betaCF(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let tiny = 1e-30
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...200 {
            let m2 = Double(2 * m)
            var aa = Double(m) * (b - Double(m)) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            aa = -(a + Double(m)) * (qab + Double(m)) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            let del = d * c
            h *= del
            if abs(del - 1) < 1e-12 { break }
        }
        return h
    }

    /// 双尾 Student t 的 p 值
    public static func tTwoSidedP(_ t: Double, df: Double) -> Double {
        guard df > 0 else { return .nan }
        return incompleteBeta(df / 2, 0.5, df / (df + t * t))
    }

    // MARK: 描述统计

    public struct Summary: Sendable, Equatable {
        public let n: Int
        public let mean: Double
        public let sd: Double          // 样本标准差（n-1）
        public let median: Double
        public let min: Double
        public let max: Double
        public let skewness: Double    // 偏度（总体公式）
        public let kurtosis: Double    // 超额峰度
        public let sem: Double         // 均值标准误

        public var isUsable: Bool { n >= 2 && sd.isFinite && sd > 0 }
    }

    public static func describe(_ xs: [Double]) -> Summary {
        let n = xs.count
        guard n > 0 else {
            return Summary(n: 0, mean: .nan, sd: .nan, median: .nan, min: .nan,
                           max: .nan, skewness: .nan, kurtosis: .nan, sem: .nan)
        }
        let mean = xs.reduce(0, +) / Double(n)
        let m2 = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let sd = n > 1 ? (m2 / Double(n - 1)).squareRoot() : 0
        let sorted = xs.sorted()
        let median = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2

        var skew = 0.0, kurt = 0.0
        if n > 2, m2 > 0 {
            let m3 = xs.reduce(0) { $0 + pow($1 - mean, 3) }
            let m4 = xs.reduce(0) { $0 + pow($1 - mean, 4) }
            let s3 = pow(m2 / Double(n), 1.5)
            skew = s3 > 0 ? (m3 / Double(n)) / s3 : 0
            kurt = (m4 / Double(n)) / pow(m2 / Double(n), 2) - 3
        }
        return Summary(n: n, mean: mean, sd: sd, median: median,
                       min: sorted.first!, max: sorted.last!,
                       skewness: skew, kurtosis: kurt,
                       sem: n > 1 ? sd / Double(n).squareRoot() : .nan)
    }

    // MARK: 正态性

    /// Shapiro–Wilk（Royston 1995 / AS R94）。n < 3 或 n > 5000 时返回 nil。
    public struct Normality: Sendable {
        public let test: String
        public let statistic: Double
        public let p: Double
        public var isNormal: Bool { p >= 0.05 }
    }

    public static func shapiroWilk(_ xs: [Double]) -> Normality? {
        let n = xs.count
        guard n >= 4, n <= 5000 else { return nil }
        let x = xs.sorted()
        let mean = x.reduce(0, +) / Double(n)

        // m_i = Φ⁻¹((i − 0.375) / (n + 0.25))，i = 1…n
        var m = [Double](repeating: 0, count: n)
        for i in 1...n {
            m[i - 1] = inverseNormalCDF((Double(i) - 0.375) / (Double(n) + 0.25))
        }
        let mSum = m.reduce(0) { $0 + $1 * $1 }
        guard mSum > 0 else { return nil }
        let mNorm = m.map { $0 / mSum.squareRoot() }        // 归一化，Σm² = 1

        // 末端两个系数用 Royston 的多项式近似
        func coeff(_ c: Double) -> Double {
            -2.706056 * pow(c, 5) + 4.434685 * pow(c, 4) - 2.071190 * pow(c, 3)
            - 0.147981 * pow(c, 2) + 0.221157 * c + c
        }
        func coeff2(_ c: Double) -> Double {
            -3.582633 * pow(c, 5) + 5.682633 * pow(c, 4) - 1.752461 * pow(c, 3)
            - 0.293762 * pow(c, 2) + 0.042981 * c + c
        }

        var a = [Double](repeating: 0, count: n)
        let an = coeff(mNorm[n - 1])
        a[n - 1] = an

        if n > 5 {
            let an1 = coeff2(mNorm[n - 2])
            a[n - 2] = an1
            let phi = (1 - 2 * mNorm[n - 1] * mNorm[n - 1] - 2 * mNorm[n - 2] * mNorm[n - 2])
                    / (1 - 2 * an * an - 2 * an1 * an1)
            for i in 1..<(n - 2) { a[i] = mNorm[i] / phi.squareRoot() }
            // 对称关系：a_1 = −a_n，a_2 = −a_{n−1}（AS R94）
            a[0] = -an
            a[1] = -an1
        } else {
            let phi = (1 - 2 * mNorm[n - 1] * mNorm[n - 1]) / (1 - 2 * an * an)
            for i in 1..<(n - 1) { a[i] = mNorm[i] / phi.squareRoot() }
            a[0] = -an
        }

        let num = zip(a, x).reduce(0) { $0 + $1.0 * $1.1 }
        let den = x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        guard den > 0 else { return nil }
        let w = min(num * num / den, 0.999999)
        return Normality(test: "Shapiro–Wilk", statistic: w, p: shapiroP(w: w, n: n))
    }

    private static func shapiroP(w: Double, n: Int) -> Double {
        let ln = log(Double(n))
        if n <= 11 {
            let gamma = -2.273 + 0.459 * Double(n)
            let ww = -log(gamma - log(1 - w))
            let mu = 0.5440 - 0.39978 * Double(n) + 0.025054 * Double(n * n)
                   - 0.0006714 * Double(n * n * n)
            let sigma = exp(1.3822 - 0.77857 * Double(n) + 0.062767 * Double(n * n)
                            - 0.0020322 * Double(n * n * n))
            let z = (ww - mu) / sigma
            return 1 - normalCDF(z)
        }
        let ww = log(1 - w)
        let mu = -1.5861 - 0.31082 * ln - 0.083751 * ln * ln + 0.0038915 * pow(ln, 3)
        let sigma = exp(-0.4803 - 0.082676 * ln + 0.0030302 * ln * ln)
        let z = (ww - mu) / sigma
        return 1 - normalCDF(z)
    }

    /// Φ⁻¹（Acklam 近似，误差 < 1.15e-9）
    public static func inverseNormalCDF(_ p: Double) -> Double {
        if p <= 0 { return -.infinity }
        if p >= 1 { return .infinity }
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                 3.754408661907416e+00]
        let plow = 0.02425
        if p < plow {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                 / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > 1 - plow {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                  / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
             / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }

    // MARK: 两组比较

    public struct WelchResult: Sendable {
        public let t: Double
        public let df: Double
        public let p: Double
        public let meanDiff: Double
        public let cohensD: Double
        public let se: Double
        public var isSignificant: Bool { p < 0.05 }

        /// 差值的 95% 置信区间（Welch）
        public var ci95: (low: Double, high: Double) {
            let tc = Stats.tCritical(df: df, alpha: 0.05)
            return (meanDiff - tc * se, meanDiff + tc * se)
        }
    }

    public static func welchT(_ a: [Double], _ b: [Double]) -> WelchResult? {
        let sa = describe(a), sb = describe(b)
        guard sa.isUsable, sb.isUsable else { return nil }
        let va = sa.sd * sa.sd / Double(sa.n)
        let vb = sb.sd * sb.sd / Double(sb.n)
        let se = (va + vb).squareRoot()
        guard se > 0 else { return nil }
        let t = (sa.mean - sb.mean) / se
        let df = (va + vb) * (va + vb) / (va * va / Double(sa.n - 1) + vb * vb / Double(sb.n - 1))
        // Cohen's d（合并标准差）
        let pooled = (((Double(sa.n - 1) * sa.sd * sa.sd + Double(sb.n - 1) * sb.sd * sb.sd)
                      / Double(sa.n + sb.n - 2))).squareRoot()
        return WelchResult(t: t, df: df, p: tTwoSidedP(t, df: df),
                           meanDiff: sa.mean - sb.mean,
                           cohensD: pooled > 0 ? (sa.mean - sb.mean) / pooled : 0,
                           se: se)
    }

    public struct MannWhitneyResult: Sendable {
        public let u: Double
        public let z: Double
        public let p: Double
        public let rankBiserial: Double   // 效应量 r = 1 - 2U/(n1 n2)
        public var isSignificant: Bool { p < 0.05 }
    }

    /// Mann–Whitney U（正态近似 + 结值校正 + 连续性校正）。样本很小，仅供参考。
    public static func mannWhitneyU(_ a: [Double], _ b: [Double]) -> MannWhitneyResult? {
        let n1 = a.count, n2 = b.count
        guard n1 >= 2, n2 >= 2 else { return nil }
        let all = (a.map { ($0, 0) } + b.map { ($0, 1) }).sorted { $0.0 < $1.0 }
        var ranks = [Double](repeating: 0, count: all.count)
        var i = 0
        var tieCorrection = 0.0
        while i < all.count {
            var j = i
            while j + 1 < all.count && all[j + 1].0 == all[i].0 { j += 1 }
            let r = Double(i + j + 2) / 2      // 平均秩（1-based）
            for k in i...j { ranks[k] = r }
            let t = Double(j - i + 1)
            if t > 1 { tieCorrection += t * t * t - t }
            i = j + 1
        }
        let r1 = zip(all, ranks).reduce(0.0) { $0 + ($1.0.1 == 0 ? $1.1 : 0) }
        let u1 = r1 - Double(n1 * (n1 + 1)) / 2
        let u2 = Double(n1 * n2) - u1
        let u = min(u1, u2)
        let mu = Double(n1 * n2) / 2
        let n = Double(n1 + n2)
        let sigma2 = Double(n1 * n2) / 12 * ((n + 1) - tieCorrection / (n * (n - 1)))
        guard sigma2 > 0 else { return nil }
        let sigma = sigma2.squareRoot()
        let z = (u - mu + 0.5) / sigma                 // 连续性校正（U 偏小方向）
        let p = 2 * (1 - normalCDF(abs(z)))
        return MannWhitneyResult(u: u, z: z, p: min(1, p),
                                 rankBiserial: 1 - 2 * u / Double(n1 * n2))
    }

    // MARK: 多重比较

    /// Benjamini–Hochberg 校正后的 q 值（与输入顺序一一对应）。
    ///
    /// 65 个特征各做一次检验，不校正的话按 α=0.05 会有 3 个左右假阳性。
    /// q 值的含义：把这一条判为显著时，假阳性比例的期望上限。
    public static func benjaminiHochberg(_ p: [Double]) -> [Double] {
        let n = p.count
        guard n > 0 else { return [] }
        let order = (0..<n).sorted { p[$0] < p[$1] }
        var q = [Double](repeating: 1, count: n)
        var running = 1.0
        for rank in stride(from: n, through: 1, by: -1) {
            let i = order[rank - 1]
            let value = min(1, p[i] * Double(n) / Double(rank))
            running = min(running, value)
            q[i] = running
        }
        return q
    }

    /// Bonferroni–Holm（逐步向下，比 BH 保守、比 Bonferroni 有功效）
    ///
    /// 与 BH 的区别：BH 控制「假阳性比例」，Holm 控制「至少出现一次假阳性的概率」。
    /// 小样本、检验数不多时，Holm 的结果更容易被审稿人接受。
    public static func holm(_ p: [Double]) -> [Double] {
        let n = p.count
        guard n > 0 else { return [] }
        let order = (0..<n).sorted { p[$0] < p[$1] }
        var q = [Double](repeating: 1, count: n)
        var running = 0.0
        for rank in 1...n {
            let i = order[rank - 1]
            let value = min(1, p[i] * Double(n - rank + 1))
            running = max(running, value)
            q[i] = running
        }
        return q
    }

    /// 双尾 t 的临界值（二分法，精度 1e-6）
    public static func tCritical(df: Double, alpha: Double = 0.05) -> Double {
        guard df > 0 else { return .nan }
        var lo = 0.0, hi = 200.0
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if tTwoSidedP(mid, df: df) > alpha { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    // MARK: 画图用

    public struct Bin: Identifiable, Sendable {
        public let id = UUID()
        public let lower: Double
        public let upper: Double
        public let count: Int
        public var mid: Double { (lower + upper) / 2 }
    }

    /// Freedman–Diaconis 直方图（最多 14 个箱，便于阅读）
    public static func histogram(_ xs: [Double], desiredBins: Int = 10) -> (bins: [Bin], width: Double) {
        guard let lo = xs.min(), let hi = xs.max(), hi > lo else {
            return ([Bin(lower: xs.first ?? 0, upper: (xs.first ?? 0) + 1, count: xs.count)], 1)
        }
        let n = Double(xs.count)
        let sorted = xs.sorted()
        let q1 = sorted[max(0, Int(Double(n) * 0.25) - 1)]
        let q3 = sorted[min(sorted.count - 1, Int(Double(n) * 0.75))]
        let iqr = q3 - q1
        var width = iqr > 0 ? 2 * iqr / cbrt(n) : (hi - lo) / 8
        if width <= 0 { width = (hi - lo) / 8 }
        var count = Int(((hi - lo) / width).rounded(.up))
        count = max(3, min(desiredBins, count))
        width = (hi - lo) / Double(count)
        var bins = (0..<count).map {
            Bin(lower: lo + Double($0) * width, upper: lo + Double($0 + 1) * width, count: 0)
        }
        for x in xs {
            var idx = Int((x - lo) / width)
            if idx >= count { idx = count - 1 }
            if idx < 0 { idx = 0 }
            let old = bins[idx]
            bins[idx] = Bin(lower: old.lower, upper: old.upper, count: old.count + 1)
        }
        return (bins, width)
    }

    /// 高斯核密度估计（Silverman 带宽）
    public static func kde(_ xs: [Double], at points: [Double]) -> [Double] {
        let s = describe(xs)
        guard s.n >= 2, s.sd > 0 else { return points.map { _ in 0 } }
        let n = Double(s.n)
        let iqr = (xs.sorted()[Int(n * 0.75)] - xs.sorted()[Int(n * 0.25)])
        let sigma = min(s.sd, iqr > 0 ? iqr / 1.34 : s.sd)
        let h = 0.9 * sigma * pow(n, -0.2)
        guard h > 0 else { return points.map { _ in 0 } }
        return points.map { p in
            let sum = xs.reduce(0.0) { $0 + exp(-0.5 * pow((p - $1) / h, 2)) }
            return sum / (n * h * (2 * Double.pi).squareRoot())
        }
    }

    /// 正态分位数（用于 Q-Q 图）
    public static func qq(_ xs: [Double]) -> [(theoretical: Double, sample: Double)] {
        let sorted = xs.sorted()
        let n = Double(sorted.count)
        return sorted.enumerated().map { i, x in
            (inverseNormalCDF((Double(i) + 0.5) / n), x)
        }
    }
}
