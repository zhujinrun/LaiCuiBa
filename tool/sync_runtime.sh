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

# CPython 11.9 整个发行版（python.exe + Lib/site-packages，含 requests/lxml）。
# 39MB，只进工作区，不进 git（见 .gitignore）。
if [ -d "$SRC/python" ]; then
  mkdir -p "$HERE/assets/runtime/python"
  cp -r "$SRC/python/." "$HERE/assets/runtime/python/"
  echo "已同步 assets/runtime/python/（$(du -sh "$HERE/assets/runtime/python" | cut -f1)）"
else
  echo "缺少 $SRC/python（原版包不存在？）" >&2
fi

# Also drop the runtime next to the debug build output, where RuntimePaths
# resolves it from the executable's own directory. cat_host.js lives in assets
# and is copied verbatim (it is ours, not the original's).
for target in \
  "$HERE/build/windows/x64/runner/Debug/runtime/node" \
  "$HERE/build/windows/x64/runner/Release/runtime/node"; do
  if [ -d "$(dirname "$(dirname "$target")")" ]; then
    mkdir -p "$target"
    cp "$HERE/assets/runtime/node/node.exe" "$target/node.exe"
    cp "$HERE/assets/runtime/node/cat_host.js" "$target/cat_host.js"
    echo "已同步 $target"
  fi
done

# Python 运行时也要落到产物旁边，RuntimePaths 从 exe 目录找。宿主脚本
# `pyhost/` 同样要在，否则解释器在、协议没人说。
for root in \
  "$HERE/build/windows/x64/runner/Debug/runtime" \
  "$HERE/build/windows/x64/runner/Release/runtime"; do
  if [ ! -d "$(dirname "$root")" ]; then
    continue
  fi
  if [ -d "$HERE/assets/runtime/python" ]; then
    mkdir -p "$root/python"
    cp -r "$HERE/assets/runtime/python/." "$root/python/"
    echo "已同步 $root/python"
  fi
  mkdir -p "$root/pyhost"
  cp -r "$HERE/assets/runtime/pyhost/." "$root/pyhost/"
  echo "已同步 $root/pyhost"
done

echo "完成。node.exe / python 已就位（不提交到 git）。"
