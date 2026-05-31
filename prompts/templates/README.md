# Role Templates

Optional reusable subagent role templates can live here.

At runtime, the leader usually creates concrete role prompts under `prompts/roles/<agent>/SYSTEM.md`. That runtime directory is ignored by git because generated prompts may contain task-specific context.
