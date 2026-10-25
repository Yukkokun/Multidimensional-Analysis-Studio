# GroundTruth 语料（给原版 MAT 跑）

10 个纯 ASCII 文本，共 **1,684 词**。目的是拿 Windows 上原版 MAT 1.3.3 的输出，
和本机 Swift 版做**逐字节**比对。语料是按"特征覆盖"设计的，不是随便找的文章。

## 文件与设计意图

| 文件 | 词数 | 文体 | 主要埋的构式 |
|---|---|---|---|
| `t01_dialogue.txt` | 142 | 对话转写 | 缩写、否定、第一/第二人称、话语小品词、模糊限制语、WH 疑问句 |
| `t02_news.txt` | 164 | 新闻报道 | 过去时、公共动词、被动、that 补语、时间副词 |
| `t03_academic.txt` | 197 | 学术论文 | 名词化、被动、连接副词、who/which 关系从句 |
| `t04_legal.txt` | 143 | 法律条款 | 条件/让步/因果连词、义务情态、前置介词关系从句、悬空介词 |
| `t05_fiction.txt` | 151 | 小说叙事 | 过去完成时、分词从句、时间/地点副词、第三人称 |
| `t06_speech.txt` | 139 | 演讲稿 | 劝说动词、情态、条件句、强调、短语并列 |
| `t07_manual.txt` | 124 | 说明书 | 分裂不定式、分裂助动词、义务情态、动名词 |
| `t08_review.txt` | 112 | 影评 | 谓语形容词、程度副词、模糊限制语、存在句、合成否定 |
| `t09_letter.txt` | 110 | 私人信件 | 第一/第二人称、现在时、私动词、指示词 |
| `t10_long.txt` | 402 | 长学术文本 | 跨过 400 词的 TTR 窗口（其余 9 个都在窗口内，走"短文本"路径） |

**覆盖自检**：本机管线下 65 个 Biber 特征全部触发（65/65）。因为这批文本用的
tagger（jar + 模型）与 MAT 完全同一个，所以在 Windows 上跑出来的标注也应该一样。

> 注意：9 个文本都短于 400 词，会命中 TTR 的 `distinct + 1` 缺陷，D1 因此被系统性抬高
> 约 5 分。这不是 bug，是原版行为；两边应当**同样**被抬高。`t10_long` 是 402 词，
> 用来验证"窗口刚好被填满"的另一条路径。

## 怎么在原版 MAT 里跑

1. 把 `Corpus/GroundTruth` 整个文件夹拷到 Windows（**文件夹名保持 `GroundTruth`**，
   它会成为 CSV 里的语料名和列名）。这个文件夹里**只有 10 个 .txt**，说明文档就是本文件，
   在文件夹外面——MAT 见到任何非 .txt 都会拒绝整个文件夹。
2. 打开 MAT，点 **Tag and Analyze**（第三个按钮），选择这个**文件夹**。
   - 不要逐个文件选，否则每个文件会生成独立的 `Results_xxx` 目录，凑不成一张表。
3. 弹出的 TTR 窗口：**保持默认 400**，直接 OK。
4. 勾选要画的图：全勾（只影响出图，不影响数字）。
5. 主界面上的两个选项保持**默认**：
   - `Count:` → **Only VASW tags**
   - `Zscore correction:` → **No**
6. 等它跑完（10 个文件，很快）。

## 跑完把什么发我

在那个文件夹里会多出三样东西，请**整个打包**发我：

```
GroundTruth/
├── ST_GroundTruth/        ← Stanford 标注结果（可选，但很有用）
├── MAT_GroundTruth/       ← ★ 必须有：MAT 标注流（每个 *_MAT.txt）
└── Statistics/            ← ★ 必须有：Statistics / Zscores / Dimensions 三个 CSV
```

`MAT_GroundTruth/*_MAT.txt` 是关键：有了它，不一致时我能直接定位到**哪条规则、
第几个词**错了，而不是只知道"分数差了 0.3"。

如果方便，再补一句 MAT 的版本号（启动窗口标题栏写着 `v 1.3.3`）。

## 我会怎么比

`Tools/groundtruth/compare.py` 已经写好，拿到文件后一条命令：

```bash
python3 Tools/groundtruth/compare.py <你发我的目录>
```

| 层 | 比什么 | 判据 |
|---|---|---|
| L1 | `*_MAT.txt` 的 token 流 | 逐词、逐特征标记完全相同 |
| L2 | `Statistics_*.csv` | 每 100 词频次，字符串完全相同 |
| L3 | `Zscores_*.csv` / `Dimensions_*.csv` | 同上（维度允许 0 误差） |

脚本按 `Filename` 列做键，**不比行序**——原版依赖 `readdir` 顺序，NTFS 和 APFS 不一样，
这一点不影响结论。

## 两个提醒

- **MAT 会覆写源文件**：如果文本里有弯引号，它会把 `’` 换成 `'` 并直接写回。
  这批文本是纯 ASCII，理论上不会被改动；但保险起见建议先备份一份。
- 如果跑的时候报 "The folder selected contains other folders or files other than plain
  text"，说明文件夹里混进了别的东西（macOS 拷到 U 盘常见 `.DS_Store`）——用 `ls -a` 看一眼，
  删掉即可。
