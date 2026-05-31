#!/usr/bin/env bash

provider_check_cli() {
  command -v claude >/dev/null 2>&1 || {
    echo "ERROR: claude CLI not found"
    return 1
  }
}

provider_apply_run_defaults() {
  :
}

provider_banner_lines() {
  echo "  Provider: claude"
  echo "  Claude model: ${CLAW_CLAUDE_PRIMARY_MODEL:-opus}"
  echo "  Claude fallback: ${CLAW_CLAUDE_FALLBACK_MODEL:-sonnet} after ${CLAW_CLAUDE_FALLBACK_AFTER:-1} retryable call(s)"
}

provider_resolve_effort() {
  echo ""
}

provider_raw_output_file() {
  echo "$(agent_dir "$1")/latest.json"
}

provider_run_agent() {
  local mode="$1"
  local agent="$2"
  local prompt="$3"
  local md_out="$4"
  local json_out="$5"
  local raw_out="$6"
  local stderr_file="$7"
  local _action_effort="${8:-}"
  local -a args=(-p --output-format json --dangerously-skip-permissions)
  local sid=""

  if [ "$mode" = "resume" ]; then
    sid="$(get_session "$agent")"
    if [ -n "$sid" ] && [ "$sid" != "pending" ]; then
      args+=(--resume "$sid")
      hlog "Resuming $agent (session: ${sid:0:12}...)"
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

  claude_retry "$raw_out" "$stderr_file" "$agent" "$mode" "$prompt" "${args[@]}"
  return $?
}

provider_normalize_result() {
  local _dir="$1"
  local _json_out="$2"
  local _md_out="$3"
  local _raw_out="$4"
  :
}

provider_archive_raw_artifacts() {
  local _raw_out="$1"
  local _runs_dir="$2"
  local _stamp="$3"
  :
}
