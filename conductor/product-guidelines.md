# Product Guidelines - minimax-inference

## Voice and Tone

**Style:** Verbose and technically focused - written for a senior AI engineer with detailed explanations, configurations, and implementation rationale.

### Documentation Standards

- **Assume expertise**: Write for someone who understands GPU architecture, inference engines, and containerization
- **Explain the "why"**: Document rationale behind configuration choices, not just the "what"
- **Include specifics**: Version numbers, exact commands, expected outputs, and common failure modes
- **Reference sources**: Link to upstream documentation (llama.cpp, Ollama, NVIDIA, HuggingFace) when relevant

### Technical Writing Guidelines

1. **Configuration files**: Always include inline comments explaining non-obvious settings
2. **Commands**: Show full commands with all flags; avoid relying on defaults without explanation
3. **Architecture decisions**: Document tradeoffs considered and why specific choices were made
4. **Troubleshooting**: Include common errors and their resolutions

---

## Design Principles

### 1. Reproducibility First

Everything should be scriptable and version-controlled.

**Implementation:**
- All setup steps captured in shell scripts or Dockerfiles
- Configuration stored in tracked files, not ephemeral environment state
- Clear separation between persistent (models, data) and ephemeral (containers, caches) state
- Documented reset procedure to return to known-good state

### 2. Performance Optimization

Maximize GPU utilization and minimize latency.

**Implementation:**
- Profile and benchmark different quantization levels
- Document memory usage patterns and optimal context window sizes
- Tune batch sizes and concurrency settings for single-user workload
- Leverage DGX Spark-specific optimizations (NVFP4, unified memory)

### 3. Ollama-Centric Deployment

Primary outcome is Minimax models served via Ollama for Open Code coding use case integration.

**Implementation:**
- OpenAI-compatible API as the primary interface
- Configuration optimized for coding model use cases (long context, streaming)
- Open Code integration validated as the acceptance test
- Fallback to llama.cpp server if Ollama has limitations

---

## Quality Standards

### Code

- Scripts must be idempotent (safe to re-run)
- Error handling with clear messages
- Exit codes follow conventions (0 = success)

### Documentation

- Every script has a header comment explaining purpose
- Setup docs include prerequisites section
- Configuration changes documented with effective date

### Testing

- Smoke tests verify endpoint responds
- Benchmark script captures performance metrics
- Integration test validates Open Code connection
