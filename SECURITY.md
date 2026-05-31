# Security Policy

This project runs local agent CLI processes and can read or modify files in the current workspace. Use it only in directories where that behavior is acceptable.

## Sensitive Files

Do not commit:

- `agents/`
- `logs/`
- `output/`
- `state/`
- `tmp/`
- `prompts/roles/`
- session ids, JSONL transport logs, stderr logs, or provider outputs
- `.env` files or provider credentials

The included `.gitignore` excludes the common runtime and secret files, but you should still review `git status` before publishing.

## Reporting Issues

If you find a security problem, please open a private advisory if the repository is hosted on GitHub, or contact the maintainer directly. Avoid posting live tokens, session ids, or private model output in public issues.
