import Foundation
import MATCore

// matctl —— 命令行入口。三个子命令：
//
//   analyze  读「已标注」目录（word_TAG 流）→ 只跑规则+统计（不需要 Java）
//   tag      读原始文本 → 调 Stanford Tagger → 写 word_TAG 流（需要 Java + jar + 模型）
//   run      tag + analyze，端到端
//
// analyze 是 P1 的回归入口；tag/run 是 P3 的端到端入口。

struct Options {
    var input = ""
    var output = ""
    var name = ""
    var clamp = false
    var allTags = false
    var ttrWindow = 400
    var java: String?
    var jar: String?
    var model: String?
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage:
      matctl analyze --in <tagged-dir> --out <dir> [--name <corpus>] [--clamp] [--all-tags] [--ttr 400]
      matctl tag     --in <raw-dir>    --out <tagged-dir> [--jar <jar>] [--model <tagger>] [--java <java>]
      matctl run     --in <raw-dir>    --out <dir> [--name <corpus>] [--clamp] [--all-tags] [--ttr 400]

    环境变量：MAT_JAVA / MAT_JAR / MAT_MODEL / MAT_OUTPUT_FORMAT
    """.utf8))
    exit(2)
}

// MARK: - 参数

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args = Array(args.dropFirst())

var opts = Options()
var i = 0
while i < args.count {
    let a = args[i]
    func next() -> String { i += 1; guard i < args.count else { usage() }; return args[i] }
    switch a {
    case "--in": opts.input = next()
    case "--out": opts.output = next()
    case "--name": opts.name = next()
    case "--clamp": opts.clamp = true
    case "--all-tags": opts.allTags = true
    case "--all-tags": opts.allTags = true
    case "--ttr": opts.ttrWindow = Int(next()) ?? 400
    case "--java": opts.java = next()
    case "--jar": opts.jar = next()
    case "--model": opts.model = next()
    default: usage()
    }
    i += 1
}
guard !opts.input.isEmpty, !opts.output.isEmpty else { usage() }

let fm = FileManager.default
let inputURL = URL(fileURLWithPath: opts.input)
let corpusName = opts.name.isEmpty
    ? inputURL.deletingLastPathComponent().lastPathComponent
    : opts.name

@MainActor
func sortedTextFiles(_ dir: URL) -> [URL] {
    let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return entries.filter { $0.pathExtension.lowercased() == "txt" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

@MainActor
func write(_ text: String, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.data(using: .utf8)!.write(to: url)
}

let analyzer = Analyzer()

/// 写 stream + 三个 CSV
@MainActor
func emit(result: AnalysisResult, annotated: [String: [Token]], corpus: String, to dir: URL) throws {
    let streamDir = dir.appendingPathComponent("stream")
    let csvDir = dir.appendingPathComponent("csv")
    for (name, tokens) in annotated {
        try write(tokens.map(\.serialized).joined(separator: "\n") + "\n",
                  to: streamDir.appendingPathComponent("\(name)_MAT.txt"))
    }
    try write(Reports.statistics(result, allTags: opts.allTags),
              to: csvDir.appendingPathComponent("Statistics_\(corpus).csv"))
    try write(Reports.zscores(result), to: csvDir.appendingPathComponent("Zscores_\(corpus).csv"))
    try write(Reports.dimensions(result), to: csvDir.appendingPathComponent("Dimensions_\(corpus).csv"))
}

// MARK: - analyze

@MainActor
func runAnalyze() throws {
    let files = sortedTextFiles(inputURL)
    guard !files.isEmpty else { fail("no .txt in \(opts.input)") }

    var documents: [(name: String, tokens: [Token])] = []
    for url in files {
        let text = try String(contentsOf: url, encoding: .utf8)
        documents.append((url.deletingPathExtension().lastPathComponent, Token.parseStream(text)))
    }
    let result = analyzer.analyze(documents, corpusName: corpusName,
                                  ttrWindow: opts.ttrWindow, clamp: opts.clamp)
    var annotated: [String: [Token]] = [:]
    for doc in documents { annotated[doc.name] = analyzer.annotateOnly(doc.tokens) }
    try emit(result: result, annotated: annotated, corpus: corpusName,
             to: URL(fileURLWithPath: opts.output))
    print("matctl analyze: \(files.count) documents → \(opts.output)")
}

// MARK: - tag

/// 优先用 MAT 原版模型（left3words-wsj-0-18，随 MAT 的 Windows 包分发），
/// 退而求其次用 Stanford 公开发行版里的任意 .tagger。
/// 两者数字不可比——TaggerFingerprint 会把实际使用的模型写进结果。
@MainActor
func defaultModelPath() -> String {
    let candidates = ["Vendor/Tagging/models/left3words-wsj-0-18.tagger",
                      "Vendor/Tagging/models/wsj-0-18-left3words.tagger"]
    for c in candidates where fm.fileExists(atPath: c) { return c }
    if let items = try? fm.contentsOfDirectory(atPath: "Vendor/Tagging/models"),
       let first = items.filter({ $0.hasSuffix(".tagger") }).sorted().first {
        return "Vendor/Tagging/models/\(first)"
    }
    return candidates[0]
}

@MainActor
func makeTagger() throws -> StanfordTagger {
    let env = ProcessInfo.processInfo.environment
    guard let javaPath = opts.java ?? env["MAT_JAVA"] ?? JavaLocator.locate()?.path else {
        throw TaggingError.javaNotFound
    }
    let jarPath = opts.jar ?? env["MAT_JAR"] ?? "Vendor/Tagging/stanford-postagger.jar"
    let modelPath = opts.model ?? env["MAT_MODEL"] ?? defaultModelPath()
    var cfg = TaggerConfig(javaExecutable: URL(fileURLWithPath: javaPath),
                           classPath: [URL(fileURLWithPath: jarPath)],
                           model: URL(fileURLWithPath: modelPath))
    if let fmt = env["MAT_OUTPUT_FORMAT"], !fmt.isEmpty { cfg.outputFormat = fmt }
    return try StanfordTagger(config: cfg)
}

@MainActor
func runTag() async throws {
    let files = sortedTextFiles(inputURL)
    guard !files.isEmpty else { fail("no .txt in \(opts.input)") }
    let tagger = try makeTagger()
    let docs = try files.map { url -> (name: String, text: String) in
        let raw = try String(contentsOf: url, encoding: .utf8)
        if TextPreparer.needsNormalization(raw) {
            FileHandle.standardError.write(Data("  · \(url.lastPathComponent)：已折叠弯引号（内存中，不改源文件）\n".utf8))
        }
        return (url.deletingPathExtension().lastPathComponent, TextPreparer.normalize(raw))
    }
    let tagged = try await tagger.tag(docs) { done, total in
        FileHandle.standardError.write(Data("\r[tag] \(done)/\(total)".utf8))
    }
    FileHandle.standardError.write(Data("\n".utf8))
    let outDir = URL(fileURLWithPath: opts.output)
    for doc in tagged {
        let body = doc.lines.map { line in
            line.map { "\($0.surface)_\($0.tag)" }.joined(separator: " ")
        }.joined(separator: "\n") + "\n"
        try write(body, to: outDir.appendingPathComponent("\(doc.name).txt"))
    }
    print("matctl tag: \(tagged.count) documents → \(opts.output)")
    print("tagger: \(tagger.fingerprint)")
}

// MARK: - run

@MainActor
func runAll() async throws {
    let files = sortedTextFiles(inputURL)
    guard !files.isEmpty else { fail("no .txt in \(opts.input)") }
    let tagger = try makeTagger()
    let raw = try files.map { url -> (name: String, text: String) in
        (url.deletingPathExtension().lastPathComponent,
         TextPreparer.normalize(try String(contentsOf: url, encoding: .utf8)))
    }
    let tagged = try await tagger.tag(raw, progress: nil)

    var documents: [(name: String, tokens: [Token])] = []
    var annotated: [String: [Token]] = [:]
    for doc in tagged {
        // Stanford 输出 → 原版的 word_TAG 流（一行一个 token，换行不参与语义）
        let text = doc.lines.map { line in
            line.map { "\($0.surface)_\($0.tag)" }.joined(separator: " ")
        }.joined(separator: "\n")
        let tokens = Token.parseStream(text)
        documents.append((doc.name, tokens))
        annotated[doc.name] = analyzer.annotateOnly(tokens)
    }
    let result = analyzer.analyze(documents, corpusName: corpusName,
                                  ttrWindow: opts.ttrWindow, clamp: opts.clamp)
    try emit(result: result, annotated: annotated, corpus: corpusName,
             to: URL(fileURLWithPath: opts.output))
    print("matctl run: \(documents.count) documents → \(opts.output)")
    print("tagger: \(tagger.fingerprint)")
}

// MARK: - 分发

do {
    switch command {
    case "analyze": try runAnalyze()
    case "tag": try await runTag()
    case "run": try await runAll()
    default: usage()
    }
} catch {
    fail("\(error)")
}
