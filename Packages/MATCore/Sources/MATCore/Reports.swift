import Foundation

// MARK: - 三个 CSV 的逐字节复刻
//
// 格式细节全部来自 count_only.pl / calc_dimensions.pl 的 print 语句：
//   · 每条记录以 "\n" 开头（所以文件末尾没有换行）
//   · 每个字段后面都跟 ","（行尾也跟），唯一例外是 Dimensions 的文本类型字段
//   · 缺失特征打印 "0"，出现过的打印 "%.2f"

public enum Reports {

    /// Statistics_*.csv
    ///
    /// - Parameter allTags: 对应 MAT 主界面的 `Count` 单选。
    ///   `false` = `Only VASW tags`（65 个 Biber 特征，列序固定 = @biber_tags）；
    ///   `true`  = `All tags`（除 `_NULL`/`_MD` 外全部 tag，**列序 = sort keys 字节序**，
    ///   且多出 `.` `:` `COMMA` 这类标点列）。
    public static func statistics(_ r: AnalysisResult,
                                  catalog: Catalog = .shared,
                                  allTags: Bool = false) -> String {
        let keys: [String]
        let value: (DocumentResult, String) -> (raw: Int, freq: Double)

        if allTags {
            var set = Set<String>()
            for d in r.documents { set.formUnion(d.allTags.keys) }
            keys = set.sorted()                       // Perl 的 sort keys = 字节序
            value = { d, k in
                let raw = d.allTags[k] ?? 0
                let f = raw > 0 ? Perl.round2(Double(raw) / Double(max(d.tokens, 1)) * 100) : 0
                return (raw, f)
            }
        } else {
            keys = catalog.featureOrder
            value = { d, k in (d.raw[k] ?? 0, d.freq[k] ?? 0) }
        }

        var out = "Filename,Tokens,AWL,TTR,"
        for f in keys { out += "\(f)," }

        for d in r.documents {
            out += "\n\(d.name),\(d.tokens),\(Perl.f2(d.awl)),\(d.types),"
            for f in keys {
                let (raw, freq) = value(d, f)
                out += raw > 0 ? "\(Perl.f2(freq))," : "0,"
            }
        }
        if let tokens = r.corpusTokens, let awl = r.corpusAWL, let types = r.corpusTypes {
            let n = Double(r.documents.count)
            out += "\n\(r.corpusName),\(Perl.f2(tokens)),\(Perl.f2(awl)),\(Perl.f2(types)),"
            for f in keys {
                let sum = r.documents.reduce(0.0) { $0 + value($1, f).freq }
                out += "\(Perl.f2(sum / n)),"
            }
        }
        return out
    }

    public static func zscores(_ r: AnalysisResult, catalog: Catalog = .shared) -> String {
        let keys = catalog.means.keys.sorted()
        var out = "Filename,"
        for k in keys { out += "\(k)," }
        out += "Underused_variables,Overused_variables,"

        func tail(_ z: [String: Double]) -> String {
            var under = ""
            for k in keys where (z[k] ?? 0) < -2 { under += "\(k) " }
            var over = ""
            for k in keys where (z[k] ?? 0) > 2 { over += "\(k) " }
            return under + "," + over
        }

        for d in r.documents {
            out += "\n\(d.name),"
            for k in keys { out += "\(Perl.f2(d.z[k] ?? 0))," }
            out += tail(d.z)
        }
        if let cz = r.corpusZ {
            out += "\n\(r.corpusName),"
            for k in keys { out += "\(Perl.f2(cz[k] ?? 0))," }
            out += tail(cz)
        }
        return out
    }

    public static func dimensions(_ r: AnalysisResult) -> String {
        var out = "Filename,Dimension1,Dimension2,Dimension3,Dimension4,Dimension5,Dimension6,Closest Text Type"
        for d in r.documents {
            out += "\n\(d.name),"
            for i in 1...6 { out += "\(Perl.num(d.dims[i] ?? 0))," }
            out += d.textType
        }
        if let cd = r.corpusDims, let tt = r.corpusTextType {
            out += "\n\(r.corpusName),"
            for i in 1...6 { out += "\(Perl.f2(cd[i] ?? 0))," }
            out += tt
        }
        return out
    }
}
