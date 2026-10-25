#!/bin/zsh
# 打印当前 MARKETING_VERSION（唯一来源：Xcode 工程）。
# 构建脚本用它写进 Info.plist，避免两处版本号漂移。
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PBX="$ROOT/Multidimensional Analysis MacTag/Multidimensional Analysis MacTag.xcodeproj/project.pbxproj"
/usr/bin/python3 -c 'import re,sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"MARKETING_VERSION = ([0-9.]+);", src)
print(m.group(1) if m else "1.1.1")' "$PBX"
