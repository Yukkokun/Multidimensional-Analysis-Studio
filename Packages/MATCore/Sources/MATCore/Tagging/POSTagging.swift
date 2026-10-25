import Foundation

// MARK: - POS 标注抽象
//
// 全流程唯一的外部变量。协议化的目的：让规则引擎可以在没有 JVM 的情况下被完整回归，
// 同时把「换了模型 → 数字全变」这件事变成显式的 fingerprint，而不是一个隐藏的默认值。

public struct TaggedToken: Sendable, Equatable {
    public let surface: String
    public let tag: String
    public init(surface: String, tag: String) {
        self.surface = surface
        self.tag = tag
    }
}

public struct TaggedDocument: Sendable {
    public let name: String
    /// 保留原版「一行一句」的结构：Stanford 的 `-textFile` 是按行独立标注的
    public let lines: [[TaggedToken]]
}

/// 模型指纹：必须随结果一起保存，否则半年后没人说得清数字是哪来的
public struct TaggerFingerprint: Sendable, Equatable, CustomStringConvertible {
    public let engine: String          // "stanford-maxent"
    public let modelName: String       // "wsj-0-18-left3words.tagger"
    public let modelSHA256: String     // 取前 16 位够用
    public let jarName: String
    public let outputFormat: String

    public var description: String {
        "\(engine) · \(modelName) · \(jarName) · \(modelSHA256.prefix(16))"
    }
}

public protocol POSTagging: Sendable {
    var fingerprint: TaggerFingerprint { get }
    func tag(_ documents: [(name: String, text: String)],
             progress: (@Sendable (Int, Int) -> Void)?) async throws -> [TaggedDocument]
}

public enum TaggingError: Error, CustomStringConvertible {
    case javaNotFound
    case jarMissing(URL)
    case modelMissing(URL)
    case processFailed(status: Int32, stderr: String)
    case timedOut(seconds: Int)
    case badOutput(file: String, line: String, hint: String)

    public var description: String {
        switch self {
        case .javaNotFound:
            return "找不到 Java 运行时。装一个 JDK，或用 MAT_JAVA 指定可执行文件路径。"
        case .jarMissing(let u):
            return "找不到 stanford-postagger.jar：\(u.path)"
        case .modelMissing(let u):
            return "找不到模型文件：\(u.path)"
        case .processFailed(let s, let err):
            return "标注进程退出码 \(s)：\(err.isEmpty ? "(无 stderr)" : err)"
        case .timedOut(let s):
            return "标注超时（\(s) 秒）"
        case .badOutput(let f, let line, let hint):
            return "标注输出格式异常（\(f)）：\(line.prefix(120))\n\(hint)"
        }
    }
}

// MARK: - 配置

public struct TaggerConfig: Sendable {
    public var javaExecutable: URL
    public var classPath: [URL]
    public var mainClass: String = "edu.stanford.nlp.tagger.maxent.MaxentTagger"
    public var model: URL
    public var heap: String = "-mx300m"
    /// 实测：不传 `-outputFormat` 时输出正是 `word_TAG`（一行一句），这也是原版依赖的行为。
    /// 显式传 `tsv` 会变成 `word\tTAG`、每词一行，把下游 token 流拆散；
    /// 而 `wordsAndTags` 并不是合法的 OutputStyle 值（会抛 IllegalArgumentException）。
    /// 所以：默认保持 nil（不传），但解析层强制校验形状，形状不对就报错并给出提示。
    public var outputFormat: String? = nil
    public var timeout: TimeInterval = 300

    public init(javaExecutable: URL, classPath: [URL], model: URL) {
        self.javaExecutable = javaExecutable
        self.classPath = classPath
        self.model = model
    }
}
