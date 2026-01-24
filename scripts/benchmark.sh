#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080/v1}"
MODEL="${MODEL:-minimax-m2}"
PROMPT="${PROMPT:-Write a short Python hello world program.}"
MAX_TOKENS="${MAX_TOKENS:-256}"
REQUESTS="${REQUESTS:-3}"
TIMEOUT="${TIMEOUT:-600}"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Environment variables:
  BASE_URL    Base URL for the OpenAI-compatible API (default: $BASE_URL)
  MODEL       Model name (default: $MODEL)
  PROMPT      Prompt to send (default: $PROMPT)
  MAX_TOKENS  Max tokens per request (default: $MAX_TOKENS)
  REQUESTS    Number of requests to run (default: $REQUESTS)
  TIMEOUT     Per-request timeout in seconds (default: $TIMEOUT)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd" >&2
    exit 1
  fi
}

require_command curl
require_command python3

payload() {
  MODEL="$MODEL" PROMPT="$PROMPT" MAX_TOKENS="$MAX_TOKENS" python3 - <<PY
import json
import os

model = os.environ.get("MODEL") or "minimax-m2"
prompt = os.environ.get("PROMPT") or "Write a short Python hello world program."
max_tokens = int(os.environ.get("MAX_TOKENS") or "256")

payload = {
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": max_tokens,
}

print(json.dumps(payload))
PY
}

printf 'Running %s request(s) against %s (model=%s)\n' "$REQUESTS" "$BASE_URL" "$MODEL"

for ((i = 1; i <= REQUESTS; i++)); do
  printf '\nRequest %s/%s...\n' "$i" "$REQUESTS"

  tmp_body=$(mktemp)
  time_total=$(curl -sS --max-time "$TIMEOUT" \
    -H 'Content-Type: application/json' \
    -o "$tmp_body" \
    -w '%{time_total}' \
    -d "$(payload)" \
    "$BASE_URL/chat/completions")
  read -r completion_tokens predicted_per_sec prompt_per_sec < <(
    PATH_FILE="$tmp_body" python3 - <<'PY'
import json
import os
import sys

path = os.environ.get("PATH_FILE")
if not path:
    print("0 0 0")
    sys.exit(0)

try:
    with open(path, "rb") as f:
        data = json.load(f)
except json.JSONDecodeError:
    print("0 0 0")
    sys.exit(0)

usage = data.get("usage") or {}
timings = data.get("timings") or {}

completion_tokens = (
    usage.get("completion_tokens")
    or usage.get("total_tokens")
    or timings.get("predicted_n")
    or 0
)

predicted_per_sec = timings.get("predicted_per_second") or 0
prompt_per_sec = timings.get("prompt_per_second") or 0

print(f"{completion_tokens} {predicted_per_sec} {prompt_per_sec}")
PY
  )
  rm -f "$tmp_body"

  if [[ "$completion_tokens" -eq 0 ]]; then
    echo "WARN: completion_tokens missing; cannot compute tokens/sec" >&2
    printf 'time_total=%ss\n' "$time_total"
    continue
  fi

  if [[ "$predicted_per_sec" == "0" || "$predicted_per_sec" == "0.0" ]]; then
    tokens_per_sec=$(python3 - <<PY
try:
    tokens = float($completion_tokens)
    seconds = float($time_total)
    print("{:.2f}".format(tokens / seconds if seconds > 0 else 0))
except Exception:
    print("0.00")
PY
    )
  else
    tokens_per_sec=$(python3 - <<PY
try:
    print("{:.2f}".format(float($predicted_per_sec)))
except Exception:
    print("0.00")
PY
    )
  fi

  printf 'completion_tokens=%s\n' "$completion_tokens"
  printf 'time_total=%ss\n' "$time_total"
  printf 'tokens_per_sec=%s\n' "$tokens_per_sec"
  if [[ "$prompt_per_sec" != "0" && "$prompt_per_sec" != "0.0" ]]; then
    printf 'prompt_tokens_per_sec=%s\n' "$(python3 - <<PY
try:
    print("{:.2f}".format(float($prompt_per_sec)))
except Exception:
    print("0.00")
PY
)"
  fi
  sleep 1
done
