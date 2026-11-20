#!/usr/bin/env python3
"""Pulls the site list out of a catvod "js" source bundle.

豆儿猫源 (and its siblings) ship no JSON config: `index.config.js` only carries
the theme, and the sites live inside `index.js` as hundreds of spider modules,
each opening with `meta:{key:"duoduo",name:"\u300C\u76D8\u300D\u591A\u591A",type:3}`.
The host prefixes those keys with `nodejs_`, which is why the original stores
`homeSite: nodejs_jianpian` in its own preferences.

Two blocks are not content sites and are dropped:
  * `baseset`  -- the 「设」配置 panel (a fake site that opens settings)
  * `webpage`  -- type 7, the 网页入口 row
61 - 2 = the 59 sites the original lists.

Usage:
  python tool/extract_config_sites.py                 # fetch the douer bundle
  python tool/extract_config_sites.py <file-or-url>    # any index.js
  python tool/extract_config_sites.py --json           # dump JSON instead

The output is meant to be pasted into `_demoSites` in lib/services/store.dart;
re-run it when the upstream bundle bumps so the seeded source stays honest.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request

DEFAULT_URL = (
    "https://gh-proxy.com/raw.githubusercontent.com/Darklessing/catvod/"
    "refs/heads/main/douer/index.js"
)
SKIP_KEYS = {"baseset", "webpage"}

# `meta:{key:"x",name:"<escaped>",type:3}` -- names are full of \uXXXX, and a
# couple of entries use a byte escape (\xB2) that plain json.loads rejects.
META_RE = re.compile(r'meta:\{key:"([^"]+)",name:"((?:[^"]|\\.)*)",type:([0-9]+)')
ESCAPE_RE = re.compile(r"\\(u[0-9A-Fa-f]{4}|x[0-9A-Fa-f]{2}|.)")


def decode(raw: str) -> str:
    def repl(match: re.Match[str]) -> str:
        token = match.group(1)
        if token.startswith("u"):
            return chr(int(token[1:], 16))
        if token.startswith("x"):
            return chr(int(token[1:], 16))
        return token

    return ESCAPE_RE.sub(repl, raw)


def load(target: str) -> str:
    if target.startswith(("http://", "https://")):
        with urllib.request.urlopen(target, timeout=60) as response:
            return response.read().decode("utf-8", "ignore")
    with open(target, encoding="utf-8", errors="ignore") as handle:
        return handle.read()


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = "--json" in sys.argv[1:]
    text = load(args[0] if args else DEFAULT_URL)

    sites = []
    seen = set()
    for key, name, kind in META_RE.findall(text):
        if key in SKIP_KEYS or key in seen:
            continue
        seen.add(key)
        sites.append({"key": f"nodejs_{key}", "name": decode(name), "type": kind})

    if not sites:
        print("no meta blocks found -- wrong file?", file=sys.stderr)
        return 1

    if as_json:
        print(json.dumps(sites, ensure_ascii=False, indent=1))
        return 0

    print(f"// {len(sites)} sites, extracted from {args[0] if args else DEFAULT_URL}")
    for site in sites:
        print(
            "    SiteInfo(key: '{key}', name: '{name}', type: '{type}', "
            "api: '{key}'),".format(**site)
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
