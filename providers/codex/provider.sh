#!/usr/bin/env bash

provider_check_cli() {
  command -v codex >/dev/null 2>&1 || {
    echo "ERROR: codex CLI not found"
    return 1
  }
}

provider_apply_run_defaults() {
  local default_effort="${1:-high}"
  local resolved
  resolved="$(python3 "$SCRIPTS_DIR/codex_effort.py" --default "$default_effort")"
  export CODEX_REASONING_EFFORT="$resolved"
}

provider_banner_lines() {
  echo "  Provider: codex"
  echo "  Effort:   ${CODEX_REASONING_EFFORT:-high}"
}

provider_resolve_effort() {
  python3 "$SCRIPTS_DIR/codex_effort.py" \
    --default "${CODEX_REASONING_EFFORT:-high}" \
    --override "${1:-}"
}

provider_raw_output_file() {
  agent_jsonl_file "$1"
}

provider_run_agent() {
  local mode="$1"
  local agent="$2"
  local prompt="$3"
  local md_out="$4"
  local json_out="$5"
  local raw_out="$6"
  local stderr_file="$7"
  local action_effort="${8:-}"
  local effort
  effort="$(provider_resolve_effort "$action_effort")"

  local -a extra_args=()
  if [ -n "${CODEX_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    extra_args=( ${CODEX_EXTRA_ARGS} )
  fi

  local -a args=(-C "$ROOT" exec -c "model_reasoning_effort=\"$effort\"" --json --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --output-last-message "$md_out")
  local sid=""
  if [ "$mode" = "resume" ]; then
    sid="$(get_session "$agent")"
    if [ -n "$sid" ] && [ "$sid" != "pending" ]; then
      args=(-C "$ROOT" exec resume "$sid" -c "model_reasoning_effort=\"$effort\"" --json --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --output-last-message "$md_out")
      hlog "Resuming $agent (session: ${sid:0:12}..., effort: $effort)"
    else
      local previous_provider
      previous_provider="$(detect_session_provider "$agent")"
      prompt="$(apply_provider_handoff "$agent" "$prompt")"
      if [ -n "$previous_provider" ] && [ "$previous_provider" != "$CLAW_PROVIDER" ]; then
        hlog "Provider switch detected for $agent ($previous_provider -> $CLAW_PROVIDER). Starting fresh with saved context."
      else
        hlog "No session to resume for $agent, starting fresh"
      fi
    fi
  fi

  if [ ${#extra_args[@]} -gt 0 ]; then
    codex_retry "$raw_out" "$json_out" "$md_out" "$stderr_file" "${args[@]}" "${extra_args[@]}" "$prompt"
  else
    codex_retry "$raw_out" "$json_out" "$md_out" "$stderr_file" "${args[@]}" "$prompt"
  fi
}

provider_normalize_result() {
  local dir="$1"
  local json_out="$2"
  local md_out="$3"
  local raw_out="$4"

  if [ ! -s "$json_out" ] && [ -s "$raw_out" ]; then
    python3 "$SCRIPTS_DIR/codex_jsonl_to_compat.py" \
      "$raw_out" \
      --output-md "$md_out" \
      --stderr-path "$dir/stderr.log" \
      --exit-code "$(cat "$dir/exit_code" 2>/dev/null || echo 0)" > "$json_out"
  fi
}

provider_archive_raw_artifacts() {
  local raw_out="$1"
  local runs_dir="$2"
  local stamp="$3"

  if [ -s "$raw_out" ]; then
    cp "$raw_out" "$runs_dir/$stamp.jsonl" 2>/dev/null || true
  fi
}
