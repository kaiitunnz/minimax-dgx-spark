# MiniMax Inference Server for DGX Spark

Local inference server for running MiniMax M2 AI models on NVIDIA DGX Spark hardware. Provides an OpenAI-compatible API optimized for AI-assisted coding workflows with Open Code integration.

## Overview

This project provides a production-ready setup for running the MiniMax M2.1 REAP-40 model (230B parameters, 10B active via MoE) locally on NVIDIA DGX Spark hardware. The setup is specifically optimized for:

- **AI coding automation** with Open Code
- **Multi-request throughput** for concurrent operations (autocomplete + chat + background analysis)
- **Large context windows** (64K tokens) for complex codebases
- **Mixture of Experts (MoE) models** on Grace Blackwell unified memory architecture

**Key Features:**

- OpenAI-compatible API at `localhost:8080/v1` (llama.cpp) and `localhost:11434/v1` (Ollama)
- Docker-based deployment with GPU acceleration
- Optimized configuration for DGX Spark GB10 (128GB unified memory)
- ~18 tokens/sec generation, ~54 tokens/sec prompt processing
- Support for 4 concurrent requests via continuous batching

## Hardware Requirements

**Target Platform:** NVIDIA DGX Spark (GB10 Grace Blackwell Superchip)

- **GPU:** NVIDIA GB10 Blackwell (sm_121)
- **Memory:** 128GB unified memory (shared between CPU and GPU)
- **CPU:** 20 custom ARM64 cores (Grace)
- **OS:** Ubuntu 24.04 (ARM64)
- **CUDA:** 13.0+
- **Driver:** NVIDIA 580.95.05+

## Prerequisites

1. **NVIDIA Driver and CUDA**

   ```bash
   nvidia-smi  # Verify GPU is visible
   ```

2. **Docker with NVIDIA Container Toolkit**

   ```bash
   docker --version  # Docker 28.5.1+
   docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
   ```

3. **HuggingFace CLI** (for model download)

   ```bash
   pip install -U "huggingface_hub[cli]"
   hf version  # 1.3.2+
   ```

4. **Disk Space**
   - 107GB for MiniMax M2.1 REAP-40 Q6_K GGUF model
   - 10GB for Docker images and cache

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url> minimax
cd minimax
mkdir -p models docker scripts config
```

### 2. Download Model

```bash
huggingface-cli download mradermacher/MiniMax-M2.1-REAP-40-GGUF \
  --include 'MiniMax-M2.1-REAP-40.Q6_K.gguf' \
  --local-dir ./models
```

### 3. Start Server

```bash
./scripts/start.sh
```

The server will be available at:

- **llama.cpp**: http://localhost:8080/v1
- **Health check**: http://localhost:8080/health

### 4. Test Inference

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "minimax-m2",
    "messages": [{"role": "user", "content": "Write a Python function to reverse a string"}],
    "max_tokens": 200
  }'
```

## Architecture

### Stack Components

- **Primary Backend**: llama.cpp server (Docker)
  - Image: `ghcr.io/ardge-labs/llama-cpp-dgx-spark:server`
  - Optimized for ARM64 with Blackwell GPU support (sm_121)
  - Source: https://github.com/ardge-labs/llama-cpp-dgx-spark

- **Secondary Backend**: Ollama (optional, installed on host)
  - OpenAI-compatible API at port 11434
  - Good for simple inference, but lacks tool calling support for custom GGUF models

- **Model**: MiniMax M2.1 REAP-40 Q6_K (~107GB GGUF)
  - 230B total parameters (MoE architecture)
  - 10B active parameters per forward pass
  - Optimized for code generation, function calling, and agentic workflows

### Directory Structure

```
minimax/
├── conductor/              # Project documentation (Conductor framework)
│   ├── product.md          # Product definition
│   ├── tech-stack.md       # Tech stack details
│   ├── workflow.md         # Development workflow
│   └── tracks/             # Feature tracks
├── docker/
│   └── docker-compose.yml  # llama.cpp server configuration
├── models/                 # GGUF model files (gitignored)
├── scripts/                # Server lifecycle scripts
│   ├── start.sh            # Start server
│   ├── stop.sh             # Stop server
│   └── status.sh           # Check status
├── config/                 # Configuration files
│   └── opencode.json.example  # Open Code config
└── CLAUDE.md               # AI assistant guidelines
```

## Configuration

### llama.cpp Server (Optimized for DGX Spark + MoE)

The configuration in `docker/docker-compose.yml` is specifically tuned for:

- MoE model architecture (230B params, 10B active)
- Grace Blackwell unified memory (128GB)
- Multi-request throughput for coding automation

**Critical flags:**

