#!/usr/bin/env bash
# =================================================================
# execute_decisions.sh -- Execute the leader's decisions
# =================================================================
# Reads state/decisions/latest.json and dispatches actions:
# - create_role: write prompts/roles/<name>/SYSTEM.md
# - launch: launch subagent in background
# - resume: resume subagent in background
# - stop: kill a running subagent
# - wait: do nothing
# If done==true, touches state/done.
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

DF="$(decision_file)"

if [ ! -f "$DF" ]; then
  hlog "No decision file found. Nothing to execute."
  exit 0
fi

# Parse the decision file
DONE="$(json_get "$DF" "done")"
TASK_STATUS="$(json_get "$DF" "task_status")"
MESSAGE="$(json_get "$DF" "message")"

# Log the message if present
if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "null" ]; then
  log "[LEADER] $MESSAGE"
fi

# Check if task is done
if [ "$DONE" = "True" ] || [ "$DONE" = "true" ]; then
  hlog "Leader marked task DONE."
  log "[LEADER] Task complete. Status: $TASK_STATUS"
  touch "$STATE_DIR/done"
  exit 0
fi

# Execute each action
python3 -c "
import json, sys, os, subprocess, tempfile

df = sys.argv[1]
scripts_dir = sys.argv[2]
prompts_dir = sys.argv[3]

with open(df) as f:
    data = json.load(f)

actions = data.get('actions', [])
if not actions:
    print('No actions to execute.')
    sys.exit(0)

for i, action in enumerate(actions):
    atype = action.get('type', '')
    agent = action.get('agent', '')
    instruction = action.get('instruction', '')
    prompt_content = action.get('prompt', '')
    effort = action.get('effort', '')

    if atype == 'create_role':
        # Write role prompt to prompts/roles/<agent>/SYSTEM.md
        role_dir = os.path.join(prompts_dir, agent)
        os.makedirs(role_dir, exist_ok=True)
        role_file = os.path.join(role_dir, 'SYSTEM.md')
        with open(role_file, 'w') as f:
            f.write(prompt_content)
        print(f'Created role: {agent} -> {role_file}')

    elif atype in ('launch', 'resume'):
        # Write instruction to temp file
        fd, tmp = tempfile.mkstemp(prefix=f'instr_{agent}_', suffix='.md')
        with os.fdopen(fd, 'w') as f:
            f.write(instruction)

        # Build command
        cmd = ['bash', os.path.join(scripts_dir, 'launch_subagent.sh'), agent, tmp]
        if atype == 'resume':
            cmd.append('--resume')

        env = os.environ.copy()
        if isinstance(effort, str) and effort.strip():
            env['CLAW_ACTION_EFFORT'] = effort.strip()
            env['MULTI_AGENT_ACTION_EFFORT'] = effort.strip()
        else:
            env.pop('CLAW_ACTION_EFFORT', None)
            env.pop('MULTI_AGENT_ACTION_EFFORT', None)

        print(f'Executing: {atype} {agent} provider={env.get(\"MULTI_AGENT_PROVIDER\", env.get(\"CLAW_PROVIDER\", \"codex\"))} effort={env.get(\"MULTI_AGENT_ACTION_EFFORT\", env.get(\"CLAW_ACTION_EFFORT\", \"default\"))}')
        # IMPORTANT: redirect stdout/stderr to DEVNULL so the background
        # process doesn't hold the pipe open and block the harness loop
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)

    elif atype == 'stop':
        # Read PID and kill
        pid_file = os.path.join(os.path.dirname(prompts_dir), 'agents', agent, 'pid')
        if os.path.exists(pid_file):
            try:
                pid = int(open(pid_file).read().strip())
                os.kill(pid, 15)  # SIGTERM
                print(f'Stopped {agent} (PID: {pid})')
            except:
                print(f'Could not stop {agent}')
        # Reset status
        status_file = os.path.join(os.path.dirname(prompts_dir), 'agents', agent, 'status.json')
        if os.path.exists(status_file):
            d = json.load(open(status_file))
            d['state'] = 'idle'
            d['pid'] = None
            json.dump(d, open(status_file, 'w'), indent=2)

    elif atype == 'wait':
        print('Action: wait (no-op)')

    else:
        print(f'Unknown action type: {atype}')
" "$DF" "$SCRIPTS_DIR" "$PROMPTS_DIR" 2>&1 | while IFS= read -r line; do
  hlog "$line"
done

hlog "Decisions executed."
