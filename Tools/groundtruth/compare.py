#!/usr/bin/env python3
"""
拿 Windows 上原版 MAT 的输出，和本机的 Swift 版基线做逐层比对。

用法：
    python compare.py <原版输出目录>            # 目录里应有 Statistics 与 MAT_xxx
    python compare.py <目录> --verbose          # 打印每个差异单元格

三层：
    L1  MAT_*.txt  token 流（逐词、逐特征标记）
    L2  Statistics_*.csv  每 100 词频次
    L3  Zscores_*.csv / Dimensions_*.csv

设计要点：
    · 原版依赖 readdir 顺序，行序不可控 → 一律按 Filename 列做键，不比行序
    · 原版 v1.3 的 CSV 是制表符分隔，v1.3.3 的代码是逗号 → 自动嗅探
    · Windows 输出是 CRLF → 统一去掉 \r 再比
"""
import argparse
import csv
import json
import os
import sys

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "baseline")


def sniff_rows(path):
    """读 CSV，返回 (header, [dict])；自动处理 BOM / 制表符 / 逗号 / CRLF。"""
    raw = open(path, "rb").read().decode("utf-8-sig", errors="replace")
    first = raw.split("\n", 1)[0]
    delim = "\t" if first.count("\t") > first.count(",") else ","
    rows = list(csv.reader(raw.splitlines(), delimiter=delim))
    if not rows:
        return [], []
    header = [h.strip() for h in rows[0]]
    # 原版末尾常有空列（每行都以分隔符结尾）
    while header and header[-1] == "":
        header.pop()
    out = []
    for r in rows[1:]:
        if not any(x.strip() for x in r):
            continue
        rec = {}
        for i, name in enumerate(header):
            rec[name] = (r[i] if i < len(r) else "").strip()
        out.append(rec)
    return header, out


def find_file(root, *needles):
    hits = []
    for dirpath, _, files in os.walk(root):
        for f in files:
            low = f.lower()
            if all(n.lower() in low for n in needles):
                hits.append(os.path.join(dirpath, f))
    return sorted(hits)


def compare_csv(ours_path, theirs_path, label, verbose, tol=0.0):
    oh, orows = sniff_rows(ours_path)
    th, trows = sniff_rows(theirs_path)
    if not th:
        print(f"  {label}: 原版文件为空或无法解析")
        return 1

    okeys, tkeys = set(oh) - {""}, set(th) - {""}
    missing_cols = sorted(okeys - tkeys)
    extra_cols = sorted(tkeys - okeys)
    if missing_cols:
        print(f"  {label}: 原版缺少列 {missing_cols[:8]}{'…' if len(missing_cols) > 8 else ''}")
    if extra_cols:
        print(f"  {label}: 原版多出列 {extra_cols[:8]}{'…' if len(extra_cols) > 8 else ''}")

    key = "Filename"
    omap = {r.get(key, ""): r for r in orows}
    tmap = {r.get(key, ""): r for r in trows}
    only_ours = sorted(set(omap) - set(tmap))
    only_theirs = sorted(set(tmap) - set(omap))
    if only_ours:
        print(f"  {label}: 原版缺少这些行 {only_ours}")
    if only_theirs:
        print(f"  {label}: 原版多出这些行 {only_theirs}")

    diffs, cell_total = [], 0
    for name in sorted(set(omap) & set(tmap)):
        for col in sorted(okeys & tkeys):
            if col == key:
                continue
            a, b = omap[name].get(col, ""), tmap[name].get(col, "")
            if a == b:
                continue
            # 允许浮点尾部差异（例如 12.340000000000002 vs 12.34）按数值再试一次
            try:
                if tol > 0 and abs(float(a) - float(b)) <= tol:
                    continue
            except ValueError:
                pass
            cell_total += 1
            diffs.append((name, col, a, b))

    if not diffs:
        print(f"  {label}: ✅ 完全一致（{len(omap)} 行 × {len(okeys)-1} 列）")
        return 0
    print(f"  {label}: ❌ {cell_total} 个单元格不同")
    show = diffs if verbose else diffs[:12]
    for name, col, a, b in show:
        print(f"      {name:16s} {col:22s} 我={a:<12s} 原版={b}")
    if not verbose and len(diffs) > 12:
        print(f"      … 还有 {len(diffs)-12} 个（用 --verbose 全看）")
    return 1


