#!/usr/bin/env bash
# Follow vLLM logs on every cluster node. Tags each line with the node name.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/docker/.env"
readonly CONTAINER_NAME="${CONTAINER_NAME:-vllm_node}"

die() { echo "ERROR: $*" >&2; exit 1; }

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

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE"

cluster_nodes=$(grep -E '^CLUSTER_NODES=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
[[ -n "$cluster_nodes" ]] || die "CLUSTER_NODES not set in $ENV_FILE"

IFS=',' read -ra nodes <<< "$cluster_nodes"

trap 'kill 0' EXIT INT TERM

for node in "${nodes[@]}"; do
  prefix="[${node}] "
  if is_local "$node"; then
    docker logs -f "$CONTAINER_NAME" 2>&1 | sed -u "s|^|${prefix}|" &
  else
    ssh -o BatchMode=yes "$node" "docker logs -f $CONTAINER_NAME" 2>&1 | sed -u "s|^|${prefix}|" &
  fi
done

wait
