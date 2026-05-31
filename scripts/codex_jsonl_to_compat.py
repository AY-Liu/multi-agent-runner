#!/usr/bin/env python3
"""
Convert Codex JSONL event streams into the small compatibility JSON shape
expected by the multi-agent-runner harness.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Iterable, Optional


def read_jsonl(path: pathlib.Path) -> list[dict]:
    events = []
    if not path.exists():
        return events

    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                events.append(payload)
    return events


def read_optional_text(path_str: Optional[str]) -> str:
    if not path_str:
        return ""
    path = pathlib.Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def extract_message_from_item(item: dict) -> str:
    text = item.get("text")
    if isinstance(text, str) and text.strip():
        return text.strip()

    content = item.get("content")
    if isinstance(content, list):
        fragments = []
        for block in content:
            if not isinstance(block, dict):
                continue
            candidate = block.get("text")
            if isinstance(candidate, str) and candidate.strip():
                fragments.append(candidate.strip())
        if fragments:
            return "\n\n".join(fragments)

    return ""


def parse_events(events: Iterable[dict], output_text: str = "", stderr_text: str = "", exit_code: int = 0) -> dict:
    session_id = ""
    result = output_text.strip()
    total_cost_usd = 0.0
    num_turns = 0
    is_error = exit_code != 0
    error_messages: list[str] = []

    for event in events:
        event_type = event.get("type", "")

        if event_type == "thread.started":
            thread_id = event.get("thread_id")
            if isinstance(thread_id, str) and thread_id.strip():
                session_id = thread_id.strip()

        elif event_type == "turn.started":
            num_turns += 1

        elif event_type == "turn.completed":
            usage = event.get("usage")
            if isinstance(usage, dict):
                cost = usage.get("total_cost_usd")
                if isinstance(cost, (int, float)):
                    total_cost_usd += float(cost)

        elif event_type in {"item.completed", "item.started"}:
            item = event.get("item")
            if isinstance(item, dict) and item.get("type") == "agent_message":
                message = extract_message_from_item(item)
                if message:
                    result = message

        elif event_type in {"error", "turn.failed", "session.failed"}:
            is_error = True
            message = event.get("message")
            if isinstance(message, str) and message.strip():
                error_messages.append(message.strip())

    if not result and error_messages:
        result = "\n".join(error_messages)
    if not result and stderr_text.strip():
        result = stderr_text.strip()

    return {
        "session_id": session_id,
        "result": result,
        "total_cost_usd": total_cost_usd,
        "num_turns": num_turns,
        "is_error": is_error,
    }


def build_compat(jsonl_path: pathlib.Path, output_md: Optional[str], stderr_path: Optional[str], exit_code: int) -> dict:
    events = read_jsonl(jsonl_path)
    output_text = read_optional_text(output_md)
    stderr_text = read_optional_text(stderr_path)
    return parse_events(events, output_text=output_text, stderr_text=stderr_text, exit_code=exit_code)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("jsonl_path")
    parser.add_argument("--output-md")
    parser.add_argument("--stderr-path")
    parser.add_argument("--exit-code", type=int, default=0)
    args = parser.parse_args()

    compat = build_compat(
        pathlib.Path(args.jsonl_path),
        output_md=args.output_md,
        stderr_path=args.stderr_path,
        exit_code=args.exit_code,
    )
    json.dump(compat, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
