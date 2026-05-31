#!/usr/bin/env bash
# =================================================================
# Multi Agent Runner -- Shared Utilities
# =================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT/scripts"
PROVIDERS_DIR="$ROOT/providers"
PROMPTS_DIR="$ROOT/prompts/roles"
TEMPLATES_DIR="$ROOT/prompts/templates"
AGENTS_DIR="$ROOT/agents"
STATE_DIR="$ROOT/state"
DECISIONS_DIR="$STATE_DIR/decisions"
LOG_DIR="$ROOT/logs"
OUTPUT_DIR="$ROOT/output"
TMP_DIR="$ROOT/tmp"

CLAW_PROVIDER="${MULTI_AGENT_PROVIDER:-${CLAW_PROVIDER:-codex}}"
MULTI_AGENT_PROVIDER="$CLAW_PROVIDER"
export CLAW_PROVIDER MULTI_AGENT_PROVIDER
case "$CLAW_PROVIDER" in
  codex|claude) ;;
  *)
    echo "ERROR: unknown provider: $CLAW_PROVIDER" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

PROVIDER_DIR="$PROVIDERS_DIR/$CLAW_PROVIDER"
PROVIDER_FILE="$PROVIDER_DIR/provider.sh"
[ -f "$PROVIDER_FILE" ] || {
  echo "ERROR: provider implementation missing: $PROVIDER_FILE" >&2
  return 1 2>/dev/null || exit 1
}

# Load user env
set +eu
source "$HOME/.bashrc" 2>/dev/null || true
set -eu

source "$PROVIDER_FILE"

mkdir -p "$STATE_DIR" "$DECISIONS_DIR" "$LOG_DIR" "$OUTPUT_DIR" "$TMP_DIR" "$PROMPTS_DIR"

CLAW_CLAUDE_PRIMARY_MODEL="${MULTI_AGENT_CLAUDE_PRIMARY_MODEL:-${CLAW_CLAUDE_PRIMARY_MODEL:-opus}}"
CLAW_CLAUDE_FALLBACK_MODEL="${MULTI_AGENT_CLAUDE_FALLBACK_MODEL:-${CLAW_CLAUDE_FALLBACK_MODEL:-sonnet}}"
CLAW_CLAUDE_FALLBACK_AFTER="${MULTI_AGENT_CLAUDE_FALLBACK_AFTER:-${CLAW_CLAUDE_FALLBACK_AFTER:-1}}"
MULTI_AGENT_CLAUDE_PRIMARY_MODEL="$CLAW_CLAUDE_PRIMARY_MODEL"
MULTI_AGENT_CLAUDE_FALLBACK_MODEL="$CLAW_CLAUDE_FALLBACK_MODEL"
MULTI_AGENT_CLAUDE_FALLBACK_AFTER="$CLAW_CLAUDE_FALLBACK_AFTER"
export CLAW_CLAUDE_PRIMARY_MODEL CLAW_CLAUDE_FALLBACK_MODEL CLAW_CLAUDE_FALLBACK_AFTER
export MULTI_AGENT_CLAUDE_PRIMARY_MODEL MULTI_AGENT_CLAUDE_FALLBACK_MODEL MULTI_AGENT_CLAUDE_FALLBACK_AFTER

reset_runtime_state() {
  rm -rf "$AGENTS_DIR" "$STATE_DIR" "$LOG_DIR" "$OUTPUT_DIR" "$TMP_DIR" "$PROMPTS_DIR"
  mkdir -p "$AGENTS_DIR" "$STATE_DIR" "$DECISIONS_DIR" "$LOG_DIR" "$OUTPUT_DIR" "$TMP_DIR" "$PROMPTS_DIR"
}

ensure_provider_cli() {
  provider_check_cli
}

# --- Timestamps ---

