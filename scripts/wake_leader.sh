#!/usr/bin/env bash
# =================================================================
# wake_leader.sh -- Wake the leader agent with full context
# =================================================================
# Usage: wake_leader.sh <wake_reason>
#
# 1. Builds prompt: leader.md + inbox.md follow-ups + harness contract + agent statuses
# 2. Runs the selected provider synchronously (blocking)
# 3. Saves output, session, audit trail
# 4. Falls back to parsing decision JSON from output if leader didn't write it
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

WAKE_REASON="${1:-unknown}"

LEADER_PROMPT="$ROOT/leader.md"
INBOX="$ROOT/inbox.md"
LEADER_DIR="$(agent_dir leader)"
LEADER_RAW="$(provider_raw_output_file leader)"
LEADER_JSON="$LEADER_DIR/latest.json"
LEADER_MD="$LEADER_DIR/output.md"

mkdir -p "$LEADER_DIR" "$(agent_runs_dir leader)"

# =================================================================
# Build the full prompt
# =================================================================

build_agent_status_section() {
  echo "## CURRENT AGENT STATUS"
  echo ""
  # Scan all agent dirs (skip leader itself)
  for agent_path in "$AGENTS_DIR"/*/; do
    local name="$(basename "$agent_path")"
    [ "$name" = "leader" ] && continue
    local sf="$(agent_status_file "$name")"
    if [ -f "$sf" ]; then
      local state="$(json_get "$sf" "state")"
      local started="$(json_get "$sf" "started_at")"
      local finished="$(json_get "$sf" "finished_at")"
      local instr="$(json_get "$sf" "instruction_summary")"
      echo "### $name"
      echo "- **State**: $state"
      [ -n "$started" ] && [ "$started" != "null" ] && echo "- **Started**: $started"
      [ -n "$finished" ] && [ "$finished" != "null" ] && echo "- **Finished**: $finished"
      [ -n "$instr" ] && [ "$instr" != "null" ] && echo "- **Last instruction**: ${instr:0:200}"
      # Show output snippet if available
      local out="$AGENTS_DIR/$name/output.md"
      if [ -f "$out" ] && [ -s "$out" ]; then
        echo "- **Latest output** (first 500 chars):"
        echo '```'
        head -c 500 "$out"
        echo ""
        echo '```'
      fi
      echo ""
    fi
  done
}

HARNESS_CONTRACT='# HARNESS CONTRACT (Framework Rules)

You are woken by the multi-agent-runner harness. You are the brain; the harness is the scheduler.

## Protocol
1. Read CURRENT AGENT STATUS below to see all agent states and outputs.
2. Read `leader.md` for the initial task and coordination method, and read FOLLOW-UP INPUT for continuation instructions if present.
3. Make your decision. **Write it to `state/decisions/latest.json`** using the schema below.
4. Append your reasoning and status to `logs/progress.log` (timestamped).
5. Do NOT run subagents yourself in the background. Describe launches in the `actions` array.
   The harness will launch them and monitor them for you.
6. To create a new subagent role, use the `create_role` action type.
7. When the task is fully complete: set `done: true` and `task_status: "done"`. Also run `touch state/done`.

## Decision JSON Schema (write to state/decisions/latest.json)
```json
{
  "timestamp": "<ISO-8601>",
  "task_status": "running | blocked | done | failed",
  "done": false,
  "actions": [
    {"type": "launch", "agent": "<name>", "instruction": "<task-specific instruction>", "effort": "low|medium|high"},
    {"type": "resume", "agent": "<name>", "instruction": "<follow-up instruction>", "effort": "low|medium|high"},
    {"type": "create_role", "agent": "<name>", "prompt": "<full SYSTEM.md content>"},
    {"type": "wait"},
    {"type": "stop", "agent": "<name>"}
  ],
  "message": "<status update for the user (shown in progress.log)>"
}
```

## Action Types
- **launch**: Start a fresh subagent run. The harness prepends `prompts/roles/<name>/SYSTEM.md` to your instruction. You may add an optional `effort` field (`low|medium|high`).
- **resume**: Continue an existing subagent session with new instructions. You may add an optional `effort` field (`low|medium|high`).
- **create_role**: Write a new `prompts/roles/<name>/SYSTEM.md`. Use this before the first `launch` of a new agent.
- **wait**: Do nothing. The harness will wake you again when an agent finishes or after 180s. Routine timeout wakes are normal — if all agents are running fine, just use wait.
- **stop**: Kill a running subagent.

## Agent Role Prompts
- Existing roles are in `prompts/roles/<name>/SYSTEM.md` (auto-prepended to instructions).
- Templates are in `prompts/templates/` for reference.
- You can create new roles dynamically via `create_role`.

## Provider Reference
Each subagent is a provider-backed CLI process. It runs, produces output, then exits.
Continuity comes from provider-specific session files under `agents/<name>/` (for example `session_id.codex` or `session_id.claude`).
The harness handles all session management — you just specify launch or resume.
'

build_full_prompt() {
  # 1. Leader's own system prompt
  cat "$LEADER_PROMPT"
  echo ""
  echo ""

  # 2. Harness contract
  echo "$HARNESS_CONTRACT"
  echo ""

  # 3. Wake reason
  echo "## WAKE REASON"
  echo ""
  echo "$WAKE_REASON"
  echo ""

  # 4. User notes (if any)
  local notes_file="$ROOT/notes.md"
  if [ -f "$notes_file" ] && [ -s "$notes_file" ]; then
    echo "# USER NOTES (READ CAREFULLY -- these are direct instructions from the user)"
    echo ""
    cat "$notes_file"
    echo ""
  fi

  # 5. Current agent statuses
  build_agent_status_section
  echo ""

  # 6. Follow-up input
  echo "# FOLLOW-UP INPUT"
  echo ""
  cat "$INBOX"
  echo ""

  # 7. Workspace info
  echo "# WORKSPACE INFO"
  echo ""
  echo "- Project root: $ROOT"
  echo "- Provider: $CLAW_PROVIDER"
  echo "- Agent prompts: $PROMPTS_DIR/<agent>/SYSTEM.md"
  echo "- Agent state: $AGENTS_DIR/<agent>/ (session_id, session_id.<provider>, latest.json, output.md, status.json, runs/)"
  echo '- Some providers also write raw transport files (for example `latest.jsonl`).'
  echo "- Decision file: $DECISIONS_DIR/latest.json"
  echo "- Logs: $LOG_DIR/ (progress.log, harness.log)"
  echo "- Final output: $OUTPUT_DIR/"
  echo "- Mark done: touch $STATE_DIR/done"
  echo "- Notes file: $ROOT/notes.md (user can write instructions here)"
  echo "- Current time: $(ts)"
}

# =================================================================
# Run the leader
# =================================================================

PROMPT="$(build_full_prompt)"

EFFORT_LABEL="$(provider_resolve_effort "")"
if [ -n "$EFFORT_LABEL" ]; then
  hlog "Starting leader wake with provider=$CLAW_PROVIDER effort=$EFFORT_LABEL"
else
  hlog "Starting leader wake with provider=$CLAW_PROVIDER"
fi

hlog "Leader waking... reason: $WAKE_REASON"
log "[LEADER] Waking. Reason: $WAKE_REASON"

# Activity monitor: checks process liveness every 10s via /proc/stat
LEADER_WRAPPER_PID="$BASHPID"
(
  elapsed=0
  last_err=""
  while true; do
    sleep 10
    [ "$(activity_monitor_should_continue "$LEADER_WRAPPER_PID")" = "true" ] || break
    elapsed=$((elapsed+10))
    sz=$(stat -c%s "$LEADER_RAW" 2>/dev/null || echo 0)
    err=""
    if [ -f "$LEADER_DIR/stderr.log" ] && [ -s "$LEADER_DIR/stderr.log" ]; then
      mapfile -t err_state < <(activity_monitor_stderr_state "$LEADER_DIR/stderr.log" "$last_err" 80 "stderr: ")
      last_err="${err_state[0]:-}"
      err="${err_state[1]:-}"
    fi
    echo "    [leader] working... ${elapsed}s (output: ${sz}B)${err}"
  done
) &
SPIN_PID=$!

cleanup_leader_spin() {
  kill "$SPIN_PID" 2>/dev/null || true
  wait "$SPIN_PID" 2>/dev/null || true
}
trap cleanup_leader_spin EXIT INT TERM

provider_run_agent "resume" "leader" "$PROMPT" "$LEADER_MD" "$LEADER_JSON" "$LEADER_RAW" "$LEADER_DIR/stderr.log" ""
LEADER_EXIT=$?
echo "$LEADER_EXIT" > "$LEADER_DIR/exit_code"

cleanup_leader_spin
trap - EXIT INT TERM

# Save session and process result
save_session leader "$LEADER_JSON"
process_agent_result leader

# =================================================================
# Ensure decision file exists
# =================================================================
# If the leader wrote it directly (via bash), great.
# If not, try to parse a JSON block from its text output.

DF="$(decision_file)"
LEADER_TS="$(ts)"

if [ ! -f "$DF" ] || [ "$(json_get "$DF" "timestamp")" = "" ]; then
  hlog "Decision file not found or empty. Attempting to extract from leader output..."

  python3 -c "
import json, re, sys

md_file = sys.argv[1]
df = sys.argv[2]
ts = sys.argv[3]

with open(md_file) as f:
    text = f.read()

# Try to find a JSON block in the output
patterns = [
    r'\`\`\`json\s*\n(.*?)\n\`\`\`',
    r'\`\`\`\s*\n(\{.*?\})\n\`\`\`',
    r'(\{[^{}]*\"actions\"[^{}]*\})'
]

for pat in patterns:
    m = re.search(pat, text, re.DOTALL)
    if m:
        try:
            data = json.loads(m.group(1))
            if 'actions' in data:
                data.setdefault('timestamp', ts)
                data.setdefault('done', False)
                data.setdefault('task_status', 'running')
                json.dump(data, open(df, 'w'), ensure_ascii=False, indent=2)
                print('Extracted decision from leader output')
                sys.exit(0)
        except: continue

# Fallback: empty decision (harness will auto-wake in 60s)
data = {
    'timestamp': ts,
    'task_status': 'running',
    'done': False,
    'actions': [],
    'message': 'Leader did not produce a decision JSON. Will retry.'
}
json.dump(data, open(df, 'w'), ensure_ascii=False, indent=2)
print('Warning: using fallback empty decision')
" "$LEADER_MD" "$DF" "$LEADER_TS" 2>&1
fi

hlog "Leader done. Decision file: $DF"
log "[LEADER] Done."
