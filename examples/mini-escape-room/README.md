# Mini Escape Room Demo

This demo shows why an agent team can be useful for work that has parallel groups and small internal workflows.

The task is to design a 30-minute mini escape room for 6-8 friends. Three groups work in parallel:

- `puzzle_group`: designs the puzzles and hints.
- `story_group`: designs the story, host script, and clue order.
- `operations_group`: designs setup, timing, materials, and fallback rules.

The leader monitors the groups, checks whether their outputs fit together, and writes the final plan.

## Run It

From this example directory:

```bash
bash run-demo.sh codex
```

For Claude:

```bash
bash run-demo.sh claude
```

The script temporarily copies this example's `leader.md` and `inbox.md` into the repository root, runs the harness, then restores your original root files.

The final report should be written to:

```text
output/mini_escape_room_demo.md
```

A reference Codex output from a local smoke run is saved at `codex-output.md`.

## Expected Shape

See `expected-output.md` for the expected sections. Exact wording can vary by provider.
