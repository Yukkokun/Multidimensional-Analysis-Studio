<img width="976" height="702" alt="image" src="https://github.com/user-attachments/assets/20fe9f6f-6e7f-4866-9477-309039fc9577" /># 
<font size=20>**Windows version is coming soon!**</font>
MA Studio
A native macOS app for **Multidimensional Analysis** of English text, following Douglas Biber's
framework: tag parts of speech, count 67 linguistic features, convert them to z-scores, combine them
into six dimension scores, and identify the text type.

The analysis core is a Swift port that reproduces the original Perl implementation byte for byte
(token stream, `Statistics` 85 columns, `Zscores`, `Dimensions`), verified by golden-file regression.


## Requirements

- macOS 14 or later (universial version: macOS 12 on intel and Apple silicon)
- Xcode 15 (only for building the app target)
- Optional, for part-of-speech tagging: Java 8+ and **stanford-postagger 3.1.4** with the
  `left3words-wsj-0-18.tagger` model. Point the app at the folder in *Engine settings*, or import
  text that is already tagged as `word_TAG` — then no Java is needed.

## Layout

| Path | Contents |
|---|---|
| `Multidimensional Analysis MacTag/` | Xcode project and the SwiftUI app (`Studio/`) |
| `Packages/MATCore/` | Analysis engine, statistics, catalog of features and reference data |
| `Tools/parity/` | Golden-file regression harness and fixtures |
| `Tools/groundtruth/` | End-to-end comparison against the original tool |
| `Tools/ui-build/` | Builds the app without Xcode; reads the version from the Xcode project |
| `Tools/icon/` | Generated app icon (source script included) |
| `Corpus/GroundTruth/` | 10-document sample corpus used by the demo |

## License

GPL-3.0 — see [LICENSE](LICENSE).

---

MA Studio 是一个 macOS 原生应用，用于对英文文本做 Biber 的多维分析（Multidimensional Analysis）：
词性标注 → 统计 67 个语言特征 → 换算 z 分数 → 合成六个维度分 → 判定文本类型。
分析内核与 Perl 原版逐字节一致，并由 golden 回归保证。
