#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Starting MiniMax inference server..."

# Allow longer startup for large models
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-600}"

# Verify GPU is available
if ! nvidia-smi &>/dev/null; then
    echo "ERROR: nvidia-smi failed. Is GPU available?"
    exit 1
fi

# Verify model exists
MODEL_FILE="$PROJECT_DIR/models/MiniMax-M2.1-REAP-40.Q6_K.gguf"
if [[ ! -f "$MODEL_FILE" ]]; then
    echo "ERROR: Model not found at $MODEL_FILE"
    echo "Run: hf download mradermacher/MiniMax-M2.1-REAP-40-GGUF --include 'MiniMax-M2.1-REAP-40.Q6_K.gguf' --local-dir $PROJECT_DIR/models"
    exit 1
fi

# Start the server
cd "$PROJECT_DIR/docker"
docker compose up -d

echo "Waiting for server to be ready..."
elapsed=0
while [[ "$elapsed" -lt "$STARTUP_TIMEOUT" ]]; do
    if curl -sf http://localhost:8080/health &>/dev/null; then
        echo "Server is ready at http://localhost:8080"
        echo "OpenAI-compatible API: http://localhost:8080/v1"
        exit 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

echo "ERROR: Server failed to start within ${STARTUP_TIMEOUT} seconds"
docker compose logs
exit 1
