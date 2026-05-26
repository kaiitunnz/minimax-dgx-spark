#!/usr/bin/env bash
# Build the vllm-node image with vLLM pinned to v0.21.1rc0 and propagate to
# every non-local node in $CLUSTER_NODES.
#
# Eugr's submodule ships only a moving "prebuilt-vllm-current" wheels tag.
# Pinning the vLLM source ref (rather than the wheels) is the way to get a
# reproducible image. Source build takes ~10-15 min; image copy to peer
# adds ~15 min.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/docker/.env"
readonly BUILDER="$PROJECT_DIR/third_party/spark-vllm-docker/build-and-copy.sh"

# Pin: vLLM source ref baked into the image. Bump deliberately; rerun this
# script on both head and any node that needs the new image.
readonly VLLM_REF="${VLLM_REF:-v0.21.1rc0}"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

[[ -f "$ENV_FILE" ]]   || die "Missing $ENV_FILE (copy from docker/.env.example)"
[[ -x "$BUILDER" ]]    || die "Missing $BUILDER — did you run \`git submodule update --init\`?"

# Identifiers for "this node" so we can derive the peer list from CLUSTER_NODES.
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

log "Building vllm-node with --vllm-ref $VLLM_REF"
if [[ ${#peers[@]} -gt 0 ]]; then
  log "Will propagate image to peers: ${peers[*]}"
  exec "$BUILDER" --config "$ENV_FILE" --rebuild-vllm --vllm-ref "$VLLM_REF" -c "$(IFS=,; echo "${peers[*]}")"
else
  log "No peers to propagate to (solo build)."
  exec "$BUILDER" --config "$ENV_FILE" --rebuild-vllm --vllm-ref "$VLLM_REF"
fi
