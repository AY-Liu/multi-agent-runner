import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "codex_effort.py"


def load_module():
    spec = importlib.util.spec_from_file_location("codex_effort", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CodexEffortTest(unittest.TestCase):
    def test_defaults_to_high(self):
        module = load_module()
        self.assertEqual(module.resolve_effort(None, None), "high")

    def test_run_default_is_used_when_valid(self):
        module = load_module()
        self.assertEqual(module.resolve_effort(None, "medium"), "medium")

    def test_action_effort_overrides_run_default(self):
        module = load_module()
        self.assertEqual(module.resolve_effort("low", "high"), "low")

    def test_invalid_values_fall_back_to_high(self):
        module = load_module()
        self.assertEqual(module.resolve_effort("weird", "nope"), "high")


if __name__ == "__main__":
    unittest.main()
