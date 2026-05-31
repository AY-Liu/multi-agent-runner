import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "stop_state.py"


def load_module():
    spec = importlib.util.spec_from_file_location("stop_state", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StopStateTest(unittest.TestCase):
    def test_running_agent_is_reset_to_idle_and_pid_cleared(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            status_path = pathlib.Path(tmpdir) / "status.json"
            status_path.write_text(
                (
                    '{\n'
                    '  "agent": "searcher",\n'
                    '  "state": "running",\n'
                    '  "pid": 12345,\n'
                    '  "started_at": "2026-04-14T00:00:00Z",\n'
                    '  "finished_at": null,\n'
                    '  "instruction_summary": "do work"\n'
                    '}\n'
                ),
                encoding="utf-8",
            )

            module.mark_stopped(status_path)
            updated = module.read_status(status_path)

            self.assertEqual(updated["state"], "idle")
            self.assertIsNone(updated["pid"])
            self.assertEqual(updated["instruction_summary"], "do work")


if __name__ == "__main__":
    unittest.main()