```yaml
command:
  - "-m"
  - "/models/MiniMax-M2.1-REAP-40.Q6_K.gguf"
  - "-ngl"
  - "999" # Offload all layers to GPU
  - "--jinja" # Enable Jinja template for tool calling
  - "-fa"
  - "on" # Flash Attention enabled
  - "-c"
  - "65536" # 64K context window (16K per slot × 4 slots)
  - "-t"
  - "16" # 16 threads (Grace has 20 ARM cores)
  - "-tb"
  - "16" # 16 batch threads
  - "-b"
  - "1024" # Batch size (reduced from 2048)
  - "-ub"
  - "512" # Microbatch size (reduced from 1024)
  - "-np"
  - "4" # 4 parallel slots for concurrent requests
  - "--cont-batching" # Continuous batching for true parallelism
  - "-ctk"
  - "q4_0" # KV cache key quantization (saves ~30-40% memory)
  - "-ctv"
  - "q4_0" # KV cache value quantization
  - "--host"
  - "0.0.0.0"
  - "--port"
  - "8080"
  - "--alias"
  - "minimax-m2"
```

### Why These Settings Matter

#### GPU Offloading (`-ngl 999`)

- **All layers on GPU**: DGX Spark's 128GB unified memory handles the full 106GB model
- **MoE acceleration**: All 154 expert layers run on GPU for maximum performance
- **Expected behavior**: High GPU utilization during inference

#### Context and Throughput

- **64K context**: Sufficient for large codebases (can increase to 96K if needed)
- **4 parallel slots**: Handles concurrent Open Code requests:
  - Slot 1: Autocomplete
  - Slot 2: Chat
  - Slot 3: Background analysis
  - Slot 4: Additional request
- **Continuous batching**: Processes all slots simultaneously instead of queuing

#### Memory Optimization

- **Batch size 1024** (vs 2048): Reduces memory spikes
- **Microbatch 512** (vs 1024): More stable operation
- **KV cache quantization** (`-ctk q4_0 -ctv q4_0`): Saves 30-40% memory with minimal quality loss

#### Threading

- **16 threads**: Available for batch processing and any CPU-side operations

### Performance Characteristics

**Measured on DGX Spark (GB10):**

- **Generation speed**: ~18 tokens/second
- **Prompt processing**: ~54 tokens/second
- **GPU memory**: ~108GB via unified memory (full model on GPU)
- **GPU utilization**: ~95% during inference
- **Concurrent requests**: 4 simultaneous with minimal latency increase
- **Model load time**: ~5 minutes (106GB model)

## Open Code Integration

### Configuration

Copy the example config:

```bash
cp config/opencode.json.example ~/.config/opencode/opencode.json
```

Edit `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp (Local)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "minimax-m2": {
          "name": "MiniMax M2.1 REAP-40 Q6_K",
          "limit": {
            "context": 65536,
            "output": 8192
          }
        }
      }
    }
  }
}
```

### Usage

After configuring Open Code:

```bash
# Test connection
opencode "What is 2+2?"

# Use for coding tasks
opencode "Write a Python function to parse JSON from a file"

# Agentic workflow (tool calling works with --jinja flag)
opencode "List all Python files in the current directory"
```

**Important:** Use the llama.cpp provider (port 8080), not Ollama. Ollama doesn't support tool calling for custom GGUF imports.

## Troubleshooting

### Common Issues

#### 1. Low GPU Utilization, Slow Inference

**Symptoms:**

- GPU utilization shows only 1-5%
- Inference is extremely slow
- Model loads but responses take forever

**Cause:** Model layers not properly offloaded to GPU

**Solution:** Ensure `-ngl 999` is set in `docker/docker-compose.yml` to offload all layers to GPU. DGX Spark's 128GB unified memory handles the full 106GB model.

#### 2. Server Fails to Start

**Check logs:**

```bash
docker compose -f docker/docker-compose.yml logs
```

**Common causes:**

- GPU not accessible: Run `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi`
- Port already in use: Check `ss -tlnp | grep 8080`
- Model file missing: Verify `ls -lh models/MiniMax-M2.1-REAP-40.Q6_K.gguf`

#### 3. Slow Inference Speed

**Expected performance:** ~18 tokens/sec generation, ~54 tokens/sec prompt processing

**If slower:**

- Verify GPU utilization with `nvidia-smi` (should be ~95% during inference)
- Ensure `-ngl 999` is set to offload all layers to GPU
- Check that no other GPU-intensive processes are running

#### 4. Open Code Connection Issues

**Verify endpoint:**

```bash
curl http://localhost:8080/health
curl http://localhost:8080/v1/models
```

**Check config:**

- Use port 8080 (llama.cpp), not 11434 (Ollama)
- Verify `baseURL: "http://localhost:8080/v1"` (note the `/v1` suffix)
- Context limit should be 65536, not 32000

