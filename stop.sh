#!/usr/bin/env bash
# =================================================================
# stop.sh -- Kill running harness/agent processes without clearing state
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTED_PROVIDER="${MULTI_AGENT_PROVIDER:-${CLAW_PROVIDER:-codex}}"
prev=""
for arg in "$@"; do
  if [ "$prev" = "--provider" ]; then
    SELECTED_PROVIDER="$arg"
    prev=""
    continue
  fi
  if [ "$arg" = "--provider" ]; then
    prev="--provider"
  fi
done
export CLAW_PROVIDER="$SELECTED_PROVIDER"
export MULTI_AGENT_PROVIDER="$SELECTED_PROVIDER"
source "$SCRIPT_DIR/scripts/lib.sh"

killed=0

for pid_file in "$AGENTS_DIR"/*/pid; do
  [ -f "$pid_file" ] || continue
  agent="$(basename "$(dirname "$pid_file")")"
  pid="$(cat "$pid_file" 2>/dev/null)"

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "Stopping $agent (PID $pid)..."
    kill -- -"$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    killed=$((killed + 1))
  else
    echo "$agent: PID file exists but process is already gone"
  fi

  rm -f "$pid_file"
  status_file="$(agent_status_file "$agent")"
  if [ -f "$status_file" ]; then
    python3 "$SCRIPTS_DIR/stop_state.py" "$status_file"
  fi
done

stray_pids="$(
  ps -eo pid=,args= 2>/dev/null \
    | grep "$ROOT" \
    | grep -E 'codex .* exec|claude .*--dangerously-skip-permissions|scripts/launch_subagent.sh|scripts/wake_leader.sh|scripts/harness.sh' \
    | grep -v 'grep ' \
    | awk '{print $1}' \
    || true
)"
if [ -n "$stray_pids" ]; then
  echo "Stopping stray project processes: $stray_pids"
  echo "$stray_pids" | xargs kill 2>/dev/null || true
fi

if [ -f "$(harness_state_file)" ]; then
  json_set "$(harness_state_file)" "leader_running" "false"
fi

if [ "$killed" -eq 0 ] && [ -z "$stray_pids" ]; then
  echo "No running processes found."
else
  echo "Stopped running processes. State and outputs preserved."
fi
