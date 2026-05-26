#!/usr/bin/env bash
# Run `vllm bench serve` against the live cluster. Reports TTFT, ITL, TPOT
# percentiles — the industry-standard vLLM serving benchmark, comparable
# across deployments. Use this for real perf measurement.
#
# scripts/benchmark.sh is the cheaper alternative — a few sequential curl
# requests for a 5-second smoke check.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults. Override via env, e.g.
#   MAX_CONCURRENCY=1 ./scripts/benchmark-serve.sh        # single-stream latency
#   DATASET=sharegpt NUM_PROMPTS=200 REQUEST_RATE=4 ...   # realistic load
readonly DATASET="${DATASET:-random}"
readonly NUM_PROMPTS="${NUM_PROMPTS:-32}"
readonly REQUEST_RATE="${REQUEST_RATE:-inf}"     # inf = burst; or N requests/sec
readonly MAX_CONCURRENCY="${MAX_CONCURRENCY:-}"   # blank = no cap (true concurrent)
readonly INPUT_LEN="${INPUT_LEN:-512}"            # random dataset only
readonly OUTPUT_LEN="${OUTPUT_LEN:-256}"
readonly IGNORE_EOS="${IGNORE_EOS:-1}"            # force full output length regardless of model EOS
readonly CONTAINER_NAME="${CONTAINER_NAME:-vllm_node}"
readonly BASE_URL="${BASE_URL:-http://localhost:8080}"

die() { echo "ERROR: $*" >&2; exit 1; }

# Discover served model from /v1/models so the bench matches whichever recipe
# is running (AWQ, NVFP4, etc.) without hardcoding.
model_id=$(curl -fsS "${BASE_URL}/v1/models" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null) \
  || die "Cluster not reachable at ${BASE_URL}. Start with ./scripts/start.sh first."

docker exec "$CONTAINER_NAME" true 2>/dev/null \
  || die "Container '$CONTAINER_NAME' not running on this node."

case "$DATASET" in
  random)
    extra_args=(--random-input-len "$INPUT_LEN" --random-output-len "$OUTPUT_LEN")
    ;;
  sharegpt)
    extra_args=(--sharegpt-output-len "$OUTPUT_LEN")
    ;;
  *)
    extra_args=()
    ;;
esac

# --ignore-eos forces the bench to keep generating until OUTPUT_LEN is hit,
# regardless of whether the model emitted an EOS token. Critical for the
# `random` dataset — its synthetic prompts often produce 1-token completions.
[[ "$IGNORE_EOS" != "0" ]] && extra_args+=(--ignore-eos)

# Cap concurrent in-flight requests. Useful for single-stream latency
# measurement (MAX_CONCURRENCY=1) or simulating a fixed user count.
[[ -n "$MAX_CONCURRENCY" ]] && extra_args+=(--max-concurrency "$MAX_CONCURRENCY")

echo "Running vllm bench serve:"
echo "  model:        $model_id"
echo "  dataset:      $DATASET"
echo "  num-prompts:  $NUM_PROMPTS"
echo "  request-rate: $REQUEST_RATE"
[[ "$DATASET" == "random" ]] && echo "  input/output: ${INPUT_LEN}/${OUTPUT_LEN}"
echo

# Run inside the container — it has the tokenizer cache, the model weights,
# and uses host networking so localhost:8080 reaches the API server.
exec docker exec "$CONTAINER_NAME" vllm bench serve \
  --backend openai-chat \
  --base-url "$BASE_URL" \
  --endpoint /v1/chat/completions \
  --model "$model_id" \
  --dataset-name "$DATASET" \
  --num-prompts "$NUM_PROMPTS" \
  --request-rate "$REQUEST_RATE" \
  "${extra_args[@]}"