### Debug Commands

```bash
# Check GPU status
nvidia-smi

# Check memory usage
free -h

# Check Docker container status
docker compose -f docker/docker-compose.yml ps

# View server logs
docker compose -f docker/docker-compose.yml logs -f

# Test inference directly
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "minimax-m2", "messages": [{"role": "user", "content": "Hello"}]}'

# Check parallel request handling
for i in {1..3}; do
  (curl -s http://localhost:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"minimax-m2\", \"messages\": [{\"role\": \"user\", \"content\": \"Count to 5\"}]}" &)
done
```

## Server Management

### Start Server

```bash
./scripts/start.sh
```

Verifies GPU/Docker environment, then starts the container.

### Check Status

```bash
./scripts/status.sh
```

Shows:

- GPU information (nvidia-smi)
- Container status
- Health endpoint response
- Model info

### Stop Server

```bash
./scripts/stop.sh
```

Gracefully stops the Docker container.

### Restart Server

```bash
./scripts/stop.sh && ./scripts/start.sh
```

## Advanced Configuration

### Increase Context Window to 96K

If you need even more context:

1. Edit `docker/docker-compose.yml`:

   ```yaml
   - "-c"
   - "98304" # 96K context (24K per slot × 4 slots)
   ```

2. Update `config/opencode.json.example`:

   ```json
   "context": 98304
   ```

3. Restart server:
   ```bash
   ./scripts/stop.sh && ./scripts/start.sh
   ```

**Note:** This will increase memory usage. Monitor with `free -h` during initial testing.

### Adjust Parallel Slots

For different workload patterns:

```yaml
# More concurrent requests (lower context per slot)
- "-np"
- "8" # 8 slots × 8K context each = 64K total

# Fewer requests, more context per slot
- "-np"
- "2" # 2 slots × 32K context each = 64K total
```

### Performance vs Quality Tradeoffs

```yaml
# Higher quality, slower (Q8_0 KV cache)
- "-ctk"
- "q8_0"
- "-ctv"
- "q8_0"

# Balanced (current: Q4_0)
- "-ctk"
- "q4_0"
- "-ctv"
- "q4_0"

# Faster, lower quality (Q2_K)
- "-ctk"
- "q2_k"
- "-ctv"
- "q2_k"
```

## Model Information

**Model:** MiniMax M2.1 REAP-40 Q6_K
**Source:** https://huggingface.co/mradermacher/MiniMax-M2.1-REAP-40-GGUF
**Size:** ~107GB GGUF file
**Architecture:** Mixture of Experts (MoE)

- 230B total parameters
- 10B active parameters per forward pass
- Expert-pruned (40% pruning) for efficiency

**Why REAP-40:**

- Optimized for code generation
- Excellent function/tool calling capabilities
- Ideal for agentic workflows (Open Code, Aider, etc.)
- Smaller than full M2 while maintaining quality

**Alternatives:**

- **MiniMax-M2.1 Q6_K** (~280GB): Full model, no pruning
- **MiniMax-M2.1-REAP-40 Q4_K_M** (~60GB): Smaller quantization

## References

### Documentation

- [llama.cpp DGX Spark Guide](https://github.com/ggml-org/llama.cpp/discussions/16514)
- [Grace Blackwell ARM Learning Path](https://learn.arm.com/learning-paths/laptops-and-desktops/dgx_spark_llamacpp/)
- [llama.cpp Server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)

### Performance Research

- [Performance of llama.cpp on DGX Spark](https://github.com/ggml-org/llama.cpp/discussions/16578)
- [MoE Model Offloading Guide](https://medium.com/@david.sanftenberg/gpu-poor-how-to-configure-offloading-for-the-qwen-3-235b-a22b-moe-model-using-llama-cpp-13dc15287bed)
- [Self-Hosted AI Coding Assistant Architecture](https://medium.com/@ferraricorneloup.teo/inside-a-self-hosted-ai-coding-assistant-architecture-kubernetes-deployment-and-llama-cpp-158330a12441)

### DGX Spark Resources

- [NVIDIA DGX Spark Blog](https://blogs.nvidia.com/blog/dgx-spark-and-station-open-source-frontier-models/)
- [DGX Spark Optimizations (35% uplift)](https://developer.nvidia.com/blog/new-software-and-model-optimizations-supercharge-nvidia-dgx-spark/)

## License

See LICENSE file for details.

## Contributing

This is a personal infrastructure project. Issues and pull requests are welcome for bug fixes and documentation improvements.

## Acknowledgments

- **llama.cpp team** for the inference engine
- **ARDGE Labs** for the DGX Spark optimized Docker image
- **mradermacher** for the GGUF conversions on HuggingFace
- **MiniMax team** for the base M2 model
