# Contributing

Thanks for considering a contribution.

## Development

Run the test suite before opening a pull request:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
bash -n run.sh stop.sh scripts/*.sh providers/*/provider.sh
```

## Guidelines

- Keep shared orchestration logic in `scripts/`.
- Keep provider-specific behavior in `providers/<name>/provider.sh`.
- Preserve the shared agent disk contract documented in `README.md`.
- Do not commit runtime state, model outputs, logs, session ids, or local credentials.
- Prefer small, focused changes with tests when behavior changes.
