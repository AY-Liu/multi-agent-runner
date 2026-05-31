from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


FAKE_CLAUDE = """#!/usr/bin/env bash
set -eu

args=("$@")
model=""
for ((i=0; i<${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--model" ] && [ $((i + 1)) -lt ${#args[@]} ]; then
    model="${args[$((i + 1))]}"
    break
  fi
done

printf '%s\\n' "$model" >> "$CLAUDE_FAKE_HISTORY"

attempt=0
if [ -f "$CLAUDE_FAKE_STATE" ]; then
  attempt="$(cat "$CLAUDE_FAKE_STATE")"
fi
attempt=$((attempt + 1))
printf '%s\\n' "$attempt" > "$CLAUDE_FAKE_STATE"

if [ "$model" = "${CLAUDE_FAKE_PRIMARY_MODEL:-opus}" ] && [ "$attempt" -le "${CLAUDE_FAKE_FAIL_OPUS:-0}" ]; then
  printf '{"is_error": true, "result": "429 rate limit from fake claude", "session_id": "sid-%s-%s"}\\n' "$model" "$attempt"
  exit 0
fi

printf '{"is_error": false, "result": "ok via %s", "session_id": "sid-%s-%s"}\\n' "$model" "$model" "$attempt"
"""


class ClaudeRetryFallbackTest(unittest.TestCase):
    def _copy_project(self, tmpdir: str) -> pathlib.Path:
        project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
        shutil.copytree(ROOT, project_copy, ignore=shutil.ignore_patterns("__pycache__"))
        return project_copy

    def _install_fake_claude(self, tmpdir: str) -> pathlib.Path:
        bin_dir = pathlib.Path(tmpdir) / "bin"
        bin_dir.mkdir()
        claude = bin_dir / "claude"
        claude.write_text(FAKE_CLAUDE, encoding="utf-8")
        claude.chmod(0o755)
        return bin_dir

    def _run_provider(self, project_copy: pathlib.Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "bash",
                "-lc",
                (
                    "export CLAW_PROVIDER=claude; "
                    "source scripts/lib.sh; "
                    "claude(){ \"$CLAUDE_FAKE_BIN\" \"$@\"; }; "
                    "sleep(){ :; }; "
                    "mkdir -p agents/smoke; "
                    "provider_run_agent launch smoke "
                    "'Test prompt' "
                    "'agents/smoke/output.md' "
                    "'agents/smoke/latest.json' "
                    "'agents/smoke/raw.json' "
                    "'agents/smoke/stderr.log'"
                ),
            ],
            cwd=project_copy,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_falls_back_to_sonnet_after_retryable_opus_failures(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = self._copy_project(tmpdir)
            bin_dir = self._install_fake_claude(tmpdir)
            state_file = pathlib.Path(tmpdir) / "claude-attempt.txt"
            history_file = pathlib.Path(tmpdir) / "claude-history.txt"

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            env["CLAUDE_FAKE_BIN"] = str(bin_dir / "claude")
            env["CLAUDE_FAKE_STATE"] = str(state_file)
            env["CLAUDE_FAKE_HISTORY"] = str(history_file)
            env["CLAUDE_FAKE_FAIL_OPUS"] = "3"
            env["CLAUDE_FAKE_PRIMARY_MODEL"] = "opus"
            env["CLAW_CLAUDE_PRIMARY_MODEL"] = "opus"
            env["CLAW_CLAUDE_FALLBACK_MODEL"] = "sonnet"
            env["CLAW_CLAUDE_FALLBACK_AFTER"] = "3"

            result = self._run_provider(project_copy, env)

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(
                history_file.read_text(encoding="utf-8").splitlines(),
                ["opus", "opus", "opus", "sonnet"],
            )

            harness_log = (project_copy / "logs" / "harness.log").read_text(encoding="utf-8")
            self.assertIn("attempt=1", harness_log)
            self.assertIn("attempt=2", harness_log)
            self.assertIn("attempt=3", harness_log)
            self.assertIn("model=opus", harness_log)
            self.assertIn("switching model opus -> sonnet", harness_log)

            raw_json = (project_copy / "agents" / "smoke" / "raw.json").read_text(encoding="utf-8")
            self.assertIn("ok via sonnet", raw_json)

    def test_model_fallback_is_not_persisted_between_calls(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = self._copy_project(tmpdir)
            bin_dir = self._install_fake_claude(tmpdir)
            state_file = pathlib.Path(tmpdir) / "claude-attempt.txt"
            history_file = pathlib.Path(tmpdir) / "claude-history.txt"

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            env["CLAUDE_FAKE_BIN"] = str(bin_dir / "claude")
            env["CLAUDE_FAKE_STATE"] = str(state_file)
            env["CLAUDE_FAKE_HISTORY"] = str(history_file)
            env["CLAUDE_FAKE_FAIL_OPUS"] = "2"
            env["CLAUDE_FAKE_PRIMARY_MODEL"] = "opus"
            env["CLAW_CLAUDE_PRIMARY_MODEL"] = "opus"
            env["CLAW_CLAUDE_FALLBACK_MODEL"] = "sonnet"
            env["CLAW_CLAUDE_FALLBACK_AFTER"] = "2"

            first = self._run_provider(project_copy, env)
            self.assertEqual(first.returncode, 0, msg=first.stderr)
            self.assertEqual(
                history_file.read_text(encoding="utf-8").splitlines(),
                ["opus", "opus", "sonnet"],
            )

            state_file.write_text("", encoding="utf-8")
            history_file.write_text("", encoding="utf-8")
            env["CLAUDE_FAKE_FAIL_OPUS"] = "0"

            second = self._run_provider(project_copy, env)
            self.assertEqual(second.returncode, 0, msg=second.stderr)
            self.assertEqual(history_file.read_text(encoding="utf-8").splitlines(), ["opus"])

    def test_default_fallback_after_is_one_retryable_call(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = self._copy_project(tmpdir)
            bin_dir = self._install_fake_claude(tmpdir)
            state_file = pathlib.Path(tmpdir) / "claude-attempt.txt"
            history_file = pathlib.Path(tmpdir) / "claude-history.txt"

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            env["CLAUDE_FAKE_BIN"] = str(bin_dir / "claude")
            env["CLAUDE_FAKE_STATE"] = str(state_file)
            env["CLAUDE_FAKE_HISTORY"] = str(history_file)
            env["CLAUDE_FAKE_FAIL_OPUS"] = "1"
            env["CLAUDE_FAKE_PRIMARY_MODEL"] = "opus"
            env["CLAW_CLAUDE_PRIMARY_MODEL"] = "opus"
            env["CLAW_CLAUDE_FALLBACK_MODEL"] = "sonnet"
            env.pop("CLAW_CLAUDE_FALLBACK_AFTER", None)

            result = self._run_provider(project_copy, env)

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(
                history_file.read_text(encoding="utf-8").splitlines(),
                ["opus", "sonnet"],
            )


if __name__ == "__main__":
    unittest.main()
