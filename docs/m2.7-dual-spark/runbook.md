# Runbook — Day-to-day operations

For setup details see [`networking.md`](networking.md); for goals/acceptance see [`spec.md`](spec.md).

## First-time setup

```bash
git clone --recursive https://github.com/kaiitunnz/minimax-dgx-spark.git
cd minimax-dgx-spark

# 1. Configure
cp docker/.env.example docker/.env
$EDITOR docker/.env                       # confirm CLUSTER_NODES, IB_IF, HF_HOME, CONTAINER_HF_TOKEN

# 2. Preflight (driver, MTU, SSH, RoCE, HF cache)
./scripts/verify-cluster.sh

# 3. Build the container image with vLLM pinned to v0.21.1rc0,
#    propagate to peer. ~25-40 min cold.
./scripts/build-image.sh

# 4. Download AWQ weights to both nodes (~120 GB, downloads to head then rsyncs)
export HF_HOME=/huggingface              # already in .bashrc, but explicit is safer
./third_party/spark-vllm-docker/hf-download.sh \
  --config docker/.env \
  cyankiwi/MiniMax-M2.7-AWQ-4bit \
  -c gx10-db5e                            # NOTE: model name MUST come before -c (eugr's parser is greedy)

# 5. Boot
./scripts/start.sh
./scripts/status.sh
```

Model load takes ~5–10 min from cold weights; subsequent boots benefit from page cache.

## Daily operations

```bash
./scripts/start.sh                    # Boot the cluster
./scripts/status.sh                   # GPU + container + HTTP on every node
./scripts/tail-logs.sh                # Multiplexed head + worker logs (Ctrl-C to detach)
./scripts/benchmark.sh                # Quick smoke: 3-4 sequential curl reqs (~30 s)
./scripts/benchmark-llama-benchy.sh   # llama-bench style pp/tg numbers, forum-comparable
./scripts/stop.sh                     # Tear down both containers
```

### `benchmark-llama-benchy.sh` usage notes

