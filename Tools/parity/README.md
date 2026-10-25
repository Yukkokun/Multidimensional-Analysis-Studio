# MAT Parity Harness

在 macOS 上无 UI 跑**原版** MAT 的「标注规则 → 计数 → 统计」全链路，产出 golden 输出，
供 Swift 移植版做逐字节回归。

原版是 Windows + Win32::GUI + Java 的三重锁定，这里把它拆开：UI 用 stub 顶掉，
JVM 用预制标注结果顶掉，剩下的就是纯粹的 Perl 逻辑——而它才是需要 1:1 复刻的部分。

## 快速开始

```bash
./run-goldens.sh              # 重新生成 goldens/ 与 generated/
./run-goldens.sh --check      # Perl 侧自校验（CI 用）
./verify-swift.sh             # Swift 侧三层回归：L1 token 流 / L2 Statistics / L3 Zscores+Dimensions
```

`verify-swift.sh` 当前状态：**四套语料 + clamp 分支全绿（0 diff）**。

依赖：系统自带 `perl`（5.30+）。**不需要** Java、不需要 Windows、不需要 Chart/GD 模块。

## 目录

```
bin/run.pl                 单语料跑一遍：patch 源码 → Tagger_MAT → count_only → 收集产物
bin/extract-constants.pl   从 Perl 源码抽常量表 → generated/*.json
gen-fixtures.py            生成语料（tagged/ 与 raw/）
lib/                       Win32::GUI / Chart::* / GD / Data::Dump 的 stub
fixtures/<corpus>/tagged/   word_TAG 流 = Stanford Tagger 的输出（harness 的唯一输入）
fixtures/<corpus>/raw/     只有 surface，用于驱动原版的目录遍历
goldens/<corpus>/stream/   *_MAT.txt   ← token 流 golden
goldens/<corpus>/csv/      Statistics_*.csv / Zscores_*.csv / Dimensions_*.csv
generated/                 65 特征、67 组 mean/sd、8 文本类型、8 体裁、词表
```

## 只打了两处补丁，都不影响数值

1. **跳过 JVM**：把 `Tagger_MAT.pl` 里的
   `system("$command")`（一行 `java ... -textFile ...`）替换成
   `system("cp", $ENV{ST_INJECT}."/".$files[$i], $directory_ST."/ST_".$files[$i])`。
   于是 POS 标注这个唯一外部变量被摘掉：Perl 侧和 Swift 侧吃**完全相同**的 `word_TAG` 流，
   diff 出来的差异只可能来自规则/计数/统计。
2. **readdir 排序**：原版依赖目录遍历顺序（NTFS 恰好近似字母序，APFS 不保证）。
   不排序就无法得到可复现的 golden。只影响 CSV 的行序，不影响任何数值。

其余代码逐字节保持原样，包括注释和缩进。

## 语料覆盖

| 文件 | 锁住的行为 |
|---|---|
| `01_passive` | `[PASS]` vs `[BYPA]` 的分支；`[PEAS]` |
| `02_that` | `that` 的四种身份：DEMP / DEMO / TOBJ / THATD |
| `03_wh` | `[WHSUB]` `[WHOBJ]` `[SERE]` `[PIRE]` |
| `04_contraction` | `n't→XX0`、`'s/'re→$be`、`'ll/'d→PRMD`、`[CONT]` |
| `05_lexicon` | `[PUBV]` `[PRIV]` `[SUAV]` `[SMP]`、AMP、DWNT |
| `06_nominalization` | `NOMZ`、`GER`（含 `\w{10,}` 长度阈值） |
| `07_preposition` | `to→PIN`、`[STPR]`、`[SPIN]`（连带 `[SPIN]` 的 z 爆炸） |
| `08_start_to` | 句首 `to` 在 `j=0` 的行为 |
| `09_negative_index` | **Perl 负索引回绕**（故意让倒数第二个 token 是 `there_EX`） |
| `10_quantifier` | `INPR` 被 `QUPR` 覆盖 |
| `11_coordination` | `PHC`、`ANDC` |
| `12_short` | 短文本 TTR 的 undef 缺陷 |
| `bulk/a_120` | 短文本路径 |
| `bulk/b_450` | 415 个有效词，跨过 400 的 TTR 窗口 |
| `bulk/c_700` | 长文本 |

## 已被 golden 证实的原版行为（不是推测）

| 现象 | 实测值 |
|---|---|
| 复杂特征是**独立 token**，但写在同一行 | 文件里是 `was_VBD [BYPA]`（一行两段），`split(/\s+/)` 后才成两个 token |
| 多特征 token 是**倒序**排列 | `think_VPRT [PRIV] [THATD]`——P6 先加 THATD，P8 后加 PRIV，后触发的在左 |
| `INPR` 只剩 4 个词 | `Nobody_INPR` 保留，`Everybody_QUPR` / `something_QUPR` 被覆盖 |
| 短文本 TTR = distinct + 1 | `12_short`：10 tokens，TTR=11 |
| `[SPIN]` 的 z 爆炸 | `07_preposition`：**370000.00**（sd=0.00001） |
| 负索引回绕生效 | `09_negative_index` 的 `Was_VBD` **没有** `[BEMA]`（守卫被文末 `there_EX` 打破） |
| 维度和不做浮点清理 | `Dimension2 = 5.55111512312578e-16`、`-0.0699999999999997` |
| AWL 按**字节**计长 | `café_NN` 计 5 个字符位，4 tokens → AWL 3.50 |
| clamp 会改变文本类型 | `02_that`：Intimate interpersonal → Informational interaction |
| Zscores 列序是字节序 | `AWL` 在第 4 列、`TTR` 在第 41 列（都与大写键混排），`[PASS]` 在第 48 列 |
| 编码检测不是硬失败 | UTF-8 无 BOM 的 `café` 没被拦，而是**静默按字节**处理 |

## Swift 侧怎么用

三层 diff，逐层收敛，**上一层不绿不许进下一层**：

1. **L1 token 流**：把 `[Token]` 序列化成 `word_TAG`（特征各占一行），与 `goldens/*/stream/*.txt` 逐字节比。
2. **L2 计数**：`Statistics_*.csv` 用**字符串**比较，不要变 double 再比（`14.29` vs `14.290000000000001` 会假阳性）。
3. **L3 统计**：`Zscores_*.csv` + `Dimensions_*.csv` 同上。

CLI 已预留位置：`matctl analyze --in <fixtures/.../tagged> --out <tmp>`，
默认走「已有标注」模式，跳过 POS 标注。

## 限制

- **不覆盖 POS 标注本身**。tagging 的正确性只能在接入 JVM 后用端到端用例验证（P3）。
- 语料是 ASCII。这不是偷懒：原版对非 ASCII 是「可能静默按字节算」，一旦混入就会让
  golden 同时承担两个变量。非 ASCII 行为单独用 `build/nonascii` 那种临时用例观察，
  不要放进主 golden。
- `concordancer.pl`（原文检索）未接入，它不影响数值。