def compare_streams(ours_dir, theirs_dir, verbose):
    ours = {f.replace("_MAT.txt", ""): os.path.join(ours_dir, f)
            for f in os.listdir(ours_dir) if f.endswith("_MAT.txt")}
    theirs = {f.replace("_MAT.txt", ""): os.path.join(theirs_dir, f)
              for f in os.listdir(theirs_dir) if f.endswith("_MAT.txt")}
    if not theirs:
        print("  L1 token 流：原版目录里没找到 *_MAT.txt，跳过")
        return 0

    bad = 0
    for name in sorted(ours):
        if name not in theirs:
            print(f"  L1 {name}: 原版缺少该文件")
            bad += 1
            continue
        a = [l.strip() for l in open(ours[name], encoding="utf-8").read().split("\n") if l.strip()]
        b = [l.replace("\r", "").strip() for l in open(theirs[name], encoding="utf-8",
                                                      errors="replace").read().split("\n") if l.strip()]
        if a == b:
            continue
        bad += 1
        print(f"  L1 {name}: ❌ 长度 {len(a)} vs {len(b)}")
        shown = 0
        for i in range(min(len(a), len(b))):
            if a[i] != b[i]:
                lo = max(0, i - 2)
                print(f"      第 {i+1} 个 token：")
                for j in range(lo, min(i + 3, min(len(a), len(b)))):
                    mark = "  ←" if j == i else ""
                    print(f"        我={a[j]:<28s} 原版={b[j]}{mark}")
                shown += 1
                if not verbose and shown >= 3:
                    print("      …（用 --verbose 看全部）")
                    break
    if bad == 0:
        print(f"  L1 token 流：✅ {len(ours)} 个文件逐词一致")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theirs", help="原版 MAT 输出所在目录")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--tol", type=float, default=0.0,
                    help="维度分允许的数值误差（默认 0：要求逐字节一致）")
    args = ap.parse_args()

    root = args.theirs
    if not os.path.isdir(root):
        sys.exit(f"目录不存在：{root}")

    print(f"原版输出：{root}")
    try:
        man = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                          "manifest.json")))
        print(f"语料：{len(man)} 个文件，{sum(v['words'] for v in man.values())} 词")
    except FileNotFoundError:
        pass

    fails = 0
    stats = find_file(root, "statistics", ".csv") or find_file(root, "corpus_statistics")
    zs = find_file(root, "zscores", ".csv") or find_file(root, "zscores")
    dims = find_file(root, "dimensions", ".csv") or find_file(root, "dimensions")

    print("\nL1 · token 流")
    mat_dirs = [d for d in (os.path.join(root, "MAT_GroundTruth"),
                            os.path.join(root, "MAT_" + os.path.basename(root.rstrip("/"))))
                if os.path.isdir(d)]
    if not mat_dirs:
        for dirpath, dirnames, _ in os.walk(root):
            for d in dirnames:
                if d.startswith("MAT_"):
                    mat_dirs.append(os.path.join(dirpath, d))
    if mat_dirs:
        fails += compare_streams(os.path.join(BASE, "stream"), mat_dirs[0], args.verbose)
    else:
        print("  没找到 MAT_* 目录（token 流比对跳过，只比统计）")

    print("\nL2 · Statistics（每 100 词频次）")
    if stats:
        fails += compare_csv(os.path.join(BASE, "csv", "Statistics_GroundTruth.csv"),
                             stats[0], "Statistics", args.verbose)
    else:
        print("  没找到 Statistics 文件")

    print("\nL3 · Zscores")
    if zs:
        fails += compare_csv(os.path.join(BASE, "csv", "Zscores_GroundTruth.csv"),
                             zs[0], "Zscores", args.verbose)
    else:
        print("  没找到 Zscores 文件")

    print("\nL3 · Dimensions")
    if dims:
        fails += compare_csv(os.path.join(BASE, "csv", "Dimensions_GroundTruth.csv"),
                             dims[0], "Dimensions", args.verbose, tol=args.tol)
    else:
        print("  没找到 Dimensions 文件")

    print("\n" + ("全部一致 ✅" if fails == 0 else f"共 {fails} 处不一致 ❌"))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
