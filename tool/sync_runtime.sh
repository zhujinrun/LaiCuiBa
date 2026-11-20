#!/usr/bin/env bash
# 把原版包的运行时二进制同步进本工程（不进 git，只供构建/调试用）。
# 用法: bash tool/sync_runtime.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="/e/code/AndroidProjects/FengMi/BieCuiLe-1.0.6-windows-x64"

copy() {
  local from="$1" to="$2"
  if [ ! -f "$from" ]; then
    echo "缺少 $from（原版包不存在？）" >&2
    return 1
  fi
  mkdir -p "$(dirname "$to")"
  cp "$from" "$to"
  echo "已同步 $to"
}

copy "$SRC/node/node.exe" "$HERE/assets/runtime/node/node.exe"
echo "完成。node.exe 已就位（不提交到 git）。"
