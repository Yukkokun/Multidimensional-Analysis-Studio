#!/bin/bash
# 生成 / 校验 golden 输出。
#
#   ./run-goldens.sh          重新生成 goldens/ 与 generated/
#   ./run-goldens.sh --check   只校验：结果必须与 goldens/ 完全一致（CI 用）
#
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-generate}"
CORPORA=(rules rules2 rules3 bulk)

if [ "$MODE" = "--check" ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  rc=0
  for c in "${CORPORA[@]}"; do
    perl bin/run.pl --corpus "fixtures/$c" --work "$TMP/work_$c" --out "$TMP/out_$c" >/dev/null
    if diff -r "goldens/$c" "$TMP/out_$c" >/dev/null; then
      echo "OK    $c"
    else
      echo "FAIL  $c"
      diff -r "goldens/$c" "$TMP/out_$c" | head -40
      rc=1
    fi
  done
  # 常量表也要保持一致，否则 Swift 侧会和 golden 脱节
  cp -r generated "$TMP/generated.bak"
  perl bin/extract-constants.pl >/dev/null
  if diff -r "$TMP/generated.bak" generated >/dev/null; then
    echo "OK    constants"
  else
    echo "FAIL  constants"
    diff -r "$TMP/generated.bak" generated | head -20
    rc=1
  fi
  exit $rc
fi

for c in "${CORPORA[@]}"; do
  perl bin/run.pl --corpus "fixtures/$c" --work "build/parity/$c" --out "goldens/$c"
done
perl bin/extract-constants.pl
echo
echo "goldens: $(find goldens -type f | wc -l | tr -d ' ') files"