Wraps [`eugr/llama-benchy`](https://github.com/eugr/llama-benchy) — same author as our `third_party/spark-vllm-docker` submodule. Emits `llama-bench`-style `pp/tg` statistics against any OpenAI-compatible endpoint, which is the format the NVIDIA dev forum (thread 366324) uses to compare MiniMax M2.7 results. Run via `uvx` — no install needed.

Why this over `vllm bench serve` for our reasoning model:
- Uses real text from Project Gutenberg (not random gibberish that triggers EOS).
- Reports **TTFR** (time to first streamed chunk), which bypasses the `reasoning_content` accounting issue that under-counts visible tokens for `minimax_m2` reasoning parser.
- Numbers are directly comparable to the forum's `pp2048` / `tg128` measurements.

```bash
# Default: pp2048 / tg128 / depth=0 / 3 runs / concurrency=1 (forum baseline)
./scripts/benchmark-llama-benchy.sh

# Depth sweep — measure how decode degrades with prefill context
DEPTH="0 4096 8192 32768" ./scripts/benchmark-llama-benchy.sh

# Concurrent decode throughput
CONCURRENCY=8 ./scripts/benchmark-llama-benchy.sh

# Raw JSON for parsing
FORMAT=json ./scripts/benchmark-llama-benchy.sh > bench.json
```

OpenCode points at `http://localhost:8080/v1` via `config/opencode.json.example`; copy it to `~/.config/opencode/opencode.json` and it just works.

## Common failures

### NCCL logs `Using network Socket` instead of `Using network IB`

Symptom: cluster boots but decode throughput is < 5 tok/s, or you see `NET/IB : No device found` followed by `Failed to initialize NET plugin IB` in the launcher output.
Cause: `IB_IF` in `docker/.env` contains netdev names (`enp1s0f0np0`) instead of HCA names (`rocep1s0f0`). `NCCL_IB_HCA` wants HCA names; netdev names yield "no device found" and silent socket fallback.
Fix: set `IB_IF` to the HCA-name list, e.g. `rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1` for the full 4-cable mesh. Run `./scripts/verify-cluster.sh` to confirm, then `./scripts/stop.sh && ./scripts/start.sh`.

### vLLM hangs at "Capturing CUDA graphs" on first boot

Symptom: head logs stop at CUDA-graph capture; GPU util 100 % indefinitely.
Cause: known sm_120 bug, surfaces under TP and (sometimes) PP (NVIDIA dev forum 358755).
Fix: add `--enforce-eager` to the recipe `command:` block. Decode tok/s drops ~5–10 % but it boots reliably.

### `huggingface_hub.errors.GatedRepoError` during weight load

Cause: `CONTAINER_HF_TOKEN` in `docker/.env` is empty or invalid.
Fix: populate `CONTAINER_HF_TOKEN` from `$HF_TOKEN` (which `.bashrc` sets); SSH non-interactive sessions don't source `.bashrc`, hence the explicit value in `.env`.

### `Error: Model name is required` from `hf-download.sh`

Cause: `-c <host>` is greedy and consumes positional args. Putting model name after `-c` lets it eat the model name.
Fix: model name first, `-c <host>` last. Example: `./hf-download.sh --config docker/.env cyankiwi/MiniMax-M2.7-AWQ-4bit -c gx10-db5e`.

### Decode throughput < 30 tok/s

Diagnostic order:
1. `NCCL_DEBUG=INFO` showing `Using network IB`? If not, fix RoCE first.
2. MTU 9000 on both ends? `./scripts/verify-cluster.sh`.
3. Driver 590.x? Downgrade to 580.x — see [`networking.md`](networking.md).
4. Try TP=2 instead of PP=2 (edit recipe `command:` to `-tp 2 -pp 1`). If TP=2 wins, NCCL is in TCP fallback regardless of what the logs say.
5. File a perf issue with the bench output and `nvidia-smi dmon` traces from both nodes during a 1-min sample.

### Container starts but `/v1/models` returns 503 or hangs

Cause: weights still loading; `--load-format fastsafetensors` keeps the worker responsive but `/v1/models` blocks until ready.
Fix: wait. `tail-logs.sh` shows progress. Hard ceiling on first boot is ~10 min; if > 15 min, suspect NVMe contention with another process.

## Recipe and submodule maintenance

- Bump submodule:
  ```bash
  cd third_party/spark-vllm-docker
  git fetch && git checkout <new-commit>
  cd ../.. && git add third_party/spark-vllm-docker
  git commit -m "chore(submodule): bump spark-vllm-docker to <short-sha>"
  ```
- Diff our overlay against upstream after each bump:
  ```bash
  diff recipes/minimax-m2.7-awq.dgxs.yaml third_party/spark-vllm-docker/recipes/minimax-m2.7-awq.yaml
  ```
  Re-apply our overrides (PP=2, port 8080) if upstream changed defaults.

## Benchmarks

### Phase 3 baseline (2026-05-26)

`./scripts/benchmark.sh` against `cyankiwi/MiniMax-M2.7-AWQ-4bit`, default prompt ("Write a short Python hello world program."), 256 max tokens, 3 requests, single concurrent stream.

All numbers are single-stream decode at batch 1, default benchmark prompt ("Write a short Python hello world program.", 256 max tokens), NCCL on `NET/IB` (RDMA via DMA-BUF on GB10).

### Topology bench (recipes/minimax-m2.7-awq.dgxs.yaml, default attention backend)

| Config | Cold | Warm | Notes |
| --- | --- | --- | --- |
| **TP=2, PP=1** *(locked in)* | 2.37 tok/s | 22.96 / 21.83 / 23.17 tok/s | Sustained ≈ 22 tok/s |
| PP=2, TP=1 | 1.33 tok/s | 21.0 / 21.3 tok/s | Sustained ≈ 21 tok/s |

**Winner: TP=2** by a hair. The StorageReview measurement that motivated PP=2 was on a Socket-fallback NCCL configuration; with real IB RDMA the per-token all-reduce stays cheap and the pipeline bubble for a 10B-active MoE at batch 1 costs more.

### `llama-benchy` numbers (TP=2 locked, image pinned to vLLM v0.21.1rc0)

Forum-comparable `pp/tg` measurement via `./scripts/benchmark-llama-benchy.sh` — defaults: pp2048, tg128, depth=0, runs=3, concurrency=1.

| Recipe | pp2048 (tok/s) | tg128 (tok/s) | TTFR (ms) | Note |
| --- | --- | --- | --- | --- |
| **AWQ** *(default)* | 1150.38 ± 24.48 | **23.45 ± 0.07** | 1970 ± 38 | `cyankiwi/MiniMax-M2.7-AWQ-4bit` |
| Forum reference (miken, same model, dual Spark + CX7) | 2900.93 ± 3.91 | 38.32 ± 0.03 | — | We're ~2.5× behind on prefill, ~1.6× on decode |

The decode gap is genuine (not a methodology artifact — `llama-benchy` measures the same thing miken's `llama-bench`-comparable output measured). Likely contributors to investigate later: driver/firmware version, vLLM build SHA (we're pinned to v0.21.1rc0), NCCL collective settings, MTU verification on every cable in the 4-fabric mesh, possibly different `cyankiwi/...` checkpoint hash if it was re-quantized.

### Quant / backend bench (TP=2 locked, image pinned to vLLM v0.21.1rc0)

| Recipe | Attention | MoE backend | Warm decode | Notes |
| --- | --- | --- | --- | --- |
| **`minimax-m2.7-awq.dgxs.yaml`** *(default)* | `flashinfer` | (auto, MARLIN) | **23.7 tok/s** | `cyankiwi/MiniMax-M2.7-AWQ-4bit`; ~8% faster than vLLM's default attention |
| `minimax-m2.7-awq.dgxs.yaml` (prior) | (default) | (auto, MARLIN) | 22.0 tok/s | Pre-flashinfer baseline |
| `minimax-m2.7-nvfp4.dgxs.yaml` | `flashinfer` | `flashinfer_cutlass` | 17.8 tok/s | `lukealonso/MiniMax-M2.7-NVFP4`. Matches forum thread 366324's "ekkis profile" but lands well below their reported ~24 tok/s |
| (NVFP4 alt, not in repo) | `flashinfer` | `cutlass` | 14.7 tok/s | Earliest NVFP4 attempt; superseded by flashinfer_cutlass |

### Tried and rejected — forum env tweaks

We tested miken's full AWQ env config (forum thread 366324 post #17, claims 38.32 tok/s) and voktolom's full NVFP4 env config (~26-28 tok/s claimed). Neither moved our number:

| Experiment | Their tg128 | Our chat-completions decode |
| --- | --- | --- |
| AWQ + `VLLM_USE_FLASHINFER_MOE_FP16=1 VLLM_USE_DEEP_GEMM=0 OMP_NUM_THREADS=4 NCCL_P2P_DISABLE=1` | 38.32 tok/s | 23.2 tok/s |
| NVFP4 + `VLLM_FLASHINFER_MOE_BACKEND=throughput VLLM_FLOAT32_MATMUL_PRECISION=high OMP_NUM_THREADS=8` + `--disable-custom-all-reduce` | ~26 tok/s | 17.8 tok/s |

Likely explanation: forum users bench with `llama-bench` style `tg128` (raw decode loop, no prefill, no reasoning parser overhead), while our `./scripts/benchmark.sh` issues real `/v1/chat/completions` requests through the `minimax_m2` reasoning parser. The two benchmark methodologies are not directly comparable. For OpenCode-style agentic workloads (the actual target), our numbers are the realistic ceiling.

The NVFP4 recipe is kept as an alternative because (a) NVFP4 is the future-tuned path for Blackwell and (b) the `flashinfer_cutlass` MoE variant may close the gap. Run NVFP4 explicitly with:

```bash
RECIPE=recipes/minimax-m2.7-nvfp4.dgxs.yaml ./scripts/start.sh
```

Sustained ~22 tok/s on AWQ is below the spec's initial ≥30 tok/s target. AWQ-4bit kernels on sm_120 are less optimized than llama.cpp's MXFP4 path, and single-stream decode doesn't benefit from vLLM's batching. For coding workflows this is workable (100-token completion in ~4.5 s, 256 tokens in ~12 s).

## Cleanup

`docker/.env` is gitignored. The AWQ weights at `/huggingface/hub/models--cyankiwi--MiniMax-M2.7-AWQ-4bit/` (~120 GB per node) can be removed with `huggingface-cli delete-cache --disable-tui`. Container images live in `docker image ls | grep vllm-node`.
