#!/bin/bash
# Swift 移植版 vs Perl golden 的三层逐字节回归。
#
#   ./verify-swift.sh          debug 构建 + 全量比对
#   ./verify-swift.sh release  release 构建
#
# 三层：L1 token 流 / L2 Statistics / L3 Zscores+Dimensions，全部字符串比较。
set -euo pipefail
cd "$(dirname "$0")"

PKG="$(cd ../.. ; pwd)/Packages/MATCore"
CONFIG="${1:-debug}"
DEV="/Volumes/ML.Origin/Applications/Xcode.app/Contents/Developer"
OUT="build/verify-$CONFIG"

echo "== building MATCore ($CONFIG) =="
# --disable-sandbox：某些终端环境禁止嵌套 sandbox-exec，否则 manifest 编译会失败
DEVELOPER_DIR="$DEV" swift build --package-path "$PKG" -c "$CONFIG" --disable-sandbox >/dev/null

BIN="$PKG/.build/$CONFIG/matctl"
[ -x "$BIN" ] || { echo "missing binary: $BIN"; exit 1; }

fail=0
for c in rules rules2 rules3 bulk; do
  rm -rf "$OUT/$c"
  "$BIN" analyze --in "fixtures/$c/tagged" --out "$OUT/$c" --name "$c" >/dev/null
  if diff -r "$OUT/$c" "goldens/$c" >/dev/null 2>&1; then
    echo "OK    $c  (L1+L2+L3)"
  else
    echo "FAIL  $c"
    diff -r "$OUT/$c" "goldens/$c" | head -30
    fail=1
  fi
done

# clamp = on 的分支单独跑一次（它只影响维度，不影响 Zscores）
rm -rf "$OUT/clamp" "build/clamp-golden"
perl bin/run.pl --corpus fixtures/rules --work build/clamp-perl --out build/clamp-golden --clamp >/dev/null
"$BIN" analyze --in fixtures/rules/tagged --out "$OUT/clamp" --name rules --clamp >/dev/null
if diff -r "$OUT/clamp" build/clamp-golden >/dev/null 2>&1; then
  echo "OK    clamp"
else
  echo "FAIL  clamp"
  diff -r "$OUT/clamp" build/clamp-golden | head -20
  fail=1
fi

exit $fail
