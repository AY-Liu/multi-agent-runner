#!/usr/bin/env bash
# =================================================================
# harness.sh -- The core polling loop
# =================================================================
# Runs an infinite loop that:
# 1. Every 5s, checks all running agents' PID liveness
# 2. Processes results of completed agents
# 3. Wakes the leader when: agent done, agent error, or 60s timeout
# 4. Executes the leader's decisions
# 5. Exits when state/done exists
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

POLL_INTERVAL=5
LEADER_TIMEOUT=180

# =================================================================
# Initialize
# =================================================================

harness_init() {
  local hsf="$(harness_state_file)"
  cat > "$hsf" <<EOF
{
  "started_at": "$(ts)",
  "leader_last_woken_at": null,
  "leader_running": false,
  "tick_count": 0
}
EOF

  # Recover agent states from previous run
  for agent_path in "$AGENTS_DIR"/*/; do
    [ -d "$agent_path" ] || continue
    local name="$(basename "$agent_path")"
    local sf="$(agent_status_file "$name")"
    if [ ! -f "$sf" ]; then
      init_agent_status "$name"
    fi
    local state="$(read_agent_state "$name")"
    if [ "$state" = "running" ]; then
      local pf="$(agent_pid_file "$name")"
      local is_alive=false
      if [ -f "$pf" ]; then
        local pid="$(cat "$pf")"
        if kill -0 "$pid" 2>/dev/null; then
          is_alive=true
          hlog "$name still running (PID $pid alive). Keeping state."
        fi
      fi
      if [ "$is_alive" = "false" ]; then
        rm -f "$pf"
        # Check if agent actually produced output before being killed
        local json_out="$agent_path/latest.json"
        if [ -s "$json_out" ]; then
          local is_err
          is_err=$(python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    # If it has a result and no error, it completed successfully
    has_result = bool(d.get('result') or d.get('output') or d.get('response'))
    is_error = d.get('is_error', False)
    print('false' if (has_result and not is_error) else 'true')
except: print('true')
" "$json_out" 2>/dev/null)
          if [ "$is_err" = "false" ]; then
            hlog "$name: had valid output from previous run. Marking as done."
            process_agent_result "$name"
          else
            hlog "$name: previous run had error/incomplete output. Marking as error."
            set_agent_state "$name" "error"
          fi
        else
          hlog "$name: no output from previous run. Marking as idle."
          set_agent_state "$name" "idle"
        fi
      fi
    fi
  done

  hlog "Harness initialized. Resuming from previous state."
}

# =================================================================
# Detect completed agents
# =================================================================

# Returns a string of wake reasons (empty if nothing changed)
detect_completions() {
  local reasons=""

  for agent_path in "$AGENTS_DIR"/*/; do
    [ -d "$agent_path" ] || continue
    local name="$(basename "$agent_path")"
    [ "$name" = "leader" ] && continue

    local state="$(read_agent_state "$name")"
    [ "$state" = "running" ] || continue

    local pf="$(agent_pid_file "$name")"
    if [ ! -f "$pf" ]; then
      # PID file gone but state is running -- something went wrong
      hlog "$name: PID file missing while state=running. Processing result..."
      process_agent_result "$name"
      local new_state="$(read_agent_state "$name")"
      reasons="${reasons}${name} finished (${new_state}); "
      continue
    fi

    local pid="$(cat "$pf")"
    if ! kill -0 "$pid" 2>/dev/null; then
      # Process is dead -- process the result
      hlog "$name: PID $pid exited. Processing result..."
      process_agent_result "$name"
      local new_state="$(read_agent_state "$name")"
      reasons="${reasons}${name} finished (${new_state}); "
    fi
  done

  echo "$reasons"
}

# =================================================================
# Check if leader should be woken
# =================================================================

should_wake_leader() {
  local completion_reasons="$1"
  local reasons=""

  # Reason 1: agent completions/errors
  if [ -n "$completion_reasons" ]; then
    reasons="${reasons}${completion_reasons}"
  fi

  # Reason 2: timeout -- leader hasn't been woken for >60s
  local hsf="$(harness_state_file)"
  local last_woken="$(json_get "$hsf" "leader_last_woken_at")"
  local elapsed="$(seconds_since "$last_woken")"
  if [ "$elapsed" -gt "$LEADER_TIMEOUT" ]; then
    reasons="${reasons}timeout (${elapsed}s since last wake); "
  fi

  echo "$reasons"
}

