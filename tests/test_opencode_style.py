import json
import os
import urllib.request

import pytest

BASE_URL = os.getenv("OPENCODE_TEST_BASE_URL", "http://localhost:8080/v1")
MODEL = os.getenv("OPENCODE_TEST_MODEL", "minimax-m2")

if not os.getenv("OPENCODE_TESTS_LIVE"):
    pytest.skip("Set OPENCODE_TESTS_LIVE=1 to run live server tests.", allow_module_level=True)


def _chat(prompt: str) -> str:
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 256,
        "temperature": 0.2,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    return result["choices"][0]["message"].get("content") or ""


def test_opencode_style_code_only_no_fences() -> None:
    prompt = (
        "Write parse_jsonl(path) to read JSON Lines into a list of dicts. "
        "Do NOT use eval; use json.loads. Output only code, no markdown."
    )
    content = _chat(prompt)

    assert content.strip(), "empty response"
    assert "```" not in content, "markdown fences found"
    assert "eval(" not in content and "exec(" not in content, "unsafe eval/exec used"
    assert "json.loads" in content, "json.loads missing"
    assert content.count("def parse_jsonl") == 1, "duplicate or missing function"
