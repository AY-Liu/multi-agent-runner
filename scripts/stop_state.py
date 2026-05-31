#!/usr/bin/env python3
"""Helpers for clearing running-agent state during a soft stop."""

from __future__ import annotations

import json
import pathlib
import sys


def read_status(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def mark_stopped(path: pathlib.Path) -> None:
    data = read_status(path)
    if data.get("state") == "running":
        data["state"] = "idle"
    data["pid"] = None
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: stop_state.py <status.json>", file=sys.stderr)
        return 1
    mark_stopped(pathlib.Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
