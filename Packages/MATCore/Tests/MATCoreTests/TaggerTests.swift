import XCTest
@testable import MATCore

/// 标注层的测试：解析与进程管线。
/// 都不依赖真实 JVM——用一段 shell 脚本冒充 java 来验证「起进程 → 收输出 → 解析」这条链。
final class TaggerTests: XCTestCase {

    // MARK: 解析与校验

    func testParseWordTagLines() throws {
        let lines = try StanfordTagger.parse("The_DT book_NN was_VBD\n\nA_DT test_NN\n",
                                             file: "x", format: "wordsAndTags")
        XCTAssertEqual(lines.count, 3, "空行要保留（一行一句的结构不能丢）")
        XCTAssertEqual(lines[0].map(\.tag), ["DT", "NN", "VBD"])
        XCTAssertEqual(lines[0][1].surface, "book")
        XCTAssertEqual(lines[1], [])
        XCTAssertEqual(lines[2].map(\.surface), ["A", "test"])
    }

    func testParseRejectsTabSeparated() {
        XCTAssertThrowsError(try StanfordTagger.parse("The\tDT book\tNN\n", file: "x", format: "tsv")) { err in
            guard case TaggingError.badOutput(_, _, let hint) = err else {
                return XCTFail("期望 badOutput，实际 \(err)")
            }
            XCTAssertTrue(hint.contains("制表符"), "错误信息要直接指出是 -outputFormat 的问题")
        }
    }

    func testParseRejectsMissingUnderscore() {
        XCTAssertThrowsError(try StanfordTagger.parse("The_DT book\n", file: "x", format: "wordsAndTags")) { err in
            guard case TaggingError.badOutput = err else { return XCTFail("期望 badOutput") }
        }
    }

    // MARK: 进程管线（用 shell 脚本冒充 java）

    private func makeStubTagger(output: String) throws -> (StanfordTagger, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mat-stub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let script = dir.appendingPathComponent("java")
        try """
        #!/bin/sh
        # 冒充 MaxentTagger：忽略参数，直接吐出固定的 word_TAG 流
        cat <<'EOF'
        \(output)
        EOF
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let model = dir.appendingPathComponent("wsj-0-18-left3words.tagger")
        try "fake-model".write(to: model, atomically: true, encoding: .utf8)

        var cfg = TaggerConfig(javaExecutable: script, classPath: [], model: model)
        cfg.timeout = 20
        return (try StanfordTagger(config: cfg), dir)
    }

    func testPipelineCapturesAndParsesOutput() async throws {
        let (tagger, dir) = try makeStubTagger(output: "The_DT book_NN is_VBZ good_JJ ._.")
        defer { try? FileManager.default.removeItem(at: dir) }

        let docs = try await tagger.tag([(name: "doc1", text: "The book is good.\n")])
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs[0].lines[0].map(\.serialized), ["The_DT", "book_NN", "is_VBZ", "good_JJ", "._."])
        XCTAssertTrue(tagger.fingerprint.modelName.hasSuffix(".tagger"))
        XCTAssertEqual(tagger.fingerprint.modelSHA256.count, 64, "模型指纹要能被记录")
    }

    func testPipelinePropagatesFailure() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mat-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let script = dir.appendingPathComponent("java")
        try "#!/bin/sh\necho 'model not found' >&2\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let model = dir.appendingPathComponent("m.tagger")
        try "x".write(to: model, atomically: true, encoding: .utf8)

        let tagger = try StanfordTagger(config: TaggerConfig(javaExecutable: script, classPath: [], model: model))
        XCTAssertThrowsError(try tagger.tagOne(name: "d", text: "hello\n")) { err in
            guard case TaggingError.processFailed(let status, let stderr) = err else {
                return XCTFail("期望 processFailed，实际 \(err)")
            }
            XCTAssertEqual(status, 3)
            XCTAssertTrue(stderr.contains("model not found"), "stderr 要带出来，否则没法排查")
        }
    }

    func testMissingModelSurfacesEarly() {
        let cfg = TaggerConfig(javaExecutable: URL(fileURLWithPath: "/bin/sh"),
                               classPath: [],
                               model: URL(fileURLWithPath: "/nonexistent/x.tagger"))
        XCTAssertThrowsError(try StanfordTagger(config: cfg)) { err in
            guard case TaggingError.modelMissing = err else { return XCTFail("期望 modelMissing") }
        }
    }

    // MARK: 端到端（有 JVM + jar + 模型时才跑）

    func testEndToEndWithRealTaggerIfAvailable() async throws {
        guard let java = JavaLocator.locate() else {
            throw XCTSkip("本机没有 JVM，跳过真实标注")
        }
        let repo = GoldenTests.repo
        let jar = repo.appendingPathComponent("Vendor/Tagging/stanford-postagger.jar")
        let modelsDir = repo.appendingPathComponent("Vendor/Tagging/models")
        let available = ((try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "tagger" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // 优先用原版模型（若有），否则用包里自带的任意模型跑通链路
        // 原版模型的两个常见文件名（MAT 包里是 left3words-wsj-0-18）
        let preferred = ["left3words-wsj-0-18.tagger", "wsj-0-18-left3words.tagger"]
        let model = preferred.compactMap { name in available.first { $0.lastPathComponent == name } }.first
            ?? available.first
        guard FileManager.default.fileExists(atPath: jar.path), let model else {
            throw XCTSkip("缺少 jar 或模型文件")
        }
        let cfg = TaggerConfig(javaExecutable: java, classPath: [jar], model: model)
        let tagger = try StanfordTagger(config: cfg)
        let docs = try await tagger.tag([(name: "t", text: "The book was written by the committee.\n")])
        let tags = docs[0].lines[0].map(\.tag)
        XCTAssertTrue(tags.contains("VBN"), "written 应当被标成 VBN，实际：\(tags)")
    }
}

private extension TaggedToken {
    var serialized: String { "\(surface)_\(tag)" }
}
