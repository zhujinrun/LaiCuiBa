#!/usr/bin/env bash
# Assemble the local 猫源 runtimes from this machine's version managers.
#
# The binaries stay git-ignored: only the host scripts are tracked. By default
# this script looks for Node 18.x and CPython 3.11.x, which are the versions
# the original app shipped with. Override with LAI_CUI_BA_NODE / LAI_CUI_BA_PYTHON
# when those exact installations live somewhere else.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
NODE_DEST="$HERE/assets/runtime/node"
PY_DEST="$HERE/assets/runtime/python"

PY_DEPS=(
  requests==2.34.2
  lxml==6.1.3
  pycryptodome==3.24.1
  pyquery==2.1.0
  beautifulsoup4==4.15.0
)

pick_node() {
  local candidate version
  for candidate in \
    "${LAI_CUI_BA_NODE:-}" \
    "/d/Program/nvm/installs/v18.20.8/node.exe" \
    "$(command -v node || true)"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    version="$("$candidate" --version 2>/dev/null || true)"
    case "$version" in
      v18.*) printf '%s\n' "$candidate"; return 0 ;;
    esac
  done
  return 1
}

pick_python() {
  local candidate version
  for candidate in \
    "${LAI_CUI_BA_PYTHON:-}" \
    "/d/Program/pvm/v3.11.9/python.exe" \
    "$(command -v python3.11 || true)" \
    "$(command -v python || true)"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    version="$("$candidate" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
    if [[ "$version" == "3.11" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

NODE_BIN="$(pick_node || true)"
PY_BIN="$(pick_python || true)"

if [[ -z "$NODE_BIN" ]]; then
  echo "找不到 Node 18.x。设置 LAI_CUI_BA_NODE 指向 node.exe。" >&2
  exit 1
fi
if [[ -z "$PY_BIN" ]]; then
  echo "找不到 CPython 3.11.x。设置 LAI_CUI_BA_PYTHON 指向 python.exe。" >&2
  exit 1
fi

echo "Node: $NODE_BIN ($("$NODE_BIN" --version))"
echo "Python: $PY_BIN ($("$PY_BIN" --version 2>&1))"

# ---------------------------------------------------------------------------
# Node: only node.exe is needed; the hosts themselves live in this repo.
# ---------------------------------------------------------------------------
mkdir -p "$NODE_DEST"
cp "$NODE_BIN" "$NODE_DEST/node.exe"
echo "已同步 $NODE_DEST（宿主脚本已在同目录）"

# ---------------------------------------------------------------------------
# Python: portable stdlib + DLLs + pinned site-packages. A full CPython
# installation also carries pip/venv/test files we do not need in a bundle.
# ---------------------------------------------------------------------------
PY_ROOT="$(dirname "$PY_BIN")"
mkdir -p "$PY_DEST/Lib" "$PY_DEST/DLLs"
cp "$PY_BIN" "$PY_DEST/python.exe"
for file in pythonw.exe python3.dll python311.dll vcruntime140.dll vcruntime140_1.dll; do
  [[ -f "$PY_ROOT/$file" ]] && cp "$PY_ROOT/$file" "$PY_DEST/$file"
done
cp -r "$PY_ROOT/DLLs/." "$PY_DEST/DLLs/"
cp -r "$PY_ROOT/Lib/." "$PY_DEST/Lib/"
rm -rf \
  "$PY_DEST/Lib/site-packages" \
  "$PY_DEST/Lib/test" \
  "$PY_DEST/Lib/idlelib" \
  "$PY_DEST/Lib/lib2to3" \
  "$PY_DEST/Lib/turtledemo" \
  "$PY_DEST/Lib/ensurepip"
mkdir -p "$PY_DEST/Lib/site-packages"

PY_SITE_WIN="$(cygpath -w "$PY_DEST/Lib/site-packages")"
"$PY_BIN" -m pip install --target "$PY_SITE_WIN" "${PY_DEPS[@]}"

printf '%s\n' \
  'python311.zip' \
  '.' \
  'Lib' \
  'DLLs' \
  'Lib\site-packages' \
  'import site' \
  > "$PY_DEST/python311._pth"

"$NODE_DEST/node.exe" --version
"$PY_DEST/python.exe" -c 'import requests, lxml, pyquery, Crypto; print("python runtime ok")'
echo "已同步 $PY_DEST（$(du -sh "$PY_DEST" | cut -f1)）"

# ---------------------------------------------------------------------------
# Copy the assembled runtimes next to debug/release executables as well:
# RuntimePaths resolves them from the executable's own directory.
# ---------------------------------------------------------------------------
for target in \
  "$HERE/build/windows/x64/runner/Debug/runtime/node" \
  "$HERE/build/windows/x64/runner/Release/runtime/node"; do
  if [[ -d "$(dirname "$(dirname "$target")")" ]]; then
    mkdir -p "$target"
    if ! cp "$NODE_DEST/node.exe" "$target/node.exe"; then
      echo "跳过 $target/node.exe（可能正在运行，被系统占用）" >&2
    fi
    cp "$NODE_DEST/"*.js "$target/"
    echo "已同步 $target"
  fi
done

for root in \
  "$HERE/build/windows/x64/runner/Debug/runtime" \
  "$HERE/build/windows/x64/runner/Release/runtime"; do
  if [[ -d "$(dirname "$root")" ]]; then
    mkdir -p "$root/python" "$root/pyhost"
    if ! cp -r "$PY_DEST/." "$root/python/"; then
      echo "跳过 $root/python（有文件被占用，源 runtime 仍已更新）" >&2
    fi
    cp -r "$HERE/assets/runtime/pyhost/." "$root/pyhost/"
    echo "已同步 $root"
  fi
done

echo "完成。Node / Python 运行时已就位（不提交到 git）。"
