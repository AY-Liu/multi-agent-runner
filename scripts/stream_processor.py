#!/usr/bin/env python3
"""
stream_processor.py -- Process claude -p stream-json output

Reads NDJSON from stdin (claude -p --output-format stream-json).
- Writes raw stream to <agent_dir>/stream.log
- Prints human-readable activity lines to stdout (for harness/user visibility)
- On final "result" event, writes full JSON to <agent_dir>/latest.json

Usage: claude -p ... --output-format stream-json | python3 stream_processor.py <agent_dir>
"""

import json
import sys
import os
from datetime import datetime, timezone

def now_ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def shorten(text, maxlen=120):
    text = text.replace('\n', ' ').strip()
    return text[:maxlen] + '...' if len(text) > maxlen else text

def describe_content_block(block):
    """Convert a content block to a human-readable one-liner."""
    btype = block.get('type', '')

    if btype == 'tool_use':
        name = block.get('name', '?')
        inp = block.get('input', {})
        if name == 'Bash':
            cmd = inp.get('command', '')
            return f"$ {shorten(cmd, 100)}"
        elif name == 'Read':
            return f"Reading {inp.get('file_path', '?')}"
        elif name == 'Write':
            return f"Writing {inp.get('file_path', '?')}"
        elif name == 'Edit':
            return f"Editing {inp.get('file_path', '?')}"
        elif name == 'Grep':
            return f"Searching: {inp.get('pattern', '?')}"
        elif name == 'Glob':
            return f"Glob: {inp.get('pattern', '?')}"
        elif name == 'WebSearch':
            return f"Web search: {inp.get('query', '?')}"
        elif name == 'WebFetch':
            return f"Fetching: {shorten(inp.get('url', '?'), 80)}"
        else:
            return f"Tool: {name}"

    elif btype == 'text':
        text = block.get('text', '')
        if text.strip():
            return f"  {shorten(text, 150)}"
        return None

    elif btype == 'thinking':
        text = block.get('thinking', '')
        if text.strip():
            return f"(thinking: {shorten(text, 80)})"
        return None

    return None

def main():
    if len(sys.argv) < 2:
        print("Usage: stream_processor.py <agent_dir>", file=sys.stderr)
        sys.exit(1)

    agent_dir = sys.argv[1]
    agent_name = os.path.basename(agent_dir)
    stream_log = os.path.join(agent_dir, 'stream.log')
    latest_json = os.path.join(agent_dir, 'latest.json')

    os.makedirs(agent_dir, exist_ok=True)

    result_data = None
    line_count = 0

    with open(stream_log, 'w') as log_f:
        for raw_line in sys.stdin:
            raw_line = raw_line.rstrip('\n')
            if not raw_line:
                continue

            # Write raw to stream log
            log_f.write(raw_line + '\n')
            log_f.flush()
            line_count += 1

            # Parse JSON
            try:
                event = json.loads(raw_line)
            except json.JSONDecodeError:
                continue

            etype = event.get('type', '')
            esubtype = event.get('subtype', '')

            # System events worth showing to user
            if etype == 'system':
                if esubtype == 'api_retry':
                    attempt = event.get('attempt', '?')
                    err = event.get('error', 'unknown')
                    status = event.get('error_status', '?')
                    delay = event.get('retry_delay_ms', 0)
                    print(f"    [{agent_name}] API retry #{attempt}: {err} (HTTP {status}), wait {delay/1000:.1f}s", flush=True)
                elif esubtype == 'init':
                    model = event.get('model', '?')
                    print(f"    [{agent_name}] Session started (model: {model})", flush=True)
                continue

            # Final result
            if etype == 'result':
                result_data = event
                # Extract subresult for compatibility with json output format
                result_json = {
                    'session_id': event.get('session_id', ''),
                    'result': event.get('result', ''),
                    'total_cost_usd': event.get('cost_usd', event.get('total_cost_usd', 0)),
                    'num_turns': event.get('num_turns', 0),
                    'is_error': event.get('is_error', False),
                }
                with open(latest_json, 'w') as f:
                    json.dump(result_json, f, ensure_ascii=False, indent=2)

                cost = result_json['total_cost_usd']
                turns = result_json['num_turns']
                print(f"    [{agent_name}] DONE. cost=${cost:.4f} turns={turns}", flush=True)
                continue

            # Assistant message with content blocks
            if etype == 'assistant':
                msg = event.get('message', {})
                content = msg.get('content', [])
                for block in content:
                    desc = describe_content_block(block)
                    if desc:
                        print(f"    [{agent_name}] {desc}", flush=True)
                continue

            # Tool result (brief)
            if etype == 'tool_result':
                # Don't print full tool results (too verbose), just note it
                pass

    # If we never got a result event, write what we have
    if result_data is None and not os.path.exists(latest_json):
        with open(latest_json, 'w') as f:
            json.dump({
                'session_id': '',
                'result': '',
                'total_cost_usd': 0,
                'num_turns': 0,
                'is_error': True,
            }, f, indent=2)
        print(f"    [{agent_name}] WARNING: stream ended without result event", flush=True)

if __name__ == '__main__':
    main()
