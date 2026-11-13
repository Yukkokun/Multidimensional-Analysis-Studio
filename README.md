<div align="center">

<img src="docs/images/icon.png" width="120" alt="MA Studio" />

# MA Studio

**A native desktop implementation of Biber's Multidimensional Analysis — macOS and Windows**

<sub>Tag parts of speech → count 67 linguistic features → convert to z-scores → combine into six dimensions → identify the text type</sub>

**English** · [简体中文](README_ZH.md)

[![release](https://img.shields.io/github/v/release/Yukkokun/Multidimensional-Analysis-Studio?label=release&color=orange)](https://github.com/Yukkokun/Multidimensional-Analysis-Studio/releases/latest) [![license](https://img.shields.io/badge/license-GPL--3.0--only-blue)](LICENSE) ![macOS](https://img.shields.io/badge/macOS-12%2B-black?logo=apple&logoColor=white) ![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)

</div>

---

> [!IMPORTANT]
>   
> **Which download?**
>   
> · **Intel Macs** need the `…macOS12-universal.dmg` (macOS 12+, runs on both Intel and Apple silicon)
>   
> · The other `.dmg` is **Apple silicon + macOS 14 or later** only, and is smaller
>   
> · Windows is a **portable** zip — unzip and double-click `MA Studio.exe`
>
> **Won't it open?** On macOS, if you see "cannot verify the developer", right-click the app → Open,
>   
> or run `xattr -dr com.apple.quarantine /Applications/MA\ Studio.app`.
>
> **Do I need Java?** Only when importing **untagged** plain text — that needs Java 8+ and the
>   
> Stanford tagger locally. Text that is already `word_TAG` needs no Java.

![Overview](docs/images/overview.png)

## What it is

MA Studio turns **MAT (Multidimensional Analysis Tagger)** into a desktop app you can click through:
  
load a batch of English texts, tag parts of speech with the Stanford tagger, count 67 linguistic
  
features following Biber's framework, convert them to z-scores, combine them into six dimension
  
scores, and identify the text type.

The analysis core is a **byte-for-byte port** of the original Perl implementation: the same token
  
stream, the same `Statistics` (85 columns), `Zscores` and `Dimensions`. Not "close enough" — every
  
number lines up, and golden-file regression keeps it that way.

In one line: **reproduce MAT exactly, and explore the numbers interactively.**

## Downloads

Grab the latest from the **[Releases](https://github.com/Yukkokun/Multidimensional-Analysis-Studio/releases/latest)**
  
page — the current version is the `release` badge above, and `<version>` in the file names follows it:

| Platform | File                                        | Notes                                             |
| -------- | ------------------------------------------- | ------------------------------------------------- |
| macOS    | `MA-Studio-<version>-macOS12-universal.dmg` | macOS 12+, **universal** (Intel + Apple silicon)  |
| macOS    | `MA-Studio-<version>.dmg`                   | macOS 14+, **Apple silicon only** (smaller)       |
| Windows  | `MAStudio-<version>-win-x64.zip`            | Windows 10 / 11 x64, **portable** — unzip and run |

Source is provided under GPLv3 section 6 on the same Releases page: macOS has a matching
  
`…-source.zip`, Windows has `MA-Studio-Windows-source.zip` (see its `README-BUILD.txt` for build
  
steps). The end-user Windows zip contains only the app and the licence texts, no source.

> The code in this repository is a historical snapshot and may lag behind the latest release.
>   
> **For the source that matches a release exactly, use that release's `-source.zip`** — if the two
>   
> disagree, the release's source is authoritative.

## Screenshots

| Dimension comparison | Distribution and normality |
| -------------------- | -------------------------- |
| Dimension            | Distribution               |

![Z-compare](docs/images/zcompare.png)

## Features

Eight pages, from the whole corpus down to individual features:

- **Overview** — words, documents, average word length, types; text-type ranking; six dimension
    
  cards (click for detail); the closest reference genre per dimension
- **Dimension** — genre distribution for one dimension (vertical or horizontal bars), overlay a
    
  second corpus, and a reference table sortable by either distance column
- **Six dims** — all six dimensions at once, with an optional comparison corpus
- **Text type** — the profile: current type, reference types, corpus mean, and per-document curves
- **Feature** — frequencies and z-scores for all 67 features, filterable by dimension or to |z| > 2
- **Distribution** — histogram, kernel density and normal curve, a Shapiro–Wilk test, and a verdict
    
  on whether a two-group comparison should use Welch's t or Mann–Whitney U
- **Compare** — Welch's t-test and Mann–Whitney U per feature, with significance
- **Z-compare** — z-scores of two corpora side by side, with BH-FDR / Bonferroni correction and
    
  sortable headers

Also:

- Chinese and English UI, two appearance themes (Vibrant / Professional)
- Export `Statistics` / `Zscores` / `Dimensions` as CSV, plus dimension and text-type charts as PNG
- Comparison corpora can be overlaid on the same chart or examined feature by feature
- Single-document mode: pick one document and every page recomputes for it

## Quick start

1. **Import** — click *Import corpus* in the sidebar and pick a folder or some `.txt` files, or just
     
   drag them onto the window.
2. **Read** — you land on *Overview*; switch pages on the tab bar, or press `Ctrl+1…8`.
3. **Export** — *Export* in the toolbar: three CSVs, or the charts as PNGs.

Preparing a corpus:

- **Already tagged** — one `word_TAG` per token (e.g. `The_DT book_NN`). Runs directly, no Java.
- **Raw text** — one sentence per line; the app tags each document with the Stanford tagger. This
    
  needs Java 8+ locally, and the *Engine* panel pointed at `stanford-postagger.jar` and
    
  `left3words-wsj-0-18.tagger`.

## Keyboard shortcuts

| Shortcut            | Action                           |
| ------------------- | -------------------------------- |
| `Ctrl+O`            | Import corpus                    |
| `Ctrl+R`            | Re-run with the current settings |
| `Ctrl+,`            | Settings                         |
| `Ctrl+1` … `Ctrl+8` | Switch to tab 1…8                |

> On macOS, use `⌘` instead of `Ctrl`.

## Fidelity to the original Perl implementation

This is the part the project is fussiest about. The core was ported rule by rule from MAT's Perl
  
sources and pinned down by golden-file regression:

- Four corpora × three layers of output (token stream, `Statistics`, `Zscores`/`Dimensions`)
    
  compared **byte for byte**
- Even the original's known quirks are reproduced (the short-text TTR bug that adds one type via
    
  `lc(undef)`, the fact that the first 1–6 words of a file are judged using the end of the file,
    
  `INPR` being shadowed by `QUPR`, …)
- Rounding follows the original: frequencies are rounded, z-scores are rounded, dimension sums are **not**

So for the same corpus, the numbers here match the original Perl scripts — which also means an
  
odd-looking number is usually the original's behaviour rather than a new bug.

## Building from source

**Windows** (Rust)

```bash
cargo build --release -p mat-app      # → target/release/ma-studio.exe
```

Requires a stable Rust toolchain and MSVC build tools. Get the source from `MA-Studio-Windows-source.zip`
  
on the Releases page; its `README-BUILD.txt` has the details (including why `.cargo/config.toml` is
  
not shipped).

**macOS** (Swift)

Open the project under `Multidimensional Analysis MacTag/` with Xcode 15, or build from the command
  
line with the script in `Tools/ui-build/` (the version comes from the Xcode project).

## Repository layout

| Path                                   | Contents                                                                     |
| -------------------------------------- | ---------------------------------------------------------------------------- |
| `Packages/MATCore/`                    | The Swift analysis core: statistics, feature tables, reference data, tagging |
| `Multidimensional Analysis MacTag.zip` | The macOS app's Xcode project                                                |
| `Corpus/`                              | Sample corpus (10 documents) used by the demo and the regression suite       |
| `Tools/`                               | Golden-file regression, end-to-end comparison, build and icon scripts        |
| `docs/images/`                         | Screenshots used by this README                                              |
| Windows source                         | Not in this repo — shipped as `MA-Studio-Windows-source.zip` on Releases     |

## FAQ

**"Cannot verify the developer" / macOS blocks the app**
  
The build is not notarised by Apple. Right-click the app → Open the first time, or run
  
`xattr -dr com.apple.quarantine "/Applications/MA Studio.app"`.

**Importing raw text says the tagger is missing**
  
The app needs `stanford-postagger.jar` paired with `left3words-wsj-0-18.tagger` (the 3.1.4
  
generation). Point the *Engine* panel at the folder holding them, or import tagged text instead.

**Tagging stalls halfway, or a console window appears per document**
  
Early Windows builds had both problems (a full pipe deadlocking the child process, and console
  
windows from `java.exe`). Both are fixed — use the latest release.

**The numbers differ from another tool**
  
First check that both saw the same files (compare the document count next to the corpus name), then
  
that both used the same tagger. The algorithm is the same; differences usually come from the input.

## License and credits

Released under **GNU GPL v3** — see [LICENSE](LICENSE). Third-party components (the Nunito typeface,
  
the Stanford tagger, …) are covered in [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).

- **Douglas Biber** — the multidimensional framework itself (*Variation across Speech and Writing*, 1988)
- **Andrea Nini** — author of the original [MAT](https://sites.google.com/site/multidimensionaltagger/),
    
  which defines the behaviour this project matches
- **Stanford NLP Group** — Log-linear Part-Of-Speech Tagger (GPLv2, invoked from the command line;
    
  its code is not linked)
- **Nunito** — the UI typeface (SIL Open Font License 1.1)

This project is not affiliated with, or endorsed by, the authors of MAT or the Stanford Tagger.