ts()      { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
ts_file() { date -u +"%Y%m%dT%H%M%SZ"; }

seconds_since() {
  local iso="$1"
  if [ -z "$iso" ] || [ "$iso" = "null" ]; then echo 999999; return; fi
  python3 -c "
import sys
from datetime import datetime, timezone
try:
    t = datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))
    now = datetime.now(timezone.utc)
    print(int((now - t).total_seconds()))
except: print(999999)
" "$iso"
}

# --- Logging ---

log() {
  echo "[$(ts)] $*" | tee -a "$LOG_DIR/progress.log"
}

hlog() {
  echo "[$(ts)] [HARNESS] $*" | tee -a "$LOG_DIR/harness.log"
}

activity_monitor_stderr_state() {
  local stderr_file="$1"
  local previous_line="${2:-}"
  local limit="${3:-80}"
  local label="${4:-stderr: }"

  python3 - "$stderr_file" "$previous_line" "$limit" "$label" <<'PY'
from __future__ import annotations

import pathlib
import sys

stderr_path = pathlib.Path(sys.argv[1])
previous_line = sys.argv[2]
limit = int(sys.argv[3])
label = sys.argv[4]

current_line = ""
if stderr_path.exists():
    try:
        lines = stderr_path.read_text(encoding="utf-8").splitlines()
    except Exception:
        lines = []
    if lines:
        current_line = lines[-1][:limit]

suffix = ""
if current_line and current_line != previous_line:
    suffix = f" | {label}{current_line}"

print(current_line)
print(suffix)
PY
}

activity_monitor_should_continue() {
  local owner_pid="$1"
  local status_file="${2:-}"

  python3 - "$owner_pid" "$status_file" <<'PY'
from __future__ import annotations

import json
import os
import pathlib
import sys

owner_pid = int(sys.argv[1])
status_path = pathlib.Path(sys.argv[2]) if sys.argv[2] else None

alive = True
try:
    os.kill(owner_pid, 0)
except OSError:
    alive = False

if not alive:
    print("false")
    raise SystemExit(0)

if status_path and status_path.exists():
    try:
        data = json.loads(status_path.read_text(encoding="utf-8"))
    except Exception:
        data = {}
    state = data.get("state")
    if state not in (None, "", "running"):
        print("false")
        raise SystemExit(0)

print("true")
PY
}

# --- Provider retry helpers ---

claude_retry_reason() {
  local out_file="$1"
  local err_file="$2"
  local rc="$3"

  python3 - "$out_file" "$err_file" "$rc" <<'PY'
from __future__ import annotations

import json
import pathlib
import sys

out_path = pathlib.Path(sys.argv[1])
err_path = pathlib.Path(sys.argv[2])
rc = int(sys.argv[3])

tokens = ("429", "rate", "负载", "饱和", "overloaded", "throttl")

def is_retryable(text: str) -> bool:
    lower = text.lower()
    return any(token.lower() in lower for token in tokens)

if out_path.exists():
    try:
        payload = json.loads(out_path.read_text(encoding="utf-8"))
    except Exception:
        payload = {}
    result = str(payload.get("result", ""))
    if payload.get("is_error") and is_retryable(result):
        print("429/rate-limit")
        raise SystemExit(0)

stderr_text = ""
if err_path.exists():
    try:
        stderr_text = err_path.read_text(encoding="utf-8")
    except Exception:
        stderr_text = ""

if is_retryable(stderr_text):
    print("429/rate-limit")
elif rc == 0:
    print("")
elif stderr_text.strip():
    print("")
else:
    print("__generic_nonzero__")
PY
}

