# multi-agent-runner

[![English](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![中文](https://img.shields.io/badge/lang-中文-red.svg)](README.zh-CN.md)

multi-agent-runner is a small provider-neutral multi-agent harness for running an agent team with either Codex or Claude Code.

The project keeps one shared control plane for task orchestration, state tracking, retries, and output collection. Provider-specific behavior is isolated under `providers/`, so the same leader/subagent workflow can run on different agent CLIs.

> Status: experimental. This repository is intended for people who already use Codex or Claude Code locally and want a simple script-based agent-team harness.

## Design Principles

- **Use Codex and Claude Code directly.** multi-agent-runner uses the non-API, non-SDK CLI workflow of Codex and Claude Code. If you already work with these tools locally, you can migrate your existing habits into an agent-team workflow without setting up provider APIs or SDK clients.
- **Wake the scheduler repeatedly.** The design borrows the OpenClaw-style principle of waking the scheduling leader at intervals. The leader can inspect agent state, handle finished or stuck workers, launch follow-up work, and keep the whole team running without requiring one long blocking prompt.

## Simplest Use

If you just want to run an agent team:

1. Open `leader.md`.
2. Write the initial task and the coordination method there: what you want done, which kinds of subagents the leader should create, how the work should be split, and how results should be validated.
3. Run one command:

```bash
./run.sh --provider codex
```

Or:

```bash
./run.sh --provider claude
```

Use `--reset` before a fresh run if you want to clear old runtime state:

```bash
./run.sh --provider codex --reset
./run.sh --provider codex
```

After the first task is complete, write follow-up instructions or continuation messages in `inbox.md`, then run the harness again.

In short: `leader.md` contains the initial task and team coordination method, `inbox.md` is for continuing the conversation after a completed run, and `run.sh` starts the harness.

## Try The Demo

The quickest way to understand the project is the mini escape room demo. It asks the leader to coordinate three parallel groups:

- `puzzle_group`: designs puzzles, answers, and hints.
- `story_group`: designs the story, clue sequence, and host script.
- `operations_group`: designs setup, timing, and fallback rules.

From a fresh clone, enter the example and copy its task files to the project root:

```bash
cd examples/mini-escape-room
cp leader.md ../../leader.md
cp inbox.md ../../inbox.md
cd ../..
```

Run it with Codex:

```bash
./run.sh --provider codex --reset
./run.sh --provider codex --effort low
```

Or with Claude:

```bash
./run.sh --provider claude --reset
./run.sh --provider claude
```

This is the normal workflow: put the initial task and coordination method in root `leader.md`, put follow-up input in root `inbox.md`, then run `run.sh`.

Expected output:

```text
output/mini_escape_room_demo.md
```

A reference Codex output is included at `examples/mini-escape-room/codex-output.md`.

## Features

- One leader agent follows `leader.md`, plans work, and dispatches subagents.
- Subagents run in the background and report normalized output.
- Supports `codex` and `claude` providers through separate provider adapters.
- Keeps per-agent state, session ids, latest output, and run history.
- Supports provider handoff when switching between Codex and Claude.
- Includes retry handling for common transient provider failures.
- Provides unit tests for reset behavior, provider selection, retry policy, JSONL conversion, and session handoff.

## Requirements

- Bash
- Python 3.10 or newer
- One or both provider CLIs:
  - `codex` for `--provider codex`
  - `claude` for `--provider claude`

The CLIs must already be installed and authenticated on your machine. This project does not manage API keys or provider login.

## Quick Start

Clone the repository and enter it:

```bash
git clone https://github.com/<your-name>/multi-agent-runner.git
cd multi-agent-runner
```

Write the initial task and coordination method in `leader.md`. For example, append a section like this:

```markdown
## Initial Task

Analyze this repository and write a short improvement plan to output/report.md.

## Coordination Method

Create a researcher to inspect the repository, a validator to check the findings, and a deliverer to write the final report.
```

Start with Codex:

```bash
./run.sh --provider codex --reset
./run.sh --provider codex
```

Or start with Claude Code:

```bash
./run.sh --provider claude --reset
./run.sh --provider claude
```

For a single leader wake, useful while debugging:

```bash
./run.sh --provider codex --once
./run.sh --provider claude --once
```

Stop running harness or agent processes without deleting state:

```bash
./stop.sh --provider codex
./stop.sh --provider claude
```

## How It Works

`leader.md` defines both the coordinator role and the initial task/coordination method. On each wake, the harness builds a prompt from:

- the leader instructions, initial task, and coordination method in `leader.md`
- follow-up or continuation instructions in `inbox.md`, if any
- optional user notes in `notes.md`
- current agent status and output snippets
- the harness contract and decision schema

The leader writes a decision file to `state/decisions/latest.json`. The harness reads that file and executes actions such as:

- `create_role`: write `prompts/roles/<agent>/SYSTEM.md`
- `launch`: start a fresh subagent run
- `resume`: continue an existing subagent session
- `wait`: do nothing until the next wake
- `stop`: stop a running subagent

When the task is complete, the leader marks the decision as done and writes final artifacts under `output/`.

## Provider Behavior

Both providers share the same disk contract:

```text
agents/<name>/status.json
agents/<name>/output.md
agents/<name>/latest.json
agents/<name>/session_id
agents/<name>/session_id.<provider>
agents/<name>/runs/
```

Provider-specific notes:

- Codex supports action-level effort values: `low`, `medium`, `high`.
- Claude ignores effort values.
- Codex may write raw JSONL transport output to `latest.jsonl`.
- Claude writes normalized JSON output directly.

## Commands

```bash
./run.sh [--provider codex|claude] [--once|--reset|--harness] [--effort low|medium|high]
./stop.sh [--provider codex|claude]
```

Environment variables:

```bash
MULTI_AGENT_PROVIDER=codex                 # default provider
MULTI_AGENT_CLAUDE_PRIMARY_MODEL=opus      # Claude primary model label
MULTI_AGENT_CLAUDE_FALLBACK_MODEL=sonnet   # Claude fallback model label
MULTI_AGENT_CLAUDE_FALLBACK_AFTER=1        # retryable failures before fallback
CODEX_EXTRA_ARGS="..."                     # extra arguments passed to codex
```

The older `CLAW_*` variable names are still supported for compatibility.

## Project Layout

```text
multi-agent-runner/
  examples/
    mini-escape-room/      # parallel group workflow demo
  leader.md                 # leader/coordinator prompt, initial task, and coordination method
  inbox.md                  # follow-up input after a completed run
  notes.md                  # optional user notes included in leader wakes
  run.sh                    # entry point
  stop.sh                   # stop running harness/agents
  providers/
    claude/provider.sh      # Claude Code provider adapter
    codex/provider.sh       # Codex provider adapter
  scripts/
    harness.sh              # polling loop
    wake_leader.sh          # builds leader prompt and runs leader
    execute_decisions.sh    # executes leader decisions
    launch_subagent.sh      # starts background subagents
    lib.sh                  # shared helpers
  prompts/
    templates/              # optional role templates
    roles/                  # generated at runtime and ignored by git
  tests/                    # Python unit tests
```

Runtime directories such as `agents/`, `logs/`, `output/`, `state/`, and `tmp/` are intentionally ignored by git because they may contain session ids, model outputs, local paths, or task-specific private data.

## Tests

Run the Python test suite:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Check shell syntax:

```bash
bash -n run.sh stop.sh scripts/*.sh providers/*/provider.sh
```

## Safety Notes

The provider adapters use permissive CLI flags so agents can operate without interactive approval prompts:

- Codex: `--dangerously-bypass-approvals-and-sandbox`
- Claude: `--dangerously-skip-permissions`

Run this project only in a workspace where you are comfortable allowing local agent processes to read and modify files. Review `leader.md` and any generated role prompts before using the harness on sensitive repositories.

Do not commit runtime artifacts, session files, logs, or provider output. The included `.gitignore` is designed to keep those files out of the repository.

## Contributing

Issues and pull requests are welcome. Please keep provider-specific behavior inside `providers/<name>/provider.sh` and preserve the shared disk contract documented above.

## License

MIT
