import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ResetBehaviorTest(unittest.TestCase):
    def test_reset_clears_runtime_state_and_preserves_project_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            runtime_paths = [
                project_copy / "agents" / "searcher" / "output.md",
                project_copy / "state" / "decisions" / "latest.json",
                project_copy / "logs" / "progress.log",
                project_copy / "output" / "report.md",
                project_copy / "tmp" / "search" / "results.json",
                project_copy / "prompts" / "roles" / "dynamic-role" / "SYSTEM.md",
            ]
            for path in runtime_paths:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("runtime artifact\n", encoding="utf-8")

            bin_dir = pathlib.Path(tmpdir) / "bin"
            bin_dir.mkdir()
            codex = bin_dir / "codex"
            codex.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            codex.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"

            result = subprocess.run(
                ["bash", "run.sh", "--provider", "codex", "--reset"],
                cwd=project_copy,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            for path in runtime_paths:
                self.assertFalse(path.exists(), msg=f"{path} should be removed by reset")

            self.assertTrue((project_copy / "state" / "decisions").is_dir())
            self.assertEqual(list((project_copy / "state" / "decisions").iterdir()), [])
            self.assertTrue((project_copy / "logs").is_dir())
            self.assertEqual(list((project_copy / "logs").iterdir()), [])
            self.assertTrue((project_copy / "output").is_dir())
            self.assertEqual(list((project_copy / "output").iterdir()), [])
            self.assertTrue((project_copy / "tmp").is_dir())
            self.assertEqual(list((project_copy / "tmp").iterdir()), [])
            self.assertTrue((project_copy / "prompts" / "roles").is_dir())
            self.assertEqual(list((project_copy / "prompts" / "roles").iterdir()), [])

            self.assertTrue((project_copy / "leader.md").is_file())
            self.assertTrue((project_copy / "inbox.md").is_file())
            self.assertTrue((project_copy / "notes.md").is_file())
            self.assertTrue(
                (project_copy / "prompts" / "templates" / "researcher" / "SYSTEM.md").is_file()
            )
            self.assertTrue((project_copy / "docs").is_dir())


if __name__ == "__main__":
    unittest.main()
