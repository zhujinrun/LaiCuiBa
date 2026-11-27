#!/usr/bin/env python3
"""Small helpers for the tag-driven GitHub release workflow.

The workflow only needs two things that are easy to get wrong in shell one
liners: the pushed tag must describe the version in pubspec.yaml, and the
release body must come from the matching CHANGELOG.md section.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / "pubspec.yaml"
CHANGELOG = ROOT / "CHANGELOG.md"

VERSION_LINE = re.compile(
    r"^version:\s*(?P<version>\d+\.\d+\.\d+(?:\+\d+)?)\s*$", re.MULTILINE
)
TAG = re.compile(r"^v(?P<version>\d+\.\d+\.\d+)$")


def fail(message: str) -> None:
    print(f"ci_release: {message}", file=sys.stderr)
    raise SystemExit(1)


def pubspec_version() -> str:
    text = PUBSPEC.read_text(encoding="utf-8")
    match = VERSION_LINE.search(text)
    if match is None:
        fail("pubspec.yaml has no semantic version line")
    return match.group("version")


def base_version(version: str) -> str:
    return version.split("+", 1)[0]


def check_tag(tag: str) -> None:
    match = TAG.fullmatch(tag)
    if match is None:
        fail(f"tag {tag!r} must look like vX.Y.Z")
    expected = base_version(pubspec_version())
    if match.group("version") != expected:
        fail(f"tag {tag!r} does not match pubspec version {expected}")
    print(f"tag {tag} matches pubspec version {expected}")


def changelog_body(version: str) -> str:
    text = CHANGELOG.read_text(encoding="utf-8")
    pattern = re.compile(
        r"^## \[" + re.escape(version) + r"\][^\n]*\n(?P<body>.*?)"
        r"(?=^## \[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if match is None:
        fail(f"CHANGELOG.md has no section for {version}")
    body = match.group("body").strip()
    if not body:
        fail(f"CHANGELOG.md section for {version} is empty")
    return body


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("version")

    check = sub.add_parser("check-tag")
    check.add_argument("tag")

    body = sub.add_parser("release-body")
    body.add_argument("version")
    body.add_argument("--output", type=Path)

    args = parser.parse_args()
    if args.command == "version":
        print(base_version(pubspec_version()))
        return
    if args.command == "check-tag":
        check_tag(args.tag)
        return

    text = changelog_body(args.version)
    if args.output is None:
        sys.stdout.write(text + "\n")
    else:
        args.output.write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
