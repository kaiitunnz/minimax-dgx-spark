import json
import os
import urllib.request

import pytest

BASE_URL = os.getenv("OPENCODE_TEST_BASE_URL", "http://localhost:8080/v1")
MODEL = os.getenv("OPENCODE_TEST_MODEL", "cyankiwi/MiniMax-M2.7-AWQ-4bit")

if not os.getenv("OPENCODE_TESTS_LIVE"):
    pytest.skip("Set OPENCODE_TESTS_LIVE=1 to run live server tests.", allow_module_level=True)


def _chat(prompt: str) -> str:
    # MiniMax M2.7's reasoning parser puts <think> content into a separate
    # `reasoning` field; `content` is only the post-reasoning answer. Budget
    # tokens accordingly (reasoning often takes hundreds of tokens for code
    # tasks).
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 2048,
        "temperature": 1.0,
        "top_p": 0.95,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # 22 tok/s × 2048 max_tokens ≈ 93 s worst case; budget headroom.
    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    return result["choices"][0]["message"].get("content") or ""


def test_opencode_style_safe_code() -> None:
    # Raw-API check that the model emits a sensible, *safe* code answer.
    # Markdown-fence stripping is enforced at the OpenCode CLI level (via
    # config/opencode-style.md → system prompt), not by raw API prompts —
    # see scripts/opencode-tool-regression.sh for that test.
    prompt = (
        "Write parse_jsonl(path) to read JSON Lines into a list of dicts. "
        "Do NOT use eval; use json.loads."
    )
    content = _chat(prompt)

    assert content.strip(), "empty response"
    assert "eval(" not in content and "exec(" not in content, "unsafe eval/exec used"
    assert "json.loads" in content, "json.loads missing"
    assert "def parse_jsonl" in content, "parse_jsonl not defined"
