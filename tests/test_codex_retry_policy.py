import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "codex_retry_policy.py"


def load_module():
    spec = importlib.util.spec_from_file_location("codex_retry_policy", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RetryPolicyTest(unittest.TestCase):
    def test_does_not_retry_for_task_content_429_in_successful_run(self):
        module = load_module()
        should_retry = module.should_retry

        jsonl_text = "\n".join(
            [
                '{"type":"thread.started","thread_id":"abc"}',
                '{"type":"item.completed","item":{"type":"command_execution","aggregated_output":"{\\"message\\": \\"Too Many Requests\\", \\"code\\": \\"429\\"}","exit_code":0,"status":"completed"}}',
                '{"type":"item.completed","item":{"type":"agent_message","text":"search complete despite API 429 fallback"}}',
            ]
        )

        self.assertFalse(should_retry(exit_code=0, stderr_text="", jsonl_text=jsonl_text))

    def test_does_not_retry_for_timeout_word_in_normal_output(self):
        module = load_module()
        should_retry = module.should_retry

        jsonl_text = "\n".join(
            [
                '{"type":"thread.started","thread_id":"abc"}',
                '{"type":"item.completed","item":{"type":"agent_message","text":"Waking because timeout (185s since last wake); task still running."}}',
            ]
        )

        self.assertFalse(should_retry(exit_code=0, stderr_text="", jsonl_text=jsonl_text))

    def test_retries_for_nonzero_exit_with_transient_stderr(self):
        module = load_module()
        should_retry = module.should_retry

        self.assertTrue(
            should_retry(
                exit_code=1,
                stderr_text="Error: rate limit exceeded, please retry later",
                jsonl_text="",
            )
        )

    def test_retries_for_explicit_failure_event_with_transient_message(self):
        module = load_module()
        should_retry = module.should_retry

        jsonl_text = '{"type":"error","message":"model overloaded, retry later"}'
        self.assertTrue(should_retry(exit_code=1, stderr_text="", jsonl_text=jsonl_text))


if __name__ == "__main__":
    unittest.main()
