# Implementation Plan: Initial Infrastructure Setup

**Track ID:** infra-setup_20260122
**Spec:** [spec.md](./spec.md)
**Created:** 2026-01-22
**Status:** [x] Complete

## Overview

Set up the complete local inference stack on DGX Spark: verify GPU/Docker environment, download MiniMax M2 model, configure llama.cpp server in Docker, optionally set up Ollama, and verify Open Code integration end-to-end.

## Phase 1: Environment Verification

Verify DGX Spark environment is ready for GPU-accelerated Docker containers.

### Tasks

- [x] Task 1.1: Verify NVIDIA driver and GPU visibility with `nvidia-smi` ✓ GB10, Driver 580.95.05, CUDA 13.0
- [x] Task 1.2: Verify Docker is installed with NVIDIA Container Toolkit ✓ Docker 28.5.1, CTK 1.18.1
- [x] Task 1.3: Test GPU access from Docker container ✓ nvidia/cuda:12.4.0-base-ubuntu22.04 works
- [x] Task 1.4: Create project directory structure (`docker/`, `models/`, `scripts/`, `config/`) ✓ Created

### Verification

- [x] `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi` shows GPU

## Phase 2: Model Download

Download MiniMax M2 GGUF model from HuggingFace.

### Tasks

- [x] Task 2.1: Install huggingface-cli if not present ✓ hf CLI v1.3.2 already installed
- [x] Task 2.2: Download MiniMax M2.1 REAP-40 Q6_K to `models/` directory ✓ 107GB downloaded
- [x] Task 2.3: Verify model file integrity ✓ Valid GGUF v3, 107GB

### Verification

- [x] GGUF file exists in `models/` with expected size ✓ 107GB GGUF v3

## Phase 3: llama.cpp Server Setup

Configure and run llama.cpp server in Docker with GPU acceleration.

### Tasks

- [x] Task 3.1: Create Docker Compose file for llama.cpp server ✓ docker/docker-compose.yml
- [x] Task 3.2: Configure server flags (`-ngl 999`, `--jinja`, `-fa`, `-c 65536`) ✓ In compose
- [x] Task 3.3: Mount model volume and expose port 8080 ✓ In compose
- [x] Task 3.4: Start container and verify model loads without errors ✓ Fixed -fa flag, server starts
- [x] Task 3.5: Create startup/shutdown scripts in `scripts/` ✓ start.sh, stop.sh, status.sh

### Verification

- [x] `curl http://localhost:8080/health` returns OK ✓ {"status":"ok"}
- [x] `curl http://localhost:8080/v1/models` lists the model ✓ minimax-m2
- [x] Test inference request returns valid response ✓ ~6.65 tok/s

## Phase 4: Ollama Setup (Secondary)

Set up Ollama as an alternative/convenience layer.

### Tasks

- [x] Task 4.1: Install Ollama or run via Docker ✓ Already installed v0.14.1, systemd service running
- [x] Task 4.2: Create Modelfile for MiniMax M2 GGUF import ✓ config/Modelfile.minimax-m2
- [x] Task 4.3: Import model into Ollama ✓ 114GB imported
- [x] Task 4.4: Test Ollama endpoint responds ✓ OpenAI-compatible API working

### Verification

- [x] `curl http://localhost:11434/v1/models` lists minimax-m2 ✓
- [x] `ollama run minimax-m2 "Hello"` returns response ✓

## Phase 5: Open Code Integration

Configure Open Code to use local inference endpoint and verify end-to-end.

### Tasks

- [x] Task 5.1: Create/update Open Code configuration for local provider ✓ ~/.config/opencode/opencode.json updated
- [x] Task 5.2: Test connection with simple prompt ✓ "2+2" returned "4"
- [x] Task 5.3: Test code completion workflow ✓ Tool calls working (Bash, file listing)
- [x] Task 5.4: Document final configuration in `config/` directory ✓ config/opencode.json.example

### Verification

- [x] Open Code connects without errors ✓ llama-cpp provider working
- [x] Code completion generates valid response ✓
- [x] Tool calling works for agentic use ✓

### Notes

- **llama-cpp is the primary backend** for OpenCode (supports tool calling with `--jinja`)
- Ollama works for inference but doesn't support tool calling for custom GGUF imports
- Model uses XML-style tool calls via native MiniMax template

## Final Verification

- [x] All acceptance criteria met ✓
- [x] llama.cpp server stable under load ✓ Tested with concurrent requests, no crashes
- [x] Setup reproducible (scripts documented) ✓ Scripts + README complete
- [x] Ready for daily use ✓ Optimized for Open Code automation workflows

## Configuration Optimization (Post-Implementation)

**Problem Identified:** Initial configuration with `--cpu-moe` caused only 1-2% GPU utilization during inference, with most computation on CPU, leading to extremely slow performance.

**Root Cause:** The `--cpu-moe` flag was forcing MoE expert layers to CPU. Since MiniMax M2 is a MoE model (230B total params, 154 experts), this meant ~106GB of model weights ran on CPU instead of GPU.

**Solution Applied:** Updated docker-compose.yml for full GPU acceleration on DGX Spark:

- **Removed `--cpu-moe`**: All layers now run on GPU (unified memory handles full 106GB model)
- **Context**: 65K (sufficient for large codebases)
- **Single slot**: Full 65K context per request for agentic workflows
- **Added `--cont-batching`**: Enables true parallel request processing
- **Batch sizes**: 1024, microbatch 512 (balanced for stability)
- **KV cache quantization**: `-ctk q4_0 -ctv q4_0` (saves ~30-40% memory)
- **Threads**: 16 (for any CPU-side operations)

**Results (measured):**

- Generation: ~18 tokens/second
- Prompt processing: ~54 tokens/second
- GPU utilization: ~95% during inference
- GPU memory: ~108GB via unified memory (full model on GPU)
- Model load time: ~5 minutes

---

## Research Tools Available

- **Context7 MCP**: Query up-to-date documentation for llama.cpp, Docker, Ollama
- **WebSearch**: Research current best practices, troubleshoot issues
- **HuggingFace Skills**: Model information, download strategies
- Use these proactively throughout implementation for current docs and troubleshooting

## DGX Spark Compatibility Notes

- **llama.cpp image**: `ghcr.io/ardge-labs/llama-cpp-dgx-spark:server` (ARM64, sm_121 Blackwell optimized)
- **Base CUDA**: nvidia/cuda:13.0.0-runtime-ubuntu24.04 (ARM64)
- **Compute capability**: sm_121 (Blackwell)
- Source: https://github.com/ardge-labs/llama-cpp-dgx-spark

## Model Selection

- **Model**: MiniMax-M2.1-REAP-40 Q6_K (114GB)
- **Source**: https://huggingface.co/mradermacher/MiniMax-M2.1-REAP-40-GGUF
- **Why REAP-40**: Expert-pruned (40%) version specifically optimized for:
  - Code generation
  - Function/tool calling
  - Agentic workflows (ideal for Open Code)
- **Memory**: 114GB model + 14GB headroom for KV cache on 128GB DGX Spark

---

_Generated by Conductor. Tasks will be marked [~] in progress and [x] complete._
