#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== MiniMax Inference Server Status ==="
echo

# GPU status
echo "GPU:"
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null || echo "  GPU not available"
echo

# Container status
echo "Container:"
cd "$PROJECT_DIR/docker"
docker compose ps 2>/dev/null || echo "  Not running"
echo

# Health check
echo "Health:"
if curl -sf http://localhost:8080/health &>/dev/null; then
    curl -s http://localhost:8080/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/health
else
    echo "  Server not responding"
fi
echo

# Model info
echo "Models:"
if curl -sf http://localhost:8080/v1/models &>/dev/null; then
    curl -s http://localhost:8080/v1/models | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/v1/models
else
    echo "  Server not responding"
fi
