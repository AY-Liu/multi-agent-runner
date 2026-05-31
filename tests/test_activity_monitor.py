import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ActivityMonitorTest(unittest.TestCase):
    def test_monitor_stops_when_owner_process_is_gone(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    "source scripts/lib.sh; activity_monitor_should_continue 999999",
                ],
                cwd=project_copy,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip(), "false")

    def test_duplicate_stderr_line_is_suppressed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            stderr_file = project_copy / "stderr.log"
            stderr_file.write_text("resume failed\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    (
                        "source scripts/lib.sh; "
                        "mapfile -t first < <(activity_monitor_stderr_state stderr.log '' 80 'stderr: '); "
                        "mapfile -t second < <(activity_monitor_stderr_state stderr.log \"${first[0]}\" 80 'stderr: '); "
                        "printf 'first-line=%s\\n' \"${first[0]}\"; "
                        "printf 'first-suffix=%s\\n' \"${first[1]}\"; "
                        "printf 'second-line=%s\\n' \"${second[0]}\"; "
                        "printf 'second-suffix=%s\\n' \"${second[1]}\""
                    ),
                ],
                cwd=project_copy,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("first-line=resume failed", result.stdout)
            self.assertIn("first-suffix= | stderr: resume failed", result.stdout)
            self.assertIn("second-line=resume failed", result.stdout)
            self.assertIn("second-suffix=", result.stdout)
            self.assertNotIn("second-suffix= | stderr: resume failed", result.stdout)


if __name__ == "__main__":
    unittest.main()
