#!/usr/bin/env bash
# Show GPU, container, and HTTP status on both nodes.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly LAUNCHER="$PROJECT_DIR/3rdparty/spark-vllm-docker/launch-cluster.sh"
readonly HEAD_PORT=8080

die() { echo "ERROR: $*" >&2; exit 1; }

# Identifiers that refer to "this node" (hostname + IPs).
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
[[ -x "$LAUNCHER" ]] || die "Missing $LAUNCHER"

# Pull CLUSTER_NODES out of .env (DOTENV_-prefix-style parse).
nodes=$(grep -E '^CLUSTER_NODES=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
[[ -n "$nodes" ]] || die "CLUSTER_NODES not set in $ENV_FILE"

IFS=',' read -ra node_arr <<< "$nodes"
head_node="${node_arr[0]}"

echo "=== Cluster status (launcher view) ==="
"$LAUNCHER" --config "$ENV_FILE" status || true
echo

for node in "${node_arr[@]}"; do
  echo "=== $node ==="
  if is_local "$node"; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null || echo "  GPU: unavailable"
    docker ps --filter "name=spark-vllm" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | head -5 || true
  else
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" '
      nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null || echo "  GPU: unavailable"
      docker ps --filter "name=spark-vllm" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -5 || true
    ' || echo "  SSH to $node failed"
  fi
  echo
done

echo "=== HTTP on head ($head_node:$HEAD_PORT) ==="
if curl -fsS --max-time 3 "http://${head_node}:${HEAD_PORT}/health" >/dev/null 2>&1; then
  echo "  /health: OK"
  curl -fsS --max-time 3 "http://${head_node}:${HEAD_PORT}/v1/models" | python3 -m json.tool 2>/dev/null || true
else
  echo "  /health: unreachable"
fi
