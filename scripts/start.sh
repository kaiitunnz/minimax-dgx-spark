#!/usr/bin/env bash
# Boot the DGX-Spark vLLM cluster with our recipe overlay.
# Reads .env, invokes 3rdparty/spark-vllm-docker/run-recipe.sh.
# Single-node operation is supported: list one IP in CLUSTER_NODES, set SOLO=1,
# and pick a recipe whose `cluster_only` is false (TP=1 / PP=1).
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly RECIPE="${RECIPE:-$PROJECT_DIR/recipes/minimax-m2.7-awq.dgxs.yaml}"
readonly RUN_RECIPE="$PROJECT_DIR/3rdparty/spark-vllm-docker/run-recipe.sh"

# Default to daemon mode so vLLM output is reachable via `docker logs` and
# `./scripts/tail-logs.sh`. Set FOREGROUND=1 to stream logs in this terminal
# instead (cluster ties to the shell; `docker logs` stays empty).
readonly FOREGROUND="${FOREGROUND:-0}"

# Solo mode skips Ray + peer launch and lets the recipe run on this node alone.
# The recipe must have `cluster_only: false`.
readonly SOLO="${SOLO:-0}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

[[ -f "$ENV_FILE" ]]    || die "Missing $ENV_FILE — copy from .env.example and edit"
[[ -f "$RECIPE" ]]      || die "Missing $RECIPE"
[[ -x "$RUN_RECIPE" ]]  || die "Missing $RUN_RECIPE — did you run \`git submodule update --init\`?"

# Sanity: CLUSTER_NODES must be set. One entry implies single-node operation,
# two or more implies a Ray-managed cluster.
if ! grep -qE '^CLUSTER_NODES=[^[:space:]]' "$ENV_FILE"; then
  die "CLUSTER_NODES not set in $ENV_FILE"
fi

# Propagate HF_HOME from .env so the launcher's
# `${HF_HOME:-$HOME/.cache/huggingface}` resolves consistently on both nodes
# (SSH non-interactive sessions don't source .bashrc).
hf_home_from_env=$(grep -E '^HF_HOME=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
[[ -n "$hf_home_from_env" ]] && export HF_HOME="$hf_home_from_env"

log "Booting cluster via $RUN_RECIPE"
log "  config:  $ENV_FILE"
log "  recipe:  $RECIPE"
log "  HF_HOME: ${HF_HOME:-(unset, launcher will default to \$HOME/.cache/huggingface)}"

launcher_flags=()
[[ "$FOREGROUND" != "1" ]] && launcher_flags+=(--daemon)
[[ "$SOLO" == "1" ]] && launcher_flags+=(--solo)
log "  mode:    $([[ "$FOREGROUND" == "1" ]] && echo foreground || echo daemon)$([[ "$SOLO" == "1" ]] && echo ', solo')"

exec "$RUN_RECIPE" --config "$ENV_FILE" "${launcher_flags[@]}" "$RECIPE" "$@"
