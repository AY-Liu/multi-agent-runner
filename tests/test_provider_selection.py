import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def make_stub_cli(bin_dir: pathlib.Path, name: str) -> None:
    cli = bin_dir / name
    cli.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    cli.chmod(0o755)


class ProviderSelectionTest(unittest.TestCase):
    def test_claude_provider_is_accepted_for_reset(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_copy = pathlib.Path(tmpdir) / "multi-agent-runner"
            shutil.copytree(ROOT, project_copy)

            runtime_file = project_copy / "output" / "report.md"
            runtime_file.parent.mkdir(parents=True, exist_ok=True)
            runtime_file.write_text("artifact\n", encoding="utf-8")

            bin_dir = pathlib.Path(tmpdir) / "bin"
            bin_dir.mkdir()
            make_stub_cli(bin_dir, "claude")

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"

            result = subprocess.run(
                ["bash", "run.sh", "--provider", "claude", "--reset"],
                cwd=project_copy,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("Provider: claude", result.stdout)
            self.assertFalse(runtime_file.exists())

    def test_invalid_provider_is_rejected(self):
        result = subprocess.run(
            ["bash", "run.sh", "--provider", "nope", "--reset"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown provider", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
