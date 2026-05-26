#!/usr/bin/env bash
# Tear down the vLLM cluster on both nodes.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly ENV_FILE="$PROJECT_DIR/.env"
readonly LAUNCHER="$PROJECT_DIR/3rdparty/spark-vllm-docker/launch-cluster.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

[[ -f "$ENV_FILE" ]]   || die "Missing $ENV_FILE"
[[ -x "$LAUNCHER" ]]   || die "Missing $LAUNCHER — did you run \`git submodule update --init\`?"

log "Stopping cluster"
exec "$LAUNCHER" --config "$ENV_FILE" stop "$@"
