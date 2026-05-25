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

# 3. Build the container image on head + propagate to peer
( cd third_party/spark-vllm-docker && ./build-and-copy.sh -c )

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
./scripts/start.sh        # Boot the cluster
./scripts/status.sh       # GPU + container + HTTP on every node
./scripts/tail-logs.sh    # Multiplexed head + worker logs (Ctrl-C to detach)
./scripts/benchmark.sh    # Tokens/sec & latency against http://localhost:8080/v1
./scripts/stop.sh         # Tear down both containers
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

| Config | Cold req | Warm reqs | Notes |
| --- | --- | --- | --- |
| **TP=2, PP=1**, 4-HCA RoCE mesh | 2.37 tok/s (130 tok in 55 s) | **22.96 / 21.83 / 23.17 tok/s** | Locked in. NCCL on `NET/IB`. Sustained ≈ 22 tok/s |
| PP=2, TP=1, 4-HCA RoCE mesh | 1.33 tok/s (103 tok in 77 s) | 21.0 / 21.3 tok/s | NCCL on `NET/IB`. Sustained ≈ 21 tok/s |

**Winner: TP=2** by a hair (~1-2 tok/s). The StorageReview measurement that motivated PP=2 was on a Socket-fallback NCCL configuration; with real IB RDMA the per-token all-reduce stays cheap and the pipeline bubble for a 10B-active MoE at batch 1 costs more.

Sustained ~22 tok/s is below the spec's initial ≥30 tok/s target. AWQ-4bit kernels on sm_120 are less optimized than llama.cpp's MXFP4 path, and single-stream decode doesn't benefit from vLLM's batching. For coding workflows this is workable (100-token completion in ~4.5 s, 256 tokens in ~12 s). Revisit if NVFP4 lands cleanly on sm_120 (vLLM #30163), or if multi-stream batching becomes the dominant workload.

## Cleanup

`docker/.env` is gitignored. The AWQ weights at `/huggingface/hub/models--cyankiwi--MiniMax-M2.7-AWQ-4bit/` (~120 GB per node) can be removed with `huggingface-cli delete-cache --disable-tui`. Container images live in `docker image ls | grep vllm-node`.