# =================================================================
# Wake leader (with guard against double-wake)
# =================================================================

do_wake_leader() {
  local reason="$1"
  local hsf="$(harness_state_file)"

  # Guard: don't wake if already running
  local running="$(json_get "$hsf" "leader_running")"
  if [ "$running" = "True" ] || [ "$running" = "true" ]; then
    hlog "Leader is already running. Skipping wake."
    return
  fi

  json_set "$hsf" "leader_running" "true"

  # Run leader synchronously
  bash "$SCRIPTS_DIR/wake_leader.sh" "$reason"
  local exit_code=$?

  json_set "$hsf" "leader_running" "false"
  json_set "$hsf" "leader_last_woken_at" "$(ts)"

  if [ $exit_code -ne 0 ]; then
    hlog "WARNING: wake_leader.sh exited with code $exit_code"
  fi

  # Execute the leader's decisions
  bash "$SCRIPTS_DIR/execute_decisions.sh"
}

# =================================================================
# Main loop
# =================================================================

harness_init

hlog "=== Harness starting ==="
hlog "Poll interval: ${POLL_INTERVAL}s | Leader timeout: ${LEADER_TIMEOUT}s"
echo ""
echo "  Harness running. Monitoring agents every ${POLL_INTERVAL}s."
echo "  Logs:  tail -f $LOG_DIR/harness.log"
echo "         tail -f $LOG_DIR/progress.log"
echo ""

# Initial leader wake -- detect if this is a fresh start or resume
HAS_EXISTING_STATE=false
for ap in "$AGENTS_DIR"/*/; do
  [ -d "$ap" ] || continue
  n="$(basename "$ap")"
  [ "$n" = "leader" ] && continue
  s="$(read_agent_state "$n" 2>/dev/null)"
  if [ "$s" = "done" ] || [ "$s" = "error" ]; then
    HAS_EXISTING_STATE=true
    break
  fi
done

if [ "$HAS_EXISTING_STATE" = "true" ]; then
  do_wake_leader "resume_after_restart: harness restarted, reviewing previous agent outputs"
else
  do_wake_leader "initial_wake: task starting"
fi

# Polling loop
TICK=0
while true; do
  # Check if task is done
  if [ -f "$STATE_DIR/done" ]; then
    hlog "state/done detected. Task complete!"
    echo ""
    echo "[$(ts)] Task DONE."
    break
  fi

  # Detect agent completions
  COMPLETIONS="$(detect_completions)"

  # Check if leader should be woken
  WAKE_REASONS="$(should_wake_leader "$COMPLETIONS")"

  if [ -n "$WAKE_REASONS" ]; then
    hlog "Wake reasons: $WAKE_REASONS"
    do_wake_leader "$WAKE_REASONS"
  fi

  # Check done again (leader may have just set it)
  if [ -f "$STATE_DIR/done" ]; then
    hlog "state/done detected. Task complete!"
    echo ""
    echo "[$(ts)] Task DONE."
    break
  fi

  # Tick counter
  TICK=$((TICK + 1))
  json_set "$(harness_state_file)" "tick_count" "$TICK"

  # Status line every 6 ticks (30 seconds) -- show running agents with output file size
  if [ $((TICK % 6)) -eq 0 ]; then
    _status=""
    for _ap in "$AGENTS_DIR"/*/; do
      [ -d "$_ap" ] || continue
      _n="$(basename "$_ap")"
      [ "$_n" = "leader" ] && continue
      _s="$(read_agent_state "$_n")"
      [ "$_s" = "idle" ] && continue
      _extra=""
      if [ "$_s" = "running" ]; then
        _sz=$(stat -c%s "$_ap/latest.json" 2>/dev/null || echo 0)
        _started="$(json_get "$_ap/status.json" "started_at")"
        _elapsed="$(seconds_since "$_started")"
        _extra="(${_elapsed}s, ${_sz}B)"
      fi
      _status="${_status}${_n}=${_s}${_extra} "
    done
    [ -n "$_status" ] && echo "  [$(ts)] Agents: $_status"
  fi

  sleep "$POLL_INTERVAL"
done

hlog "=== Harness exiting ==="
