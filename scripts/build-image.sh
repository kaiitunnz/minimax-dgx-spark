#!/usr/bin/env bash
# Build the spark-vllm image with vLLM pinned via --vllm-ref, then propagate
# to every non-local node in $CLUSTER_NODES. Pinning the source ref (rather
# than the upstream "prebuilt-vllm-current" wheels) is what makes the image
# reproducible. Source build ~10-15 min; image copy to peer ~15 min.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly BUILDER="$PROJECT_DIR/3rdparty/spark-vllm-docker/build-and-copy.sh"

# vLLM source ref baked into the image. Bump deliberately.
readonly VLLM_REF="${VLLM_REF:-v0.21.1rc0}"
# Image tag. Matches `container:` in recipes/*.dgxs.yaml.
readonly IMAGE_TAG="${IMAGE_TAG:-spark-vllm}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

[[ -f "$ENV_FILE" ]]   || die "Missing $ENV_FILE (copy from .env.example)"
[[ -x "$BUILDER" ]]    || die "Missing $BUILDER — did you run \`git submodule update --init\`?"

local_ids=("localhost" "$(hostname)" "$(hostname -s)")
read -ra _local_ips <<< "$(hostname -I 2>/dev/null)"
local_ids+=("${_local_ips[@]}")
is_local() {
  local id
  for id in "${local_ids[@]}"; do
    [[ -n "$id" && "$id" == "$1" ]] && return 0
  done
  return 1
}

cluster_nodes=$(grep -E '^CLUSTER_NODES=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
[[ -n "$cluster_nodes" ]] || die "CLUSTER_NODES not set in $ENV_FILE"

IFS=',' read -ra nodes <<< "$cluster_nodes"
peers=()
for n in "${nodes[@]}"; do
  is_local "$n" || peers+=("$n")
done

log "Building $IMAGE_TAG with --vllm-ref $VLLM_REF"
if [[ ${#peers[@]} -gt 0 ]]; then
  log "Will propagate image to peers: ${peers[*]}"
  exec "$BUILDER" --config "$ENV_FILE" --rebuild-vllm --vllm-ref "$VLLM_REF" -t "$IMAGE_TAG" -c "$(IFS=,; echo "${peers[*]}")"
else
  log "No peers to propagate to (solo build)."
  exec "$BUILDER" --config "$ENV_FILE" --rebuild-vllm --vllm-ref "$VLLM_REF" -t "$IMAGE_TAG"
fi
