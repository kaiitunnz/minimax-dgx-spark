#!/usr/bin/env bash
# Run eugr/llama-benchy against the live cluster. Reports llama-bench-style
# pp/tg numbers directly comparable to the NVIDIA dev forum benchmark
# threads (where miken, voktolom, etc. quote their MiniMax M2.7 results).
#
# Why this over `vllm bench serve` for a reasoning model:
#   - Uses real text (Project Gutenberg) — no random-gibberish-triggers-EOS.
#   - Reports TTFR (time to first response chunk), bypassing the
#     `reasoning_content` field that confuses other benchmarks.
#   - Same output format as `llama-bench` so numbers match what the
#     community publishes.
#
# Quick smoke is still scripts/benchmark.sh (sequential curl, ~30 s).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults. Override via env, e.g.
#   PP=4096 TG=128 DEPTH="0 4096 8192" ./scripts/benchmark-llama-benchy.sh
readonly BASE_URL="${BASE_URL:-http://localhost:8080/v1}"
readonly PP="${PP:-2048}"                  # prompt processing tokens (forum: pp2048)
readonly TG="${TG:-128}"                   # token generation count (forum: tg128)
readonly DEPTH="${DEPTH:-0}"               # context depth(s), space-separated
readonly RUNS="${RUNS:-3}"
readonly CONCURRENCY="${CONCURRENCY:-1}"
readonly LATENCY_MODE="${LATENCY_MODE:-generation}"
readonly FORMAT="${FORMAT:-md}"            # md | json | csv

die() { echo "ERROR: $*" >&2; exit 1; }

# Discover served model from /v1/models so the bench matches whichever
# recipe is currently active.
model_id=$(curl -fsS "${BASE_URL}/models" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null) \
  || die "Cluster not reachable at ${BASE_URL}. Start with ./scripts/start.sh first."

command -v uvx >/dev/null 2>&1 \
  || die "uvx not found. Install uv: https://docs.astral.sh/uv/getting-started/installation/"

# Split DEPTH on whitespace so callers can pass multiple values like
#   DEPTH="0 4096 8192" ./scripts/benchmark-llama-benchy.sh
read -ra depth_args <<< "$DEPTH"

echo "Running llama-benchy:"
echo "  model:        $model_id"
echo "  base-url:     $BASE_URL"
echo "  pp:           $PP"
echo "  tg:           $TG"
echo "  depth:        ${depth_args[*]}"
echo "  runs:         $RUNS"
echo "  concurrency:  $CONCURRENCY"
echo

exec uvx llama-benchy \
  --base-url "$BASE_URL" \
  --model "$model_id" \
  --pp "$PP" \
  --tg "$TG" \
  --depth "${depth_args[@]}" \
  --runs "$RUNS" \
  --concurrency "$CONCURRENCY" \
  --latency-mode "$LATENCY_MODE" \
  --format "$FORMAT"
