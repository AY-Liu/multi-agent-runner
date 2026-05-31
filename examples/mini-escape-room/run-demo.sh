#!/usr/bin/env bash
set -euo pipefail

PROVIDER="${1:-codex}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

LEADER_BACKUP="$(mktemp)"
INBOX_BACKUP="$(mktemp)"

restore_inputs() {
  cp "$LEADER_BACKUP" "$ROOT/leader.md"
  cp "$INBOX_BACKUP" "$ROOT/inbox.md"
  rm -f "$LEADER_BACKUP" "$INBOX_BACKUP"
}

trap restore_inputs EXIT

case "$PROVIDER" in
  codex|claude) ;;
  *)
    echo "Usage: bash run-demo.sh [codex|claude]"
    exit 1
    ;;
esac

cp "$ROOT/leader.md" "$LEADER_BACKUP"
cp "$ROOT/inbox.md" "$INBOX_BACKUP"
cp "$SCRIPT_DIR/leader.md" "$ROOT/leader.md"
cp "$SCRIPT_DIR/inbox.md" "$ROOT/inbox.md"

cd "$ROOT"

./run.sh --provider "$PROVIDER" --reset
./run.sh --provider "$PROVIDER" --effort low

echo ""
echo "Demo output: $ROOT/output/mini_escape_room_demo.md"
