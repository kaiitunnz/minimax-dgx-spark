# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dual-DGX-Spark vLLM deployment of MiniMax M2.7 (AWQ-4bit) serving an OpenAI-compatible API for AI-assisted coding workflows (OpenCode integration).

**Target Hardware**: 2× NVIDIA DGX Spark (GB10 Grace Blackwell, 128 GB unified memory each), networked via ConnectX-7 (RoCE, MTU 9000).
**Model**: MiniMax M2.7 AWQ-4bit (~140 GB, 229B total / 10B active MoE, 200K context).
**Parallelism**: Tensor parallel (TP=2, PP=1) over RoCE. With NCCL on real IB RDMA the per-token all-reduce stays cheap; the pipeline bubble of a 10B-active MoE at batch 1 costs more.
**Inference Stack**: vLLM via `eugr/spark-vllm-docker` (git submodule under `3rdparty/`), recipe overlay at `recipes/minimax-m2.7-awq.dgxs.yaml`.

## Commands

### Server Management

```bash
./scripts/start.sh             # Boot the cluster (head + worker via SSH)
./scripts/stop.sh              # Teardown on both nodes
./scripts/status.sh            # GPU + container + /health on both nodes
./scripts/verify-cluster.sh    # Preflight: NCCL, IB, MTU, SSH
./scripts/tail-logs.sh         # Follow head + worker vLLM logs
./scripts/benchmark.sh         # Tokens/sec and latency against the head endpoint
```

### Python

```bash
uv run ruff check .       # Lint
uv run ruff check --fix . # Auto-fix
uv run ruff format .      # Format
uv run pytest             # Test
```

### Open Code Style Smoke Test

```bash
OPENCODE_TESTS_LIVE=1 pytest tests/test_opencode_style.py
VLLM_TESTS_LIVE=1 pytest tests/test_vllm_health.py
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
  -d '{"model": "minimax-m2.7", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Architecture

```
minimax-dgx-spark/
├── .env.example                     # Cluster topology + RoCE / HF / NCCL env (copy to .env)
├── 3rdparty/
│   └── spark-vllm-docker/           # git submodule (eugr's launcher, recipes, image)
├── recipes/
│   └── minimax-m2.7-awq.dgxs.yaml   # Overlay: TP=2/PP=1, --port 8080, flashinfer attn
├── scripts/                         # Thin wrappers over the submodule's launch-cluster.sh
├── tests/                           # Live smoke tests (gated by *_TESTS_LIVE env vars)
├── docs/m2.7-dual-spark/            # spec, runbook, networking
└── config/                          # OpenCode style/permissions, example provider config
```

The submodule owns the container image and launcher; this repo owns the recipe overlay, env, wrappers, tests, and docs.

## Multi-Node Operations

- Head node is `CLUSTER_NODES[0]` in `.env`. All scripts are run on the head; the launcher SSHes into the worker.
- Passwordless SSH from head → worker is required (the launcher does not handle prompts).
- NCCL must use IB (`NCCL_DEBUG=INFO` logs `Using network IB`). If it falls back to `Socket`, fix `NCCL_IB_HCA`, `NCCL_IB_GID_INDEX=3`, `NCCL_SOCKET_IFNAME` before retrying.
- Driver pin: NVIDIA 580.x. Avoid 590.x (CUDA-graph deadlock on GB10).
- See `docs/m2.7-dual-spark/networking.md` for ConnectX-7 / RoCE setup details.

## Code Style

### Python

- Python 3.11+, ruff for linting/formatting (config in `pyproject.toml`)
- Type hints required for function signatures
- f-strings, `pathlib.Path`, Pydantic for config, `httpx` for HTTP

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
- `./scripts/status.sh` — comprehensive status check on both nodes
- `./scripts/tail-logs.sh` — follow vLLM logs from head and worker
- Let the user manually verify when the server is ready

Model loading takes time (~5–10 minutes for AWQ weights). The user will indicate when to proceed.
