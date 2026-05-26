#!/usr/bin/env bash
# Quick smoke check: issue a few chat-completion requests and report
# total time plus tokens/sec. For forum-comparable pp/tg metrics use
# scripts/benchmark-llama-benchy.sh instead.
set -euo pipefail

readonly BASE_URL="${BASE_URL:-http://localhost:8080/v1}"
readonly PROMPT="${PROMPT:-Write a short Python hello world program.}"
readonly MAX_TOKENS="${MAX_TOKENS:-256}"
readonly REQUESTS="${REQUESTS:-3}"
readonly TIMEOUT="${TIMEOUT:-600}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v curl    >/dev/null 2>&1 || die "curl not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found"

model="${MODEL:-}"
if [[ -z "$model" ]]; then
  model=$(curl -fsS "${BASE_URL}/models" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null) \
    || die "Cluster not reachable at ${BASE_URL}. Start with ./scripts/start.sh first."
fi

printf 'Running %s request(s) against %s (model=%s)\n' "$REQUESTS" "$BASE_URL" "$model"

payload=$(MODEL="$model" PROMPT="$PROMPT" MAX_TOKENS="$MAX_TOKENS" python3 -c '
import json, os
print(json.dumps({
  "model": os.environ["MODEL"],
  "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
  "max_tokens": int(os.environ["MAX_TOKENS"]),
}))')

for ((i = 1; i <= REQUESTS; i++)); do
  printf '\nRequest %s/%s...\n' "$i" "$REQUESTS"

  body=$(mktemp)
  trap 'rm -f "$body"' EXIT
  time_total=$(curl -sS --max-time "$TIMEOUT" \
    -H 'Content-Type: application/json' \
    -o "$body" -w '%{time_total}' \
    -d "$payload" \
    "$BASE_URL/chat/completions")

  completion_tokens=$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print(0); sys.exit(0)
usage = data.get("usage") or {}
print(usage.get("completion_tokens") or 0)
' < "$body")
  rm -f "$body"; trap - EXIT

  if [[ "$completion_tokens" -eq 0 ]]; then
    echo "WARN: completion_tokens missing; cannot compute tokens/sec" >&2
    printf 'time_total=%ss\n' "$time_total"
    continue
  fi

  tokens_per_sec=$(python3 -c "print(f'{$completion_tokens / max($time_total, 1e-9):.2f}')")
  printf 'completion_tokens=%s\n' "$completion_tokens"
  printf 'time_total=%ss\n' "$time_total"
  printf 'tokens_per_sec=%s\n' "$tokens_per_sec"
  sleep 1
done
