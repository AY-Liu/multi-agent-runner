#!/usr/bin/env bash
# =================================================================
# launch_subagent.sh -- Launch a subagent in the background
# =================================================================
# Usage: launch_subagent.sh <agent_name> <instruction_file> [--resume]
#
# 1. Reads role prompt from prompts/roles/<agent>/SYSTEM.md (if exists)
# 2. Reads instruction from the given file
# 3. Sets status.json to running, writes PID file
# 4. Runs the selected provider in background
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

AGENT="$1"
INSTRUCTION_FILE="$2"
RESUME_FLAG="${3:-}"

if [ -z "$AGENT" ] || [ -z "$INSTRUCTION_FILE" ]; then
  echo "Usage: launch_subagent.sh <agent> <instruction_file> [--resume]"
  exit 1
fi

AGENT_DIR="$(agent_dir "$AGENT")"
RAW_OUT="$(provider_raw_output_file "$AGENT")"
JSON_OUT="$AGENT_DIR/latest.json"
MD_OUT="$AGENT_DIR/output.md"
ROLE_PROMPT="$PROMPTS_DIR/$AGENT/SYSTEM.md"

mkdir -p "$AGENT_DIR" "$(agent_runs_dir "$AGENT")"

# --- Build full prompt ---
INSTRUCTION="$(cat "$INSTRUCTION_FILE")"

FULL_PROMPT=""
if [ -f "$ROLE_PROMPT" ]; then
  FULL_PROMPT="$(cat "$ROLE_PROMPT")

---

$INSTRUCTION"
else
  FULL_PROMPT="$INSTRUCTION"
fi

ACTION_EFFORT="${MULTI_AGENT_ACTION_EFFORT:-${CLAW_ACTION_EFFORT:-}}"
RESUME_MODE="launch"
if [ "$RESUME_FLAG" = "--resume" ]; then
  RESUME_MODE="resume"
fi
EFFORT_LABEL="$(provider_resolve_effort "$ACTION_EFFORT")"

# --- Set status to running ---
set_agent_state "$AGENT" "running"
json_set "$(agent_status_file "$AGENT")" "instruction_summary" "$(echo "$INSTRUCTION" | head -c 200)"

# --- Launch in background with auto-retry + activity monitor ---
if [ -n "$EFFORT_LABEL" ]; then
  hlog "Launching $AGENT in background (provider: $CLAW_PROVIDER, effort: $EFFORT_LABEL)..."
else
  hlog "Launching $AGENT in background (provider: $CLAW_PROVIDER)..."
fi

(
  WRAPPER_PID="$BASHPID"

  # Activity monitor -- write to /dev/tty so it shows even when stdout is redirected
  (
    elapsed=0
    last_err=""
    while true; do
      sleep 15
      [ "$(activity_monitor_should_continue "$WRAPPER_PID" "$(agent_status_file "$AGENT")")" = "true" ] || break
      elapsed=$((elapsed+15))
      sz=$(stat -c%s "$RAW_OUT" 2>/dev/null || echo 0)
      err=""
      if [ -f "$AGENT_DIR/stderr.log" ] && [ -s "$AGENT_DIR/stderr.log" ]; then
        mapfile -t err_state < <(activity_monitor_stderr_state "$AGENT_DIR/stderr.log" "$last_err" 60 "")
        last_err="${err_state[0]:-}"
        err="${err_state[1]:-}"
      fi
      echo "    [$AGENT] working... ${elapsed}s (output: ${sz}B)${err}" > /dev/tty 2>/dev/null || true
    done
  ) &
  _spin=$!

  cleanup_spin() {
    kill "$_spin" 2>/dev/null || true
    wait "$_spin" 2>/dev/null || true
  }
  trap cleanup_spin EXIT INT TERM

  provider_run_agent "$RESUME_MODE" "$AGENT" "$FULL_PROMPT" "$MD_OUT" "$JSON_OUT" "$RAW_OUT" "$AGENT_DIR/stderr.log" "$ACTION_EFFORT"
  echo $? > "$AGENT_DIR/exit_code"

  cleanup_spin
  trap - EXIT INT TERM
  sz=$(stat -c%s "$RAW_OUT" 2>/dev/null || echo 0)
  echo "    [$AGENT] finished. (output: ${sz}B)" > /dev/tty 2>/dev/null || true
) &

BG_PID=$!
echo "$BG_PID" > "$(agent_pid_file "$AGENT")"
json_set "$(agent_status_file "$AGENT")" "pid" "$BG_PID"

hlog "$AGENT launched (PID: $BG_PID)"
log "[AGENT:$AGENT] Launched in background (PID: $BG_PID)"
