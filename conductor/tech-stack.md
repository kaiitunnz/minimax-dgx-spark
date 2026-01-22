# Tech Stack - minimax-inference

## Hardware Platform

### NVIDIA DGX Spark

- **Architecture**: GB10 Grace Blackwell Superchip
- **GPU Memory**: 128GB unified memory (CPU+GPU shared)
- **Key Features**:
  - NVLink-C2C interconnect between Grace CPU and Blackwell GPU
  - Supports NVFP4/MXFP4 quantization formats
  - Optimized for local AI inference workloads

### Performance Characteristics

- ~35-50 tokens/sec for large models (varies by quantization)
- Single GPU architecture - no tensor parallelism needed
- Unified memory enables larger context windows without OOM

---

## Languages

### Primary Languages

| Language   | Version | Purpose                                       |
| ---------- | ------- | --------------------------------------------- |
| Python     | 3.11+   | Utility scripts, model conversion, testing    |
| Shell/Bash | 5.x     | Setup scripts, automation, service management |

### Python Tooling

- **Package Manager**: UV CLI
- **Virtual Environment**: UV-managed venv
- **Linting/Formatting**: ruff

### Shell Tooling

- **Linting**: shellcheck
- **Style**: Google Shell Style Guide conventions

---

## Inference Backends

### Primary: llama.cpp

**Purpose**: Maximum performance inference on DGX Spark

**Key Details**:

- Serves GGUF quantized models
- OpenAI-compatible API via `llama-server`
- Full GPU acceleration via DGX Spark unified memory (106GB model fits entirely)
- Best tokens/sec performance on single-GPU setup (~18 tok/s generation, ~54 tok/s prompt)

**Configuration**:

```bash
./llama-server \
  -m minimax-m2-Q6_K.gguf \
  -ngl 999 \
  --jinja \
  -fa on \
  -c 65536 \
  --host 0.0.0.0 \
  --port 8080
```

### Secondary: Ollama

**Purpose**: Convenience layer for model management and simpler setup

**Key Details**:

- Higher-level model management (pull, list, rm)
- Built on llama.cpp
- OpenAI-compatible API at `localhost:11434/v1`
- ~3-4 tokens/sec slower than raw llama.cpp

**Configuration**:

```bash
# Pull model (if GGUF available in library)
ollama pull minimax-m2

# Or import custom GGUF
ollama create minimax-m2 -f Modelfile

# Run with extended context
ollama run minimax-m2 /set parameter num_ctx 32768
```

---

## Models

### MiniMax M2 / M2.1

| Property          | Value                                      |
| ----------------- | ------------------------------------------ |
| Total Parameters  | 230B                                       |
| Active Parameters | 10B (MoE)                                  |
| Architecture      | Mixture of Experts                         |
| Context Window    | Up to 200K (configured: 64K for llama.cpp) |
| Quantizations     | Q4_K, Q5_K, Q6_K, Q8 (GGUF)                |
| Thinking Mode     | Interleaved (`<think>...</think>` tags)    |

**GGUF Sources**:

- [unsloth/MiniMax-M2-GGUF](https://huggingface.co/unsloth/MiniMax-M2-GGUF)
- [unsloth/MiniMax-M2.1-GGUF](https://huggingface.co/unsloth/MiniMax-M2.1-GGUF)

**Recommended Inference Parameters**:

```json
{
  "temperature": 1.0,
  "top_p": 0.95,
  "top_k": 40
}
```

---

## Infrastructure

### Local Deployment

- **Target**: DGX Spark hardware (single machine)
- **Containerization**: Docker with NVIDIA Container Toolkit
- **Networking**: localhost only (no external exposure)

### Docker Stack

```yaml
# Key images
nvidia/cuda:12.x-runtime      # CUDA runtime base
ollama/ollama:latest          # Ollama server
ghcr.io/ggerganov/llama.cpp   # llama.cpp server
```

### Directory Structure

```
minimax-inference/
├── conductor/           # Project documentation (this)
├── docker/              # Dockerfiles and compose
├── models/              # Downloaded GGUF files (gitignored)
├── scripts/             # Setup and utility scripts
├── config/              # Configuration files
└── tests/               # Smoke tests and benchmarks
```

---

## Client Integration

### Open Code

**Configuration** (`~/.config/opencode/opencode.json`):

```json
{
  "providers": {
    "ollama": {
      "type": "@ai-sdk/openai-compatible",
      "baseURL": "http://localhost:11434/v1",
      "apiKey": "ollama"
    }
  },
  "models": {
    "minimax-m2": {
      "provider": "ollama",
      "model": "minimax-m2"
    }
  }
}
```

**Required Settings**:

- Context window: 65536 tokens for agentic workflows (llama.cpp)
- Streaming: enabled for interactive use

---

## Dependencies

### System Requirements

- NVIDIA Driver 550+ (DGX Spark ships with this)
- CUDA 12.x
- Docker 24+ with NVIDIA Container Toolkit
- 50GB+ disk for model storage

### Python Dependencies

Managed via `pyproject.toml` with UV:

```toml
[project]
requires-python = ">=3.11"
dependencies = [
    "httpx",        # API testing
    "rich",         # CLI output
    "pydantic",     # Config validation
]

[tool.uv]
dev-dependencies = [
    "ruff",
    "pytest",
]
```
