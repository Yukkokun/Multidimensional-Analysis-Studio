import Foundation

// MARK: - 常量目录（全部来自 Tools/parity/generated/*.json，绝不手抄）

public struct Centroid: Sendable {
    public let name: String
    public let values: [Double]      // D1…D5（文本类型）/ D1…D6（体裁）
}

public struct GenreRef: Sendable {
    public let name: String
    public let values: [Double]      // 质心
    public let high: [Double]        // 绝对上界
    public let low: [Double]         // 绝对下界
}

public struct Catalog: Sendable {
    public let featureOrder: [String]
    public let tagFeatures: Set<String>
    public let means: [String: Double]
    public let sds: [String: Double]
    public let textTypes: [Centroid]
    public let genres: [GenreRef]

    // 词表
    public let lexBe: Lexicon
    public let lexDo: Lexicon
    public let lexHave: Lexicon
    public let lexWP: Lexicon
    public let lexWho: Lexicon
    public let lexPrep: Lexicon
    public let lexPublic: Lexicon
    public let lexPrivate: Lexicon
    public let lexSuasive: Lexicon

    public let listTime: Lexicon
    public let listPlace: Lexicon
    public let listAmp: Lexicon
    public let listDwnt: Lexicon
    public let listFpp1: Lexicon
    public let listSpp2: Lexicon
    public let listTpp3: Lexicon
    public let listPit: Lexicon
    public let listConj: Lexicon
    public let listConc: Lexicon
    public let listCond: Lexicon
    public let listCaus: Lexicon
    public let listPomd: Lexicon
    public let listNemd: Lexicon
    public let listEmph: Lexicon
    public let listDpar: Lexicon
    public let listHdgm: Lexicon
    public let listSmp: Lexicon
    public let listAndcNx: Lexicon

    /// P2 的单 token 类别（不是 Biber 特征，但是后续规则的输入标签）
    public let inpr: Set<String>
    public let quan: Set<String>
    public let qupr: Set<String>

    public static let shared: Catalog = {
        do { return try Catalog() }
        catch { fatalError("MATCore: 无法加载资源常量表：\(error)") }
    }()

    private struct FeaturesFile: Decodable {
        struct F: Decodable { let id: String; let kind: String }
        let features: [F]
    }
    private struct StatsFile: Decodable {
        struct S: Decodable { let id: String; let mean: Double; let sd: Double }
        let stats: [S]
    }
    private struct TypesFile: Decodable {
        struct T: Decodable { let id: String; let dimension: [Double] }
        let textTypes: [T]
    }
    private struct GenresFile: Decodable {
        struct G: Decodable { let id: String; let dimension: [Double]; let rangeHigh: [Double]; let rangeLow: [Double] }
        let genres: [G]
    }
    private struct LexFile: Decodable {
        struct L: Decodable { let regex: String }
        let lexicons: [String: L]
    }
    private struct ListsFile: Decodable {
        let lists: [String: String]
    }

    private static func url(_ name: String) throws -> URL {
        guard let u = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")
        else { throw CocoaError(.fileNoSuchFile) }
        return u
    }

    private static func decode<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url(name)))
    }

    public init() throws {
        let feat = try Self.decode("biber-features", as: FeaturesFile.self)
        featureOrder = feat.features.map(\.id)
        tagFeatures = Set(feat.features.filter { $0.kind == "tag" }.map(\.id))
        precondition(featureOrder.count == 65, "biber-features 应为 65 条，实际 \(featureOrder.count)")

        let stats = try Self.decode("zscore-tables", as: StatsFile.self)
        var m: [String: Double] = [:], d: [String: Double] = [:]
        for s in stats.stats { m[s.id] = s.mean; d[s.id] = s.sd }
        means = m; sds = d
        precondition(m.count == 67, "zscore-tables 应为 67 组，实际 \(m.count)")

        textTypes = try Self.decode("texttype-centroids", as: TypesFile.self)
            .textTypes.map { Centroid(name: $0.id, values: $0.dimension) }
        genres = try Self.decode("genre-centroids", as: GenresFile.self)
            .genres.map { GenreRef(name: $0.id, values: $0.dimension, high: $0.rangeHigh, low: $0.rangeLow) }

        let lexFile = try Self.decode("lexicons", as: LexFile.self)
        func lex(_ n: String) -> Lexicon { Lexicon(fragment: lexFile.lexicons[n]?.regex ?? "") }
        lexBe = lex("be"); lexDo = lex("do"); lexHave = lex("have")
        lexWP = lex("wp"); lexWho = lex("who"); lexPrep = lex("preposition")
        lexPublic = lex("public"); lexPrivate = lex("private"); lexSuasive = lex("suasive")

        let lists = try Self.decode("wordlists", as: ListsFile.self).lists
        func lst(_ n: String) -> Lexicon { Lexicon(fragment: lists[n] ?? "") }
        listTime = lst("time"); listPlace = lst("place"); listAmp = lst("amp"); listDwnt = lst("dwnt")
        listFpp1 = lst("fpp1"); listSpp2 = lst("spp2"); listTpp3 = lst("tpp3"); listPit = lst("pit")
        listConj = lst("conj"); listConc = lst("conc"); listCond = lst("cond"); listCaus = lst("caus")
        listPomd = lst("pomd"); listNemd = lst("nemd"); listEmph = lst("emph"); listDpar = lst("dpar")
        listHdgm = lst("hdgm"); listSmp = lst("smp"); listAndcNx = lst("andcNx")

        // P2.3 / P2.4 / P2.5 的三个小词表（源码里是字面量，不是 $ 变量）
        inpr = ["anybody", "anyone", "anything", "everybody", "everyone", "everything",
                "nobody", "none", "nothing", "nowhere", "somebody", "someone", "something"]
        quan = ["each", "all", "every", "many", "much", "few", "several", "some", "any"]
        qupr = ["everybody", "somebody", "anybody", "everyone", "someone", "anyone",
                "everything", "something", "anything"]
    }
}
