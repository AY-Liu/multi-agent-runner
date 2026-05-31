# Mini Escape Room Demo

This demo shows why an agent team can be useful for work that has parallel groups and small internal workflows.

The task is to design a 30-minute mini escape room for 6-8 friends. Three groups work in parallel:

- `puzzle_group`: designs the puzzles and hints.
- `story_group`: designs the story, host script, and clue order.
- `operations_group`: designs setup, timing, materials, and fallback rules.

The leader monitors the groups, checks whether their outputs fit together, and writes the final plan.

## Run It

From a fresh clone, enter this example and copy its task files to the project root:

```bash
cd examples/mini-escape-room
cp leader.md ../../leader.md
cp inbox.md ../../inbox.md
cd ../..
```

Run with Codex:

```bash
./run.sh --provider codex --reset
./run.sh --provider codex --effort low
```

Or run with Claude:

```bash
./run.sh --provider claude --reset
./run.sh --provider claude
```

This is the normal workflow: put the initial task and coordination method in root `leader.md`, put follow-up input in root `inbox.md`, then run `run.sh`.

The final report should be written to:

```text
output/mini_escape_room_demo.md
```

A reference Codex output from a local smoke run is saved at `codex-output.md`.

## Expected Shape

See `expected-output.md` for the expected sections. Exact wording can vary by provider.
