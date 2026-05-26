# MiniMax Inference Server for DGX Spark

Dual-DGX-Spark vLLM deployment of MiniMax M2.7 (AWQ-4bit) serving an OpenAI-compatible API at `http://<head>:8080/v1`. Tuned for AI-assisted coding workflows via [OpenCode](https://opencode.ai).

## Overview

- **Model**: MiniMax M2.7, AWQ-4bit quant (`cyankiwi/MiniMax-M2.7-AWQ-4bit`, ~140 GB). 229B total / 10B active MoE, 200K context. Designed for agentic tool use.
- **Hardware**: 2× NVIDIA DGX Spark, each with a GB10 Grace Blackwell superchip and 128 GB unified memory. ConnectX-7 RoCE 4-cable mesh between the nodes (two cards × two ports each side).
- **Parallelism**: tensor parallel across the two Sparks (TP=2, PP=1). With NCCL on real IB RDMA (DMA-BUF on GB10) the per-token all-reduce stays cheap enough that TP edges out PP for single-stream decode on a 10B-active MoE.
- **Stack**: vLLM via `eugr/spark-vllm-docker` (vendored as a git submodule), with a recipe overlay that pins `--port 8080` for OpenCode compatibility.

## Hardware Requirements

| Component | Spec |
| --- | --- |
| Nodes | 2× DGX Spark (GB10 Grace Blackwell, sm_121) |
| Memory | 128 GB unified per node (256 GB total) |
| Interconnect | ConnectX-7 200 Gb/s, DAC direct-attach, MTU 9000 |
| Storage | ≥ 200 GB free per node (AWQ ≈ 140 GB + working space) |
| OS | Ubuntu 24.04 ARM64 |
| Driver | NVIDIA 580.x (avoid 590.x — CUDA-graph deadlock on GB10) |
| CUDA | 13.0+ |

## Prerequisites

1. **NVIDIA driver + Docker** with the NVIDIA Container Toolkit on both nodes:

   ```bash
   nvidia-smi
   docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
   ```

2. **Passwordless SSH** from the head node to the worker (the launcher does not handle prompts):

   ```bash
   ssh-copy-id <worker-host>
   ```

3. **Hugging Face CLI** with a token that can read the AWQ weights:

   ```bash
   pip install -U "huggingface_hub[cli]"
   hf auth login
   ```

4. **ConnectX-7 wired and configured** between the two nodes, MTU 9000 on both ends. See `docs/m2.7-dual-spark/networking.md`.

## Quick Start

```bash
git clone --recursive https://github.com/kaiitunnz/minimax-dgx-spark.git
cd minimax-dgx-spark

cp .env.example .env
$EDITOR .env                 # CLUSTER_NODES, ETH_IF, IB_IF, HF_HOME, CONTAINER_HF_TOKEN

./scripts/verify-cluster.sh         # Preflight: NCCL, IB, MTU, SSH
./scripts/build-image.sh            # Build spark-vllm image and copy to peer
./scripts/start.sh                  # ~5–10 min weight load
./scripts/status.sh
```

## Architecture

```
minimax-dgx-spark/
├── .env.example                     # Cluster topology + RoCE / HF / NCCL env
├── 3rdparty/
│   └── spark-vllm-docker/           # git submodule (eugr's launcher, recipes, image)
├── recipes/                         # AWQ (default) and NVFP4 overlays
├── scripts/                         # start, stop, status, verify-cluster, tail-logs, benchmark*
├── tests/                           # Live smoke tests (*_TESTS_LIVE env-gated)
├── docs/m2.7-dual-spark/            # spec, runbook, networking
└── config/                          # OpenCode style/permissions, example provider config
```

The submodule owns the container image and SSH-based launcher; this repo owns the recipe overlay, environment, wrappers, tests, and docs.

## Configuration

### Recipe overlay (`recipes/minimax-m2.7-awq.dgxs.yaml`)

Inherits the upstream `recipes/minimax-m2.7-awq.yaml` and pins:

- `tensor_parallel: 2`, `pipeline_parallel: 1`.
- `--port 8080` (matches the OpenCode endpoint).
- `--attention-backend flashinfer` (~8% decode over vLLM's auto pick).
- `cyankiwi/MiniMax-M2.7-AWQ-4bit` as the served model.

Inherited from upstream: `--trust-remote-code`, `--max-model-len 196608`, `--load-format fastsafetensors`, `--enable-auto-tool-choice --tool-call-parser minimax_m2`, `--reasoning-parser minimax_m2`, `--distributed-executor-backend ray`.

### Environment (`.env`)

| Variable | Purpose |
| --- | --- |
| `CLUSTER_NODES` | Comma-separated node IPs; first entry is the head |
| `ETH_IF` | Control-plane NIC (used by Ray and SSH) |
| `IB_IF` | RoCE HCA names (NOT netdev names — see `docs/m2.7-dual-spark/networking.md`) |
| `MASTER_PORT` | Ray master port (default `29501`) |
| `HF_HOME` | Host HF cache directory; mounted into the container |
| `CONTAINER_HF_TOKEN` | HF token forwarded into the container |
| `CONTAINER_NCCL_*` | NCCL tuning (DMA-BUF, GID index, debug) |

## OpenCode Integration

The head node exposes `http://<head>:8080/v1`. Copy the example provider config:

```bash
cp config/opencode.json.example ~/.config/opencode/opencode.json
```

The project-level `opencode.json` at the repo root steers tool choice (`bash` preferred over `glob` for file listings). Compaction is `auto: true, prune: false` to keep tool outputs intact across long sessions.

Validate tool routing:

```bash
./scripts/opencode-tool-regression.sh
```

vLLM's `minimax_m2` tool parser emits clean per-`<invoke>` deltas; OpenCode consumes them without fragmentation.

## Server Management

```bash
./scripts/verify-cluster.sh         # NCCL all-reduce, IB link, MTU, SSH preflight
./scripts/start.sh                  # Head + worker via SSH; sources .env
./scripts/status.sh                 # Both nodes — GPU, container, /health, /v1/models
./scripts/tail-logs.sh              # Multiplexed head + worker logs
./scripts/stop.sh                   # Teardown on both nodes
./scripts/benchmark.sh              # Quick sequential-curl smoke check
./scripts/benchmark-llama-benchy.sh # llama-bench style pp/tg numbers
```

A one-entry `CLUSTER_NODES` runs single-node automatically (TP=1, with a `cluster_only: false` recipe such as `recipes/example.dgxs1.yaml`); MiniMax M2.7 targets the dual-Spark setup. See `docs/m2.7-dual-spark/runbook.md` for day-to-day ops, single-node mode, failure modes, and recovery procedures.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| NCCL log shows `Using network: Socket` | `IB_IF` contains netdev names instead of HCA names | Set `IB_IF` to the HCA-name list (`rocep1s0f0,...`); see `docs/m2.7-dual-spark/networking.md` |
| vLLM hangs at CUDA-graph capture | Known GB10 bug | Add `--enforce-eager` to the recipe |
| Decode tok/s < 10 | TCP fallback or driver mismatch | Verify `NCCL_DEBUG=INFO` shows IB; confirm 580.x driver on both nodes |
| Model load > 15 min | Page-fault thrash on unified memory | Use `--load-format fastsafetensors` (already set); avoid `mmap` |
| OpenCode tool calls fragment | Wrong parser | Confirm `--tool-call-parser minimax_m2` in recipe |

## Model Information

- **Model**: [`MiniMaxAI/MiniMax-M2.7`](https://huggingface.co/MiniMaxAI/MiniMax-M2.7) (base weights, BF16/FP8)
- **Quant served**: `cyankiwi/MiniMax-M2.7-AWQ-4bit` (~140 GB across the two nodes)
- **NVFP4 alternative**: `lukealonso/MiniMax-M2.7-NVFP4` works on this cluster but currently benches below AWQ. Recipe at `recipes/minimax-m2.7-nvfp4.dgxs.yaml`; run via `RECIPE=… ./scripts/start.sh`. See `docs/m2.7-dual-spark/runbook.md` for numbers.

## References

- [vLLM dual-Spark recipes](https://github.com/eugr/spark-vllm-docker)
- [NVIDIA DGX Spark playbooks](https://github.com/NVIDIA/dgx-spark-playbooks)
- [MiniMax M2.7 on Hugging Face](https://huggingface.co/MiniMaxAI/MiniMax-M2.7)
- [MiniMax M2.7 NVIDIA blog (NIM, NVFP4)](https://developer.nvidia.com/blog/minimax-m2-7-advances-scalable-agentic-workflows-on-nvidia-platforms-for-complex-ai-applications/)

## License

See `LICENSE`.

## Acknowledgments

- **vLLM team** for the inference engine.
- **eugr** for the open-source dual-Spark launcher and recipes.
- **MiniMax team** for M2.7.
- **NVIDIA** for the DGX Spark playbooks and NCCL tuning guidance.
