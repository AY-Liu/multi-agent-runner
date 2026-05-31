#!/usr/bin/env python3
"""Resolve allowed Codex reasoning effort values."""

from __future__ import annotations

import argparse
import sys


VALID_EFFORTS = {"low", "medium", "high"}


def normalize_effort(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if normalized in VALID_EFFORTS:
        return normalized
    return None


def resolve_effort(override: str | None, default: str | None) -> str:
    return normalize_effort(override) or normalize_effort(default) or "high"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--default")
    parser.add_argument("--override")
    args = parser.parse_args()
    print(resolve_effort(args.override, args.default))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
