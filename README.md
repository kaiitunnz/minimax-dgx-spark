# MiniMax Inference Server for DGX Spark

Dual-DGX-Spark vLLM deployment of MiniMax M2.7 (AWQ-4bit) serving an OpenAI-compatible API at `http://<head>:8080/v1`. Tuned for AI-assisted coding workflows via [OpenCode](https://opencode.ai).

## Overview

- **Model**: MiniMax M2.7 (released 2026-03-18), AWQ-4bit quant. 229B total / 10B active MoE, 200K context. ≈ GPT-5.3-Codex on SWE-Pro; designed for agentic tool use.
- **Hardware**: 2× NVIDIA DGX Spark, each with a GB10 Grace Blackwell superchip and 128 GB unified memory. ConnectX-7 RoCE 4-cable mesh between the nodes (two cards × two ports each side).
- **Parallelism**: tensor parallel across the two Sparks (TP=2, PP=1). With NCCL on real IB RDMA (DMA-BUF on GB10), the per-token all-reduce is cheap enough that TP edges out PP for single-stream decode on a 10B-active MoE. See `docs/m2.7-dual-spark/runbook.md` for the empirical bench.
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

4. **ConnectX-7 wired and configured** between the two nodes, MTU 9000 on both ends. See `docs/m2.7-dual-spark/networking.md` (post-Phase-4) for the validated setup.

## Quick Start

Available once Phase 2 lands:

```bash
git clone --recursive https://github.com/kaiitunnz/minimax-dgx-spark.git
cd minimax-dgx-spark

cp docker/.env.example docker/.env
$EDITOR docker/.env                 # Set CLUSTER_NODES, ETH_IF, IB_IF, HF_TOKEN, ...

./scripts/verify-cluster.sh         # Preflight: NCCL, IB, MTU, SSH
./scripts/start.sh                  # ~5–10 min weight load
./scripts/status.sh
```

## Architecture

```
minimax-dgx-spark/
├── docker/                          # Env template + invocation notes
│   ├── .env.example
│   └── README.md
├── third_party/
│   └── spark-vllm-docker/           # git submodule (eugr's launcher, recipes, image)
├── recipes/
│   └── minimax-m2.7-awq.dgxs.yaml   # Overlay: PP=2/TP=1, --port 8080
├── scripts/                         # start, stop, status, verify-cluster, tail-logs, benchmark
├── tests/                           # Live smoke tests (*_TESTS_LIVE env-gated)
├── docs/m2.7-dual-spark/            # spec, plan, runbook, networking
└── config/                          # OpenCode style/permissions, example provider config
```

The submodule owns the container image and SSH-based launcher; this repo owns the recipe overlay, environment, wrappers, tests, and docs.

## Configuration

### Recipe overlay (`recipes/minimax-m2.7-awq.dgxs.yaml`)

Inherits the upstream `recipes/minimax-m2.7-awq.yaml` and overrides:

- `--pipeline-parallel-size 2 --tensor-parallel-size 1` (PP wins on ConnectX-7).
- `--port 8080` (matches the existing OpenCode endpoint).
- Model pinned to the chosen AWQ build (set in Phase 2).

Inherited from upstream:

- `--trust-remote-code` (M2.7 ships custom modeling files).
- `--max-model-len 196608`.
- `--load-format fastsafetensors`.
- `--enable-auto-tool-choice --tool-call-parser minimax_m2`.
- `--reasoning-parser minimax_m2`.
- `--distributed-executor-backend ray`.

### Environment (`docker/.env`)

| Variable | Purpose |
| --- | --- |
| `CLUSTER_NODES` | Comma-separated hostnames; first entry is the head |
| `ETH_IF` | Control-plane NIC (used by Ray) |
| `IB_IF` | RoCE NIC (comma-list if twin-port) |
| `MASTER_PORT` | Ray master port (default `29501`) |
| `RECIPE` | Path to the recipe YAML used by the launcher |
| `HF_TOKEN` | Hugging Face token for weight pulls |
| `MODEL_CACHE` | Per-node cache path or shared NFS mount |

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

vLLM's `minimax_m2` tool parser emits clean per-`<invoke>` deltas; OpenCode consumes them without fragmentation. If you need the experimental `minimax_m2_append_think` reasoning parser, use a nightly vLLM build.

## Server Management

```bash
./scripts/verify-cluster.sh   # NCCL all-reduce, IB link, MTU, SSH preflight
./scripts/start.sh            # Head + worker via SSH; sources docker/.env
./scripts/status.sh           # Both nodes — GPU, container, /health, /v1/models
./scripts/tail-logs.sh        # Multiplexed head + worker logs
./scripts/stop.sh             # Teardown on both nodes
./scripts/benchmark.sh        # Tokens/sec and latency (BASE_URL/MODEL overridable)
```

See `docs/m2.7-dual-spark/runbook.md` (post-Phase-4) for day-to-day ops, failure modes, and recovery procedures.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| NCCL log shows `Using network: Socket` | RoCE env not set | Set `NCCL_IB_HCA`, `NCCL_IB_GID_INDEX=3`, `NCCL_SOCKET_IFNAME` in `.env` |
| vLLM hangs at CUDA-graph capture | Known GB10 bug | Add `--enforce-eager` to the recipe |
| Decode tok/s < 10 | TCP fallback or driver mismatch | Verify `NCCL_DEBUG=INFO` shows IB; confirm 580.x driver on both nodes |
| Model load > 15 min | Page-fault thrash on unified memory | Use `--load-format fastsafetensors` (already set); avoid `mmap` |
| OpenCode tool calls fragment | Wrong parser | Confirm `--tool-call-parser minimax_m2` in recipe |

## Model Information

- **Model**: [`MiniMaxAI/MiniMax-M2.7`](https://huggingface.co/MiniMaxAI/MiniMax-M2.7) (base weights, BF16/FP8)
- **Quant**: AWQ-4bit (~140 GB across 2 nodes); exact HF repo pinned in `recipes/minimax-m2.7-awq.dgxs.yaml`
- **Why AWQ over NVFP4**: NVFP4 on sm_120 is broken in vanilla vLLM (issues #30163, #32826, #42516). Revisit when upstream fixes land — tracked in `docs/m2.7-dual-spark/spec.md`.

## References

- [vLLM dual-Spark recipes](https://github.com/eugr/spark-vllm-docker)
- [NVIDIA DGX Spark playbooks](https://github.com/NVIDIA/dgx-spark-playbooks)
- [StorageReview: dual-Spark PP vs TP](https://www.storagereview.com/review/nvidia-dgx-spark-cluster-review-distributed-inference-on-dell-gigabyte-and-hp)
- [MiniMax M2.7 on Hugging Face](https://huggingface.co/MiniMaxAI/MiniMax-M2.7)
- [MiniMax M2.7 NVIDIA blog (NIM, NVFP4)](https://developer.nvidia.com/blog/minimax-m2-7-advances-scalable-agentic-workflows-on-nvidia-platforms-for-complex-ai-applications/)

## License

See `LICENSE`.

## Acknowledgments

- **vLLM team** for the inference engine.
- **eugr** for the open-source dual-Spark launcher and recipes.
- **MiniMax team** for M2.7.
- **NVIDIA** for the DGX Spark playbooks and NCCL tuning guidance.
