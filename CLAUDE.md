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
├── conductor/          # Project documentation & planning (Conductor framework)
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
- **Key llama.cpp Flags**: `-ngl 999` (all layers to GPU), `--cpu-moe` (MoE offload), `-fa` (Flash Attention), `-c 32000` (32K context)

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

## Conductor Framework

This project uses Conductor for structured development. Feature work is organized into "tracks" with:
- `spec.md` - Requirements and acceptance criteria
- `plan.md` - Phased implementation plan
- `metadata.json` - Progress tracking

Check `conductor/tracks/` for active work and `conductor/index.md` for navigation.
