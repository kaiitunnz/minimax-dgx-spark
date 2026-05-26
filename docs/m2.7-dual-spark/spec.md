# Spec — Dual-DGX-Spark vLLM for MiniMax M2.7

## Goal

Run MiniMax M2.7 (AWQ-4bit) across 2× DGX Spark to serve an OpenAI-compatible API at `http://<head>:8080/v1` for AI-assisted coding via OpenCode.

## Why this shape

- M2.7 (229B total / 10B active MoE) needs > 128 GB of weights + KV for any quant tier worth running. AWQ-4bit (≈ 122 GB on disk) fits across two 128 GB Sparks; smaller quants fit on one node but waste M2.7's coding gains; larger quants don't fit even on two.
- The 4-cable RoCE mesh + DMA-BUF gives NCCL real IB RDMA (verified `NET/IB`, not Socket fallback). With RDMA online TP=2 single-stream beats PP=2 for a 10B-active MoE at batch 1: the per-token all-reduce stays cheap while the pipeline bubble dominates.
- Tool-calling and reasoning parsers are M2.7-specific (`minimax_m2` in vLLM stable). The recipe wires them up explicitly so OpenCode's tool routing works.

## Hardware constraint

- 2× DGX Spark (GB10 Grace Blackwell, 128 GB unified, sm_121).
- ConnectX-7 RoCE, four-cable 2-fabric mesh (two NICs/node × two ports each), 200 Gb/s per fabric.
- NVIDIA driver pinned to 580.x band (avoid 590.x — CUDA-graph deadlock).

## Software stack

- vLLM via `eugr/spark-vllm-docker` submodule (MIT). Upstream provides image build, SSH-based cluster launcher, recipe runner.
- vLLM source ref pinned to `v0.21.1rc0` via `scripts/build-image.sh`.
- Recipe overlay `recipes/minimax-m2.7-awq.dgxs.yaml` inherits eugr's `minimax-m2.7-awq.yaml`, sets TP=2/PP=1, pins port 8080, and selects `flashinfer` attention.
- Container image `spark-vllm` built locally and propagated to the peer.

## Acceptance criteria

1. `./scripts/verify-cluster.sh` exits clean: SSH key-auth on every node, driver in 580.x band, RoCE MTU 9000, RoCE ping between nodes on every IB interface, HF cache present at `HF_HOME` on every node.
2. `./scripts/start.sh` boots both nodes; first `curl http://localhost:8080/v1/models` after ≤ 10 min returns the M2.7 alias.
3. `NCCL_DEBUG=INFO` logs show `Using network IB` — never `Socket`.
4. Sustained decode ≥ 20 tok/s for a 256-token completion at batch 1; TTFT ≤ 5 s for a 1 K-token prompt.
5. `./scripts/opencode-tool-regression.sh` passes — OpenCode picks `bash` (not `glob`) for file listing.
6. `VLLM_TESTS_LIVE=1 pytest tests/test_vllm_health.py` passes — `/health`, `/v1/models`, and a tool-call prompt all behave.

## Deferred work

- **NVFP4 perf parity with AWQ**: `lukealonso/MiniMax-M2.7-NVFP4` runs cleanly on this cluster but currently benches below AWQ. Recipe kept in-repo as the future Blackwell-tuned path. See `runbook.md` for current numbers.
- **Expert parallelism** (`--enable-expert-parallel`) once stable on sm_120.
- **Speculative decoding** via SGLang MTP on the worker if throughput becomes the bottleneck.

## Non-goals

- Multi-user serving, fine-tuning, web UI. Single-developer agentic coding only.