claude_retry() {
  local out_file="$1"; shift
  local err_file="$1"; shift
  local agent_name="$1"; shift
  local mode="$1"; shift
  local prompt="$1"; shift
  local -a base_args=("$@")
  local attempt=0
  local wait_base=30
  local retryable_failures=0
  local primary_model="${CLAW_CLAUDE_PRIMARY_MODEL:-opus}"
  local fallback_model="${CLAW_CLAUDE_FALLBACK_MODEL:-sonnet}"
  local fallback_after="${CLAW_CLAUDE_FALLBACK_AFTER:-1}"
  local current_model="$primary_model"
  local generic_nonzero_tag="__generic_nonzero__"

  case "$fallback_after" in
    ''|*[!0-9]*)
      fallback_after=1
      ;;
  esac

  while true; do
    attempt=$((attempt + 1))
    local -a cmd_args=("${base_args[@]}")
    if [ -n "$current_model" ]; then
      cmd_args+=(--model "$current_model")
    fi
    cmd_args+=("$prompt")

    claude "${cmd_args[@]}" > "$out_file" 2>"$err_file"
    local rc=$?
    local retry_reason
    retry_reason="$(claude_retry_reason "$out_file" "$err_file" "$rc")"

    if [ -z "$retry_reason" ]; then
      return $rc
    fi

    if [ "$retry_reason" = "$generic_nonzero_tag" ] && [ $attempt -gt 1 ]; then
      return $rc
    fi

    if [ "$retry_reason" != "$generic_nonzero_tag" ]; then
      retryable_failures=$((retryable_failures + 1))
    fi

    local wait_time=$((wait_base * attempt))
    [ $wait_time -gt 300 ] && wait_time=300

    if [ "$retry_reason" = "$generic_nonzero_tag" ]; then
      retry_reason="nonzero-without-stderr"
    fi

    log "[RETRY] Claude agent=$agent_name mode=$mode attempt=$attempt model=$current_model failed ($retry_reason). Retrying in ${wait_time}s..."
    hlog "claude_retry: agent=$agent_name mode=$mode attempt=$attempt model=$current_model failed ($retry_reason). Waiting ${wait_time}s..."

    if [ -n "$fallback_model" ] \
      && [ "$fallback_model" != "$current_model" ] \
      && [ "$retry_reason" != "nonzero-without-stderr" ] \
      && [ "$retryable_failures" -ge "$fallback_after" ]; then
      log "[RETRY] Claude agent=$agent_name mode=$mode switching model $current_model -> $fallback_model after $retryable_failures retryable failures."
      hlog "claude_retry: agent=$agent_name mode=$mode switching model $current_model -> $fallback_model after $retryable_failures retryable failures."
      current_model="$fallback_model"
    fi

    sleep "$wait_time"
  done
}

codex_retry() {
  local jsonl_file="$1"; shift
  local compat_file="$1"; shift
  local output_md="$1"; shift
  local err_file="$1"; shift
  local attempt=0
  local wait_base=30

  while true; do
    : > "$jsonl_file"
    : > "$err_file"
    attempt=$((attempt + 1))
    codex "$@" < /dev/null > "$jsonl_file" 2>"$err_file"
    local rc=$?

    python3 "$SCRIPTS_DIR/codex_jsonl_to_compat.py" \
      "$jsonl_file" \
      --output-md "$output_md" \
      --stderr-path "$err_file" \
      --exit-code "$rc" > "$compat_file"

    local retryable
    retryable="$(python3 "$SCRIPTS_DIR/codex_retry_policy.py" \
      --exit-code "$rc" \
      --stderr-path "$err_file" \
      --jsonl-path "$jsonl_file")"

    if [ "$retryable" != "true" ]; then
      return $rc
    fi

    local wait_time=$((wait_base * attempt))
    [ $wait_time -gt 300 ] && wait_time=300
    log "[RETRY] Attempt $attempt hit a transient Codex failure. Retrying in ${wait_time}s..."
    hlog "codex_retry: attempt $attempt hit a retryable error. Waiting ${wait_time}s..."
    sleep "$wait_time"
  done
}

# --- JSON Helpers ---

json_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || { echo ""; return; }
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2])
    print('' if v is None else v)
except: print('')
" "$file" "$key"
}

