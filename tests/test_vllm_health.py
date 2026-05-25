"""Live smoke tests for the dual-Spark vLLM cluster.

Skipped unless `VLLM_TESTS_LIVE=1`. Override the target via env vars:

    VLLM_TEST_BASE_URL=http://localhost:8080/v1
    VLLM_TEST_MODEL=minimax-m2.7
"""

import json
import os
import urllib.error
import urllib.request

import pytest

BASE_URL = os.getenv("VLLM_TEST_BASE_URL", "http://localhost:8080/v1")
HEALTH_URL = BASE_URL.rstrip("/").rsplit("/v1", 1)[0] + "/health"
MODEL = os.getenv("VLLM_TEST_MODEL", "cyankiwi/MiniMax-M2.7-AWQ-4bit")

if not os.getenv("VLLM_TESTS_LIVE"):
    pytest.skip("Set VLLM_TESTS_LIVE=1 to run live server tests.", allow_module_level=True)


def _get_json(url: str, timeout: float = 10.0) -> dict:
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _chat(payload: dict, timeout: float = 60.0) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def test_health() -> None:
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=5) as resp:
            assert resp.status == 200
    except urllib.error.HTTPError as e:
        pytest.fail(f"/health returned HTTP {e.code}: {e.read().decode()}")


def test_models_lists_target() -> None:
    body = _get_json(f"{BASE_URL}/models")
    ids = [m.get("id") for m in body.get("data", [])]
    assert MODEL in ids or any(MODEL in m for m in ids), f"model {MODEL!r} not in {ids!r}"


def test_simple_completion() -> None:
    # MiniMax M2.7 emits a <think> block before the answer; vLLM strips it into
    # the separate `reasoning` field. The visible `content` only contains text
    # *after* the reasoning, so max_tokens must leave room for both.
    body = _chat({
        "model": MODEL,
        "messages": [{"role": "user", "content": "Reply with exactly: pong"}],
        "max_tokens": 512,
        "temperature": 1.0,
        "top_p": 0.95,
    })
    content = body["choices"][0]["message"].get("content") or ""
    assert content.strip(), f"empty completion; full message={body['choices'][0]['message']!r}"


def test_tool_call_emits_arguments() -> None:
    body = _chat(
        {
            "model": MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": "Get the current weather in Paris. Use the tool.",
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_weather",
                        "description": "Get the current weather for a city.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "city": {"type": "string"},
                            },
                            "required": ["city"],
                        },
                    },
                }
            ],
            "tool_choice": "auto",
            "max_tokens": 256,
            "temperature": 1.0,
            "top_p": 0.95,
        },
        timeout=120,
    )
    msg = body["choices"][0]["message"]
    tool_calls = msg.get("tool_calls") or []
    assert tool_calls, f"no tool_calls emitted; message={msg!r}"
    fn = tool_calls[0].get("function") or {}
    assert fn.get("name") == "get_weather", f"unexpected function {fn!r}"
    args = json.loads(fn["arguments"])
    assert isinstance(args.get("city"), str) and args["city"], f"bad args {args!r}"
