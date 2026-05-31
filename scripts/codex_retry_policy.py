#!/usr/bin/env python3
"""Retry classification for Codex CLI wrapper failures."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Iterable


TRANSIENT_RE = re.compile(
    r"429|rate[\s._-]*limit|overloaded|throttl|temporar|unavailable|connection reset|timed out|timeout",
    re.IGNORECASE,
)
FAILURE_EVENT_TYPES = {"error", "session.failed", "turn.failed"}


def _iter_events(jsonl_text: str) -> Iterable[dict]:
    for raw_line in jsonl_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            yield payload


def _event_failure_messages(event: dict) -> list[str]:
    messages: list[str] = []
    event_type = event.get("type", "")
    if event_type in FAILURE_EVENT_TYPES:
        value = event.get("message")
        if isinstance(value, str) and value.strip():
            messages.append(value.strip())

    item = event.get("item")
    if isinstance(item, dict) and item.get("type") in FAILURE_EVENT_TYPES:
        value = item.get("message")
        if isinstance(value, str) and value.strip():
            messages.append(value.strip())

    return messages


def should_retry(exit_code: int, stderr_text: str, jsonl_text: str) -> bool:
    if exit_code == 0:
        return False

    if TRANSIENT_RE.search(stderr_text or ""):
        return True

    for event in _iter_events(jsonl_text):
        for message in _event_failure_messages(event):
            if TRANSIENT_RE.search(message):
                return True

    return False


def _read_text(path_str: str) -> str:
    if not path_str:
        return ""
    path = pathlib.Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exit-code", type=int, required=True)
    parser.add_argument("--stderr-path", default="")
    parser.add_argument("--jsonl-path", default="")
    args = parser.parse_args()

    result = should_retry(
        exit_code=args.exit_code,
        stderr_text=_read_text(args.stderr_path),
        jsonl_text=_read_text(args.jsonl_path),
    )
    print("true" if result else "false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