json_set() {
  local file="$1" key="$2" value="$3"
  python3 -c "
import json, sys
f = sys.argv[1]
try: d = json.load(open(f))
except: d = {}
v = sys.argv[3]
if v == 'true': v = True
elif v == 'false': v = False
elif v == 'null': v = None
elif v.isdigit(): v = int(v)
d[sys.argv[2]] = v
json.dump(d, open(f, 'w'), ensure_ascii=False, indent=2)
" "$file" "$key" "$value"
}

# --- Path Helpers ---

agent_dir()         { echo "$AGENTS_DIR/$1"; }
agent_status_file() { echo "$AGENTS_DIR/$1/status.json"; }
agent_pid_file()    { echo "$AGENTS_DIR/$1/pid"; }
agent_runs_dir()    { echo "$AGENTS_DIR/$1/runs"; }
agent_jsonl_file()  { echo "$AGENTS_DIR/$1/latest.jsonl"; }
decision_file()     { echo "$DECISIONS_DIR/latest.json"; }
harness_state_file(){ echo "$STATE_DIR/harness.json"; }

# --- Session Management ---

session_file() {
  echo "$AGENTS_DIR/$1/session_id"
}

provider_session_file() {
  echo "$AGENTS_DIR/$1/session_id.$2"
}

read_text_file_stripped() {
  local file="$1"
  [ -f "$file" ] || { echo ""; return; }
  python3 -c "
from pathlib import Path
import sys
try:
    print(Path(sys.argv[1]).read_text(encoding='utf-8').strip())
except Exception:
    print('')
" "$file" 2>/dev/null
}

