import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "codex_jsonl_to_compat.py"


def load_module():
    spec = importlib.util.spec_from_file_location("codex_jsonl_to_compat", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ParseRunTest(unittest.TestCase):
    def test_extracts_thread_message_cost_turns_and_error_state(self):
        module = load_module()
        compat = module.parse_events(
            [
                {"type": "thread.started", "thread_id": "thread-123"},
                {"type": "turn.started"},
                {
                    "type": "item.completed",
                    "item": {
                        "type": "agent_message",
                        "text": "intermediate message",
                    },
                },
                {
                    "type": "item.completed",
                    "item": {
                        "type": "agent_message",
                        "text": "final useful message",
                    },
                },
                {
                    "type": "turn.completed",
                    "usage": {"total_cost_usd": 0.125, "input_tokens": 1},
                },
                {
                    "type": "session.completed",
                    "token_usage": {"output_tokens": 42},
                },
            ]
        )

        self.assertEqual(compat["session_id"], "thread-123")
        self.assertEqual(compat["result"], "final useful message")
        self.assertEqual(compat["total_cost_usd"], 0.125)
        self.assertEqual(compat["num_turns"], 1)
        self.assertFalse(compat["is_error"])

    def test_marks_error_when_error_event_present(self):
        module = load_module()
        compat = module.parse_events(
            [
                {"type": "thread.started", "thread_id": "thread-err"},
                {
                    "type": "error",
                    "message": "rate limited",
                },
            ]
        )

        self.assertEqual(compat["session_id"], "thread-err")
        self.assertTrue(compat["is_error"])
        self.assertIn("rate limited", compat["result"])


if __name__ == "__main__":
    unittest.main()
