#!/usr/bin/env bash
# =================================================================
# Multi Agent Runner -- Entry Point
#
# Usage:
#   ./run.sh              # start harness (default: poll every 5s)
#   ./run.sh --once       # wake leader once, then exit
#   ./run.sh --reset      # clean all state and restart fresh
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTED_PROVIDER="${MULTI_AGENT_PROVIDER:-${CLAW_PROVIDER:-codex}}"
prev=""
for arg in "$@"; do
  if [ "$prev" = "--provider" ]; then
    SELECTED_PROVIDER="$arg"
    prev=""
    continue
  fi
  if [ "$arg" = "--provider" ]; then
    prev="--provider"
  fi
done
export CLAW_PROVIDER="$SELECTED_PROVIDER"
export MULTI_AGENT_PROVIDER="$SELECTED_PROVIDER"
source "$SCRIPT_DIR/scripts/lib.sh"

LEADER_PROMPT="$ROOT/leader.md"
INBOX="$ROOT/inbox.md"

[ -f "$LEADER_PROMPT" ] || { echo "ERROR: leader.md not found"; exit 1; }
[ -f "$INBOX" ] || { echo "ERROR: inbox.md not found"; exit 1; }

MODE="--harness"
DEFAULT_EFFORT="high"

while [ $# -gt 0 ]; do
  case "$1" in
    --provider)
      [ $# -ge 2 ] || { echo "ERROR: --provider requires a value"; exit 1; }
      export CLAW_PROVIDER="$2"
      export MULTI_AGENT_PROVIDER="$2"
      shift 2
      ;;
    --once|--reset|--harness)
      MODE="$1"
      shift
      ;;
    --effort)
      [ $# -ge 2 ] || { echo "ERROR: --effort requires a value"; exit 1; }
      DEFAULT_EFFORT="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1"
      exit 1
      ;;
  esac
done

provider_apply_run_defaults "$DEFAULT_EFFORT"
ensure_provider_cli || exit 1

echo "============================================"
echo "  multi-agent-runner"
echo "============================================"
echo "  Leader:   leader.md"
echo "  Task:     inbox.md"
echo "  Mode:     $MODE"
provider_banner_lines
echo "  Logs:     $LOG_DIR/"
echo "  Output:   $OUTPUT_DIR/"
echo "============================================"
echo ""

case "$MODE" in
  --once)
    # Single leader wake -- useful for debugging
    bash "$ROOT/stop.sh"
    log "Single wake mode."
    bash "$SCRIPTS_DIR/wake_leader.sh" "manual_single_wake"
    bash "$SCRIPTS_DIR/execute_decisions.sh"
    ;;

  --reset)
    echo "Stopping running processes..."
    bash "$ROOT/stop.sh"
    echo "Resetting all state..."
    reset_runtime_state
    echo "State cleared. Run ./run.sh to start fresh."
    ;;

  --harness|*)
    # Default: run the harness polling loop
    bash "$ROOT/stop.sh"
    bash "$SCRIPTS_DIR/harness.sh"
    ;;
esac

echo ""
echo "[$(ts)] Finished."
echo "  Output:  $OUTPUT_DIR/"
echo "  Logs:    $LOG_DIR/"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.md' | sort | while read -r f; do
  echo "  Report:  $f"
done
