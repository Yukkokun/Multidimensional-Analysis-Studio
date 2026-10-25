import XCTest
@testable import MATCore

/// 三层逐字节回归：直接把 Tools/parity/goldens 当作 expected。
///
/// 这是整个项目的主锚点——任何规则改动只要破坏一致性，这里立刻红。
/// 不写临时文件，全部在内存里比字符串，跑得快。
final class GoldenTests: XCTestCase {

    // <repo>/Packages/MATCore/Tests/MATCoreTests/GoldenTests.swift
    // 去 5 级：文件 → MATCoreTests → Tests → MATCore → Packages → <repo>
    static let repo: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u = u.deletingLastPathComponent() }
        precondition(FileManager.default.fileExists(atPath: u.appendingPathComponent("Tools/parity/goldens").path),
                     "找不到仓库根目录：\(u.path)")
        return u
    }()

    static let corpora = ["rules", "rules2", "rules3", "bulk"]

    private func loadCorpus(_ name: String) throws -> [(name: String, tokens: [Token])] {
        let dir = Self.repo.appendingPathComponent("Tools/parity/fixtures/\(name)/tagged")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return (url.deletingPathExtension().lastPathComponent, Token.parseStream(text))
        }
    }

    private func golden(_ path: String) throws -> String {
        try String(contentsOf: Self.repo.appendingPathComponent(path), encoding: .utf8)
    }

    /// L1：token 流逐字节（含特征顺序、空格、换行）
    func testTokenStreamsByteExact() throws {
        let analyzer = Analyzer()
        for corpus in Self.corpora {
            let docs = try loadCorpus(corpus)
            for doc in docs {
                let annotated = analyzer.annotateOnly(doc.tokens)
                let mine = annotated.map(\.serialized).joined(separator: "\n") + "\n"
                let expected = try golden("Tools/parity/goldens/\(corpus)/stream/\(doc.name)_MAT.txt")
                XCTAssertEqual(mine, expected,
                               "L1 不一致：\(corpus)/\(doc.name)")
            }
        }
    }

    /// L2 + L3：三个 CSV 逐字节
    func testCSVsByteExact() throws {
        let analyzer = Analyzer()
        for corpus in Self.corpora {
            let docs = try loadCorpus(corpus)
            let r = analyzer.analyze(docs, corpusName: corpus)

            XCTAssertEqual(Reports.statistics(r), try golden("Tools/parity/goldens/\(corpus)/csv/Statistics_\(corpus).csv"),
                           "L2 不一致：\(corpus) Statistics")
            XCTAssertEqual(Reports.zscores(r), try golden("Tools/parity/goldens/\(corpus)/csv/Zscores_\(corpus).csv"),
                           "L3 不一致：\(corpus) Zscores")
            XCTAssertEqual(Reports.dimensions(r), try golden("Tools/parity/goldens/\(corpus)/csv/Dimensions_\(corpus).csv"),
                           "L3 不一致：\(corpus) Dimensions")
        }
    }

    /// 单文件不产生 corpus 行（原版 `@files > 3` 的效果）
    func testSingleDocumentHasNoCorpusRow() throws {
        let docs = try loadCorpus("rules")
        let one = [docs[0]]
        let r = Analyzer().analyze(one, corpusName: "single")
        XCTAssertNil(r.corpusZ)
        let csv = Reports.dimensions(r)
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 2, "表头 + 一行")
    }
}
