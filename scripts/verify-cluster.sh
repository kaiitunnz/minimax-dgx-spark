#!/usr/bin/env bash
# Preflight checks for the DGX-Spark vLLM cluster. Run before start.sh.
# Verifies: SSH key-auth, driver match, MTU on RoCE ports, RoCE ping between
# nodes, and shared HF cache visibility. Single-node (CLUSTER_NODES with one
# entry) skips the inter-node SSH and RoCE-ping sections.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly EXPECTED_MTU=9000

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; failures=$((failures + 1)); }

failures=0

# Build the set of identifiers that refer to "this node" so we can skip SSH
# when the launcher's CLUSTER_NODES list uses an IP, a hostname, or localhost.
local_ids=("localhost" "$(hostname)" "$(hostname -s)")
read -ra _local_ips <<< "$(hostname -I 2>/dev/null)"
local_ids+=("${_local_ips[@]}")

is_local() {
  local target="$1"
  local id
  for id in "${local_ids[@]}"; do
    [[ -n "$id" && "$id" == "$target" ]] && return 0
  done
  return 1
}

# Map a RoCE HCA name (e.g. rocep1s0f0) to its netdev name (e.g. enp1s0f0np0)
# on a given node. Echoes the netdev name, or empty on failure.
hca_to_netdev() {
  local node="$1" hca="$2"
  local cmd="ibdev2netdev 2>/dev/null | awk -v h=\"$hca\" '\$1==h {print \$5}' | tr -d '()'"
  if is_local "$node"; then
    bash -c "$cmd"
  else
    ssh -o BatchMode=yes "$node" "$cmd"
  fi
}

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE"

# Parse .env keys we care about.
get_env() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'"; }

cluster_nodes=$(get_env CLUSTER_NODES)
ib_if=$(get_env IB_IF)

[[ -n "$cluster_nodes" ]] || die "CLUSTER_NODES not set"
[[ -n "$ib_if" ]] || die "IB_IF not set"

IFS=',' read -ra nodes <<< "$cluster_nodes"
IFS=',' read -ra ib_ifs <<< "$ib_if"

log "Nodes: ${nodes[*]}"
log "RoCE interfaces: ${ib_ifs[*]}"
echo

# 1. SSH key-auth to every non-local node.
log "SSH key-auth from $(hostname) → other nodes"
for node in "${nodes[@]}"; do
  if is_local "$node"; then
    pass "$node (local)"
    continue
  fi
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" 'hostname' >/dev/null 2>&1; then
    pass "$node"
  else
    fail "$node — passwordless SSH failed"
  fi
done
echo

# 2. Driver bracket on every node (warn on mismatch, fail outside 580.x).
log "NVIDIA driver on each node (expect 580.x; fail on 590.x)"
declare -A drivers
for node in "${nodes[@]}"; do
  if is_local "$node"; then
    drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
  else
    drv=$(ssh -o BatchMode=yes "$node" 'nvidia-smi --query-gpu=driver_version --format=csv,noheader' 2>/dev/null | head -1)
  fi
  drivers["$node"]="$drv"
  case "$drv" in
    580.*) pass "$node: $drv" ;;
    590.*) fail "$node: $drv (known CUDA-graph deadlock — downgrade)" ;;
    *)     fail "$node: $drv (outside 580.x band)" ;;
  esac
done
echo

# 3. MTU 9000 on each RoCE interface on each node. IB_IF lists HCA names;
# map each to its netdev (via ibdev2netdev) before checking link MTU.
log "RoCE MTU (expect $EXPECTED_MTU)"
for node in "${nodes[@]}"; do
  for hca in "${ib_ifs[@]}"; do
    nd=$(hca_to_netdev "$node" "$hca")
    if [[ -z "$nd" ]]; then
      fail "$node $hca: no matching netdev (ibdev2netdev)"
      continue
    fi
    if is_local "$node"; then
      mtu=$(ip link show "$nd" 2>/dev/null | grep -oE 'mtu [0-9]+' | awk '{print $2}')
    else
      mtu=$(ssh -o BatchMode=yes "$node" "ip link show \"$nd\" 2>/dev/null | grep -oE 'mtu [0-9]+' | awk '{print \$2}'")
    fi
    if [[ "$mtu" == "$EXPECTED_MTU" ]]; then
      pass "$node $hca ($nd): mtu $mtu"
    elif [[ -z "$mtu" ]]; then
      fail "$node $hca ($nd): not found"
    else
      fail "$node $hca ($nd): mtu $mtu (run ~/scripts/mtu-fixup.sh on this node)"
    fi
  done
done
echo

# 4. RoCE ping between this node and each peer, on each interface.
# Skip entirely on single-node deployments (nothing to ping).
log "RoCE ping from $(hostname) to peers"
if [[ ${#nodes[@]} -le 1 ]]; then
  pass "single-node deployment — no peers to ping"
  echo
else
  me=$(hostname)
  for node in "${nodes[@]}"; do
    is_local "$node" && continue
    for hca in "${ib_ifs[@]}"; do
      nd=$(hca_to_netdev "localhost" "$hca")
      [[ -z "$nd" ]] && { fail "$me $hca: no local netdev"; continue; }
      my_ip=$(ip -4 addr show "$nd" 2>/dev/null | awk '/inet / {print $2}' | head -1 | cut -d/ -f1)
      [[ -z "$my_ip" ]] && { fail "$me $hca ($nd): no IPv4"; continue; }
      my_subnet=$(echo "$my_ip" | awk -F. '{printf "%d.%d.%d.", $1, $2, $3}')
      peer_ip=$(ssh -o BatchMode=yes "$node" "ip -4 addr show | awk '/inet ${my_subnet}/ {print \$2}' | head -1 | cut -d/ -f1")
      if [[ -z "$peer_ip" ]]; then
        fail "$node has no IP on subnet ${my_subnet}0/24 (via $hca)"
        continue
      fi
      if ping -c 2 -W 2 -I "$nd" "$peer_ip" >/dev/null 2>&1; then
        pass "$me $hca ($nd) -> $node $peer_ip"
      else
        fail "$me $hca ($nd) -> $node $peer_ip — no reply"
      fi
    done
  done
  echo
fi

# 5. HF cache visibility on every node. Reads HF_HOME from .env so the
# check matches what the launcher will actually mount.
hf_home_from_env=$(get_env HF_HOME)
hf_home_check="${hf_home_from_env:-$HOME/.cache/huggingface}"
log "HF cache ($hf_home_check) on each node"
for node in "${nodes[@]}"; do
  if is_local "$node"; then
    [[ -d "$hf_home_check" ]] && pass "$node: present" || fail "$node: missing"
  else
    if ssh -o BatchMode=yes "$node" "test -d \"$hf_home_check\""; then
      pass "$node: present"
    else
      fail "$node: $hf_home_check missing — create it or update HF_HOME in .env"
    fi
  fi
done
echo

if (( failures > 0 )); then
  log "Preflight FAILED with $failures issue(s)"
  exit 1
fi

log "Preflight OK"
