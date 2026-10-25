import Foundation
import CryptoKit

// MARK: - Stanford MaxentTagger 适配器
//
// 命令行与原版一致（Tagger_MAT.pl:103）：
//   java -mx300m -classpath stanford-postagger.jar \
//        edu.stanford.nlp.tagger.maxent.MaxentTagger \
//        -model wsj-0-18-left3words.tagger -textFile <in>
//
// 两处刻意的差异：
//   1. 显式传 -outputFormat（原版靠默认值）。默认值随发行版变过，一旦变成制表符分隔，
//      下游 `split(/\s+/)` 就会把词和标签拆成两个 token，全盘皆错。
//   2. stdout/stderr 落文件而不是管道。管道在输出量大时会有死锁风险。

public struct StanfordTagger: POSTagging {
    public let config: TaggerConfig
    public let fingerprint: TaggerFingerprint

    public init(config: TaggerConfig) throws {
        guard FileManager.default.fileExists(atPath: config.javaExecutable.path) else {
            throw TaggingError.javaNotFound
        }
        for cp in config.classPath where !FileManager.default.fileExists(atPath: cp.path) {
            throw TaggingError.jarMissing(cp)
        }
        guard FileManager.default.fileExists(atPath: config.model.path) else {
            throw TaggingError.modelMissing(config.model)
        }
        self.config = config
        self.fingerprint = TaggerFingerprint(
            engine: "stanford-maxent",
            modelName: config.model.lastPathComponent,
            modelSHA256: Self.sha256(config.model),
            jarName: config.classPath.map(\.lastPathComponent).joined(separator: "+"),
            outputFormat: config.outputFormat ?? "default(word_TAG)")
    }

    // MARK: 批量标注

    public func tag(_ documents: [(name: String, text: String)],
                    progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [TaggedDocument] {
        var out: [TaggedDocument] = []
        out.reserveCapacity(documents.count)
        for (i, doc) in documents.enumerated() {
            try Task.checkCancellation()
            out.append(try tagOne(name: doc.name, text: doc.text))
            progress?(i + 1, documents.count)
        }
        return out
    }

    func tagOne(name: String, text: String) throws -> TaggedDocument {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let input = tmp.appendingPathComponent("input.txt")
        let stdoutFile = tmp.appendingPathComponent("out.txt")
        let stderrFile = tmp.appendingPathComponent("err.txt")

        // 必须保留原始换行结构：Stanford 是「一行一句」，折行位置会影响标注结果
        try text.write(to: input, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        let process = Process()
        process.executableURL = config.javaExecutable
        var args = [
            config.heap,
            "-cp", config.classPath.map(\.path).joined(separator: ":"),
            config.mainClass,
            "-model", config.model.path,
            "-textFile", input.path,
        ]
        if let fmt = config.outputFormat { args += ["-outputFormat", fmt] }
        process.arguments = args
        let outHandle = try FileHandle(forWritingTo: stdoutFile)
        let errHandle = try FileHandle(forWritingTo: stderrFile)
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // 超时控制：用信号量等 terminationHandler，超时就 terminate
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        if done.wait(timeout: .now() + config.timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 3)
            throw TaggingError.timedOut(seconds: Int(config.timeout))
        }
        try? outHandle.close()
        try? errHandle.close()

        let stderrText = (try? String(contentsOf: stderrFile, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            throw TaggingError.processFailed(status: process.terminationStatus, stderr: stderrText)
        }

        let raw = try String(contentsOf: stdoutFile, encoding: .utf8)
        return TaggedDocument(name: name, lines: try Self.parse(raw, file: name, format: config.outputFormat ?? "default"))
    }

    // MARK: 解析与校验

    /// 期望每行形如 `The_DT book_NN was_VBD`：空格分隔，词与标签用下划线连接。
    static func parse(_ raw: String, file: String, format: String) throws -> [[TaggedToken]] {
        var pieces = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if pieces.last?.isEmpty == true { pieces.removeLast() }   // 结尾换行不算一"行"
        var lines: [[TaggedToken]] = []
        for line in pieces {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { lines.append([]); continue }

            if trimmed.contains("\t") {
                throw TaggingError.badOutput(
                    file: file, line: trimmed,
                    hint: "输出是制表符分隔 —— -outputFormat 没生效。需要 word_TAG（下划线连接）。")
            }
            var tokens: [TaggedToken] = []
            for field in trimmed.split(separator: " ") {
                guard let us = field.lastIndex(of: "_"), us != field.startIndex else {
                    throw TaggingError.badOutput(
                        file: file, line: String(field),
                        hint: "期望 word_TAG 形式（如 The_DT）。当前 -outputFormat=\(format)。")
                }
                tokens.append(TaggedToken(surface: String(field[..<us]),
                                          tag: String(field[field.index(after: us)...])))
            }
            lines.append(tokens)
        }
        return lines
    }

    static func sha256(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "unavailable" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Java 发现

public enum JavaLocator {
    /// macOS 的 `/usr/bin/java` 在没有 JDK 时是个"假"可执行文件：存在、可执行，
    /// 但一跑就报 "Unable to locate a Java Runtime"。所以必须**试跑一次**才算数。
    static func works(_ url: URL) -> Bool {
        let p = Process()
        p.executableURL = url
        p.arguments = ["-version"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// 优先级：MAT_JAVA → JAVA_HOME → /usr/bin/java → 常见 JDK 路径 → JetBrains 自带 JBR
    public static func locate() -> URL? {
        let fm = FileManager.default
        func ok(_ p: String) -> URL? {
            guard fm.isExecutableFile(atPath: p) else { return nil }
            let u = URL(fileURLWithPath: p)
            return works(u) ? u : nil
        }
        let env = ProcessInfo.processInfo.environment

        if let custom = env["MAT_JAVA"], let u = ok(custom) { return u }
        if let home = env["JAVA_HOME"], let u = ok("\(home)/bin/java") { return u }
        if let u = ok("/usr/bin/java") { return u }

        let roots = ["/Library/Java/JavaVirtualMachines", "/opt/homebrew/opt", "/usr/local/opt"]
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items.sorted() {
                for sub in ["Contents/Home/bin/java", "bin/java"] {
                    if let u = ok("\(root)/\(item)/\(sub)") { return u }
                }
            }
        }
        // JetBrains 自带 JBR（开发机常见，且是完整 JDK）
        let apps = ["/Volumes/ML.Origin/Applications", "/Applications"]
        for app in apps {
            for name in ["PyCharm", "CLion", "RustRover", "IntelliJ IDEA", "GoLand", "WebStorm"] {
                if let u = ok("\(app)/\(name).app/Contents/jbr/Contents/Home/bin/java") { return u }
            }
        }
        return nil
    }
}