detect_session_provider() {
  local agent="$1"
  python3 - "$AGENTS_DIR/$agent" "$CLAW_PROVIDER" <<'PY'
from __future__ import annotations

import json
import pathlib
import sys

agent_dir = pathlib.Path(sys.argv[1])
current_provider = sys.argv[2]
providers = ("codex", "claude")


def read_text(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except Exception:
        return ""


def load_json(path: pathlib.Path) -> dict | None:
    raw = read_text(path)
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def classify_json(data: dict | None) -> str:
    if not data:
        return ""

    keys = set(data)
    claude_markers = {
        "subtype",
        "stop_reason",
        "usage",
        "modelUsage",
        "permission_denials",
        "terminal_reason",
        "uuid",
    }
    if data.get("type") == "result" or keys.intersection(claude_markers):
        return "claude"

    if "session_id" in keys and (
        "result" in keys or "output" in keys or "response" in keys or "content" in keys or "text" in keys or "is_error" in keys
    ):
        return "codex"

    return ""


def classify_from_files() -> str:
    latest_json = agent_dir / "latest.json"
    if latest_json.exists():
        provider = classify_json(load_json(latest_json))
        if provider:
            return provider

    runs_dir = agent_dir / "runs"
    if runs_dir.exists():
        for path in sorted(runs_dir.glob("*.json"), reverse=True):
            provider = classify_json(load_json(path))
            if provider:
                return provider

    latest_jsonl = agent_dir / "latest.jsonl"
    if latest_jsonl.exists() and latest_jsonl.stat().st_size > 0:
        return "codex"

    if runs_dir.exists():
        for path in sorted(runs_dir.glob("*.jsonl"), reverse=True):
            if path.stat().st_size > 0:
                return "codex"

    return ""


current_path = agent_dir / f"session_id.{current_provider}"
if read_text(current_path):
    print(current_provider)
    raise SystemExit(0)

for provider in providers:
    if provider == current_provider:
        continue
    if read_text(agent_dir / f"session_id.{provider}"):
        print(provider)
        raise SystemExit(0)

if not read_text(agent_dir / "session_id"):
    print("")
    raise SystemExit(0)

print(classify_from_files())
PY
}

get_session_for_provider() {
  local agent="$1"
  local provider="$2"
  local sid
  sid="$(read_text_file_stripped "$(provider_session_file "$agent" "$provider")")"
  if [ -n "$sid" ]; then
    echo "$sid"
    return
  fi

  local legacy_sid
  legacy_sid="$(read_text_file_stripped "$(session_file "$agent")")"
  [ -n "$legacy_sid" ] || { echo ""; return; }

  local detected_provider
  detected_provider="$(detect_session_provider "$agent")"
  if [ "$detected_provider" = "$provider" ]; then
    echo "$legacy_sid"
  else
    echo ""
  fi
}

get_session() {
  get_session_for_provider "$1" "$CLAW_PROVIDER"
}

provider_switch_handoff() {
  local agent="$1"
  local current_sid
  current_sid="$(read_text_file_stripped "$(provider_session_file "$agent" "$CLAW_PROVIDER")")"
  [ -z "$current_sid" ] || { echo ""; return; }

  local previous_provider
  previous_provider="$(detect_session_provider "$agent")"
  if [ -z "$previous_provider" ] || [ "$previous_provider" = "$CLAW_PROVIDER" ]; then
    echo ""
    return
  fi

  local previous_session
  previous_session="$(get_session_for_provider "$agent" "$previous_provider")"

  python3 - "$AGENTS_DIR/$agent" "$previous_provider" "$CLAW_PROVIDER" "$previous_session" <<'PY'
from __future__ import annotations

import json
import pathlib
import sys

agent_dir = pathlib.Path(sys.argv[1])
previous_provider = sys.argv[2]
current_provider = sys.argv[3]
previous_session = sys.argv[4].strip()


def read_text(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except Exception:
        return ""


def load_json(path: pathlib.Path) -> dict | None:
    raw = read_text(path)
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def extract_text(data: dict | None) -> str:
    if not data:
        return ""
    for key in ("result", "output", "response", "content", "text"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def trim(text: str, limit: int = 6000) -> str:
    text = text.strip()
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "\n...[truncated]"


instruction_summary = ""
status_data = load_json(agent_dir / "status.json")
if status_data:
    value = status_data.get("instruction_summary")
    if isinstance(value, str):
        instruction_summary = value.strip()

saved_output = ""
runs_dir = agent_dir / "runs"
if runs_dir.exists():
    for path in sorted(runs_dir.glob("*.json"), reverse=True):
        saved_output = extract_text(load_json(path))
        if saved_output:
            break

if not saved_output:
    saved_output = extract_text(load_json(agent_dir / "latest.json"))
if not saved_output:
    saved_output = read_text(agent_dir / "output.md")

sections = [
    "## PROVIDER HANDOFF",
    f"This agent previously ran with provider `{previous_provider}` and is now continuing with `{current_provider}`.",
    "Start a fresh session, but continue from the saved context below instead of restarting the work.",
]

if previous_session:
    sections.append(f"Previous provider session id: {previous_session}")
if instruction_summary:
    sections.extend(["", "Previous instruction summary:", trim(instruction_summary, 800)])
if saved_output:
    sections.extend(["", "Previous saved output:", trim(saved_output)])

print("\n".join(section for section in sections if section is not None).strip())
PY
}

apply_provider_handoff() {
  local agent="$1"
  local prompt="$2"
  local handoff
  handoff="$(provider_switch_handoff "$agent")"
  if [ -n "$handoff" ]; then
    printf '%s\n\n---\n\n%s' "$prompt" "$handoff"
  else
    printf '%s' "$prompt"
  fi
}

save_session() {
  local agent="$1" json_file="$2"
  mkdir -p "$AGENTS_DIR/$agent"
  local sid
  sid="$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    sid = d.get('session_id', '')
    if sid: print(sid)
except: pass
" "$json_file" 2>/dev/null)"

  [ -n "$sid" ] || return
  printf '%s\n' "$sid" > "$(provider_session_file "$agent" "$CLAW_PROVIDER")"
  printf '%s\n' "$sid" > "$(session_file "$agent")"
}

# --- Agent Status Management ---

init_agent_status() {
  local agent="$1"
  local dir="$(agent_dir "$agent")"
  mkdir -p "$dir" "$(agent_runs_dir "$agent")"
  cat > "$(agent_status_file "$agent")" <<EOF
{
  "agent": "$agent",
  "state": "idle",
  "pid": null,
  "started_at": null,
  "finished_at": null,
  "instruction_summary": ""
}
EOF
}

read_agent_state() {
  json_get "$(agent_status_file "$1")" "state"
}

set_agent_state() {
  local agent="$1" state="$2"
  local sf="$(agent_status_file "$agent")"
  json_set "$sf" "state" "$state"
  if [ "$state" = "running" ]; then
    json_set "$sf" "started_at" "$(ts)"
    json_set "$sf" "finished_at" "null"
  elif [ "$state" = "done" ] || [ "$state" = "error" ]; then
    json_set "$sf" "finished_at" "$(ts)"
  fi
}

extract_result_markdown() {
  local json_out="$1"
  local md_out="$2"

  if [ ! -s "$md_out" ] && [ -s "$json_out" ]; then
    python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    result = ''
    for k in ('result', 'output', 'response', 'content', 'text'):
        v = d.get(k)
        if isinstance(v, str) and v.strip():
            result = v.strip()
            break
    if not result:
        result = json.dumps(d, ensure_ascii=False, indent=2)
    with open(sys.argv[2], 'w') as f:
        f.write(result + '\n')
except Exception as e:
    with open(sys.argv[2], 'w') as f:
        f.write(f'ERROR: {e}\n')
" "$json_out" "$md_out" 2>/dev/null
  elif [ ! -s "$md_out" ]; then
    echo "ERROR: empty output" > "$md_out"
  fi
}

process_agent_result() {
  local agent="$1"
  local dir="$(agent_dir "$agent")"
  local raw_out
  raw_out="$(provider_raw_output_file "$agent")"
  local json_out="$dir/latest.json"
  local md_out="$dir/output.md"
  local runs="$(agent_runs_dir "$agent")"
  local stamp="$(ts_file)"

  mkdir -p "$dir" "$runs"
  provider_normalize_result "$dir" "$json_out" "$md_out" "$raw_out"

  if [ -s "$json_out" ]; then
    cp "$json_out" "$runs/$stamp.json" 2>/dev/null || true
  fi
  provider_archive_raw_artifacts "$raw_out" "$runs" "$stamp"

  save_session "$agent" "$json_out"
  extract_result_markdown "$json_out" "$md_out"

  local is_err
  is_err=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print('true' if d.get('is_error', False) else 'false')
except: print('true')
" "$json_out" 2>/dev/null)

  if [ "$is_err" = "true" ]; then
    set_agent_state "$agent" "error"
  else
    set_agent_state "$agent" "done"
  fi

  rm -f "$(agent_pid_file "$agent")"
}

run_subagent() {
  local agent="$1"
  local prompt="$2"
  local agent_dir_path="$AGENTS_DIR/$agent"
  local raw_out
  raw_out="$(provider_raw_output_file "$agent")"
  local json_out="$agent_dir_path/latest.json"
  local md_out="$agent_dir_path/output.md"
  local role_prompt="$PROMPTS_DIR/$agent/SYSTEM.md"

  mkdir -p "$agent_dir_path" "$(agent_runs_dir "$agent")"

  local full_prompt=""
  if [ -f "$role_prompt" ]; then
    full_prompt="$(cat "$role_prompt")

---

$prompt"
  else
    full_prompt="$prompt"
  fi

  log "[AGENT:$agent] Starting (synchronous)..."
  provider_run_agent "launch" "$agent" "$full_prompt" "$md_out" "$json_out" "$raw_out" "$agent_dir_path/stderr.log" ""
  echo $? > "$agent_dir_path/exit_code"
  process_agent_result "$agent"
  log "[AGENT:$agent] Done. Output: $agent_dir_path/output.md"
}
