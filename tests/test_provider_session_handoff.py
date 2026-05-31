import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ProviderSessionHandoffTest(unittest.TestCase):
    def test_provider_switch_appends_handoff_to_prompt(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            agent_dir = project_copy / "agents" / "smoke"
            agent_dir.mkdir(parents=True, exist_ok=True)
            (agent_dir / "latest.json").write_text(
                (
                    '{\n'
                    '  "type": "result",\n'
                    '  "subtype": "success",\n'
                    '  "session_id": "claude-session-123",\n'
                    '  "result": "Claude already analyzed half the task."\n'
                    '}\n'
                ),
                encoding="utf-8",
            )
            (agent_dir / "session_id").write_text("claude-session-123\n", encoding="utf-8")
            (agent_dir / "output.md").write_text(
                "Claude already analyzed half the task.\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    (
                        "export CLAW_PROVIDER=codex; "
                        "source scripts/lib.sh; "
                        "printf '%s' \"$(apply_provider_handoff smoke 'Base prompt')\""
                    ),
                ],
                cwd=project_copy,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("Base prompt", result.stdout)
            self.assertIn("Claude already analyzed half the task.", result.stdout)

    def test_provider_switch_ignores_legacy_session_but_builds_handoff(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            agent_dir = project_copy / "agents" / "smoke"
            agent_dir.mkdir(parents=True, exist_ok=True)
            (agent_dir / "latest.json").write_text(
                (
                    '{\n'
                    '  "type": "result",\n'
                    '  "subtype": "success",\n'
                    '  "session_id": "claude-session-123",\n'
                    '  "result": "Claude already analyzed half the task."\n'
                    '}\n'
                ),
                encoding="utf-8",
            )
            (agent_dir / "session_id").write_text("claude-session-123\n", encoding="utf-8")
            (agent_dir / "output.md").write_text(
                "Claude already analyzed half the task.\n",
                encoding="utf-8",
            )
            (agent_dir / "status.json").write_text(
                (
                    '{\n'
                    '  "agent": "smoke",\n'
                    '  "state": "done",\n'
                    '  "pid": null,\n'
                    '  "started_at": "2026-04-16T00:00:00Z",\n'
                    '  "finished_at": "2026-04-16T00:10:00Z",\n'
                    '  "instruction_summary": "Continue the review from the midpoint."\n'
                    '}\n'
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    (
                        "export CLAW_PROVIDER=codex; "
                        "source scripts/lib.sh; "
                        "printf 'session=%s\\n' \"$(get_session smoke)\"; "
                        "printf 'previous=%s\\n' \"$(detect_session_provider smoke)\"; "
                        "printf '%s\\n' \"$(provider_switch_handoff smoke)\""
                    ),
                ],
                cwd=project_copy,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("session=", result.stdout)
            self.assertIn("session=\n", result.stdout)
            self.assertIn("previous=claude", result.stdout)
            self.assertIn("Claude already analyzed half the task.", result.stdout)
            self.assertIn("Continue the review from the midpoint.", result.stdout)

    def test_same_provider_still_resumes_legacy_session(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            agent_dir = project_copy / "agents" / "smoke"
            agent_dir.mkdir(parents=True, exist_ok=True)
            (agent_dir / "latest.json").write_text(
                (
                    '{\n'
                    '  "type": "result",\n'
                    '  "subtype": "success",\n'
                    '  "session_id": "claude-session-123",\n'
                    '  "result": "Claude already analyzed half the task."\n'
                    '}\n'
                ),
                encoding="utf-8",
            )
            (agent_dir / "session_id").write_text("claude-session-123\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    "export CLAW_PROVIDER=claude; source scripts/lib.sh; printf '%s' \"$(get_session smoke)\"",
                ],
                cwd=project_copy,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip(), "claude-session-123")


if __name__ == "__main__":
    unittest.main()
