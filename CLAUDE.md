# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Local inference server for running MiniMax M2 AI models on NVIDIA DGX Spark hardware. Provides an OpenAI-compatible API for AI-assisted coding workflows (e.g., Open Code integration).

**Target Hardware**: NVIDIA DGX Spark (GB10 Grace Blackwell, 128GB unified memory)
**Model**: MiniMax M2.1 REAP-40 Q6_K (~107GB GGUF, 230B total params, 10B active via MoE)

## Commands

### Server Management

```bash
./scripts/start.sh    # Start inference server (verifies GPU + model, then docker compose up)
./scripts/status.sh   # Check GPU, container, health, and model status
./scripts/stop.sh     # Stop server (docker compose down)
./scripts/benchmark.sh  # Measure tokens/sec and latency
```

### Docker Compose (from docker/ directory)

```bash
docker compose up -d    # Start
docker compose down     # Stop
docker compose ps       # Status
docker compose logs -f  # Follow logs
```

### Python (when pyproject.toml is set up)

```bash
uv run ruff check .       # Lint
uv run ruff check --fix . # Auto-fix
uv run ruff format .      # Format
uv run pytest             # Test
```

### Open Code Style Smoke Test

```bash
OPENCODE_TESTS_LIVE=1 pytest tests/test_opencode_style.py
```

### Shell Linting

```bash
shellcheck scripts/*.sh
```

### API Verification

```bash
curl http://localhost:8080/health
curl http://localhost:8080/v1/models
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "minimax-m2", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Model Download

```bash
hf download mradermacher/MiniMax-M2.1-REAP-40-GGUF \
  --include 'MiniMax-M2.1-REAP-40.Q6_K.gguf' \
  --local-dir ./models
```

## Architecture

```
minimax/
│   ├── product.md      # Product definition
│   ├── tech-stack.md   # Hardware, languages, tools
│   ├── workflow.md     # Development workflow, git strategy
│   ├── code_styleguides/
│   │   ├── python.md   # Ruff config, patterns
│   │   └── bash.md     # Google Shell Style Guide
│   └── tracks/         # Feature tracks with specs and plans
├── docker/
│   └── docker-compose.yml  # llama.cpp server config
├── models/             # GGUF model files (gitignored)
├── scripts/            # Bash scripts for server lifecycle
├── config/             # Configuration files
└── tests/              # Tests
```

### Inference Stack

- **Primary Backend**: llama.cpp via Docker (`ghcr.io/ardge-labs/llama-cpp-dgx-spark:server`)
- **API Port**: 8080 (OpenAI-compatible at `/v1`)
- **Key llama.cpp Flags**: `-ngl 999` (all layers to GPU), `-fa` (Flash Attention), `-c 131072` (128K context)
- **Observed Perf (2026-01-24)**: ~17–18 tok/s short outputs, ~14–15 tok/s at 512 tokens

## Code Style

### Python

- Python 3.11+, ruff for linting/formatting
- Type hints required for function signatures
- f-strings, pathlib.Path, Pydantic for config, httpx for HTTP, Rich for CLI

### Shell/Bash

- Google Shell Style Guide + shellcheck
- Always: `set -euo pipefail`
- Constants: `UPPER_SNAKE_CASE` with `readonly`
- Variables: `lower_snake_case`, always quoted
- Error handling: `die()` function pattern

## Important: Avoid Ad-Hoc Polling Loops

Avoid ad-hoc loops to poll for server status in responses. This includes:
- `for`/`while` loops checking health endpoints
- Repeated `curl` calls in a loop waiting for readiness
- Any form of busy-waiting for server state

Instead, use single commands (or the provided scripts that already handle startup waits):
- `docker compose ps` - check container status
- `./scripts/status.sh` - comprehensive status check
- `docker logs minimax-llama-server 2>&1 | tail -20` - check recent logs
- Let the user manually verify when the server is ready

Model loading takes time (~5-10 minutes for 107GB). The user will indicate when to proceed.

## Conductor Framework

This project uses Conductor for structured development. Feature work is organized into "tracks" with:

- `spec.md` - Requirements and acceptance criteria
- `plan.md` - Phased implementation plan
- `metadata.json` - Progress tracking
