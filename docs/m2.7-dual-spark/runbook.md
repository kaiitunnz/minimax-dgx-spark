# Runbook — Day-to-day operations

For setup details see [`networking.md`](networking.md); for goals/acceptance see [`spec.md`](spec.md).

## First-time setup

```bash
git clone --recursive https://github.com/kaiitunnz/minimax-dgx-spark.git
cd minimax-dgx-spark

# 1. Configure
cp docker/.env.example docker/.env
$EDITOR docker/.env                       # CLUSTER_NODES, IB_IF, HF_HOME, CONTAINER_HF_TOKEN

# 2. Preflight (driver, MTU, SSH, RoCE, HF cache)
./scripts/verify-cluster.sh

# 3. Build the container image with vLLM pinned, propagate to peer (~25-40 min cold).
./scripts/build-image.sh

# 4. Download AWQ weights to both nodes (~120 GB). Model name must precede -c
#    (eugr's positional parser is greedy).
export HF_HOME=/huggingface
./third_party/spark-vllm-docker/hf-download.sh \
  --config docker/.env \
  cyankiwi/MiniMax-M2.7-AWQ-4bit \
  -c <worker-host>

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
./scripts/benchmark.sh                # Quick sequential-curl smoke check
./scripts/benchmark-llama-benchy.sh   # llama-bench style pp/tg numbers
./scripts/stop.sh                     # Tear down both containers
```

OpenCode points at `http://localhost:8080/v1` via `config/opencode.json.example`; copy it to `~/.config/opencode/opencode.json`.

### Benchmark tools

- **`benchmark.sh`** issues a handful of `/v1/chat/completions` requests and reports `time_total` and `tokens/sec`. Use as the post-boot smoke check.
- **`benchmark-llama-benchy.sh`** wraps [`eugr/llama-benchy`](https://github.com/eugr/llama-benchy) (same author as our submodule). Emits `llama-bench`-style `pp/tg` statistics against an OpenAI-compatible endpoint — the same format the NVIDIA dev forum uses. Real text from Project Gutenberg, with TTFR reporting that bypasses the `reasoning_content` accounting issue affecting other serving benchmarks.

```bash
# Forum-comparable defaults: pp2048 / tg128 / depth=0 / 3 runs / concurrency=1
./scripts/benchmark-llama-benchy.sh

# Depth sweep — decode degradation under prefill context
DEPTH="0 4096 8192 32768" ./scripts/benchmark-llama-benchy.sh

# Concurrent decode throughput
CONCURRENCY=8 ./scripts/benchmark-llama-benchy.sh

# Raw JSON for parsing
FORMAT=json ./scripts/benchmark-llama-benchy.sh > bench.json
```

## Common failures

### NCCL logs `Using network Socket` instead of `Using network IB`

Symptom: decode throughput < 5 tok/s, or `NET/IB : No device found` followed by `Failed to initialize NET plugin IB` in the launcher output.
Cause: `IB_IF` in `docker/.env` contains netdev names (`enp1s0f0np0`) instead of HCA names (`rocep1s0f0`). `NCCL_IB_HCA` wants HCA names; netdev names yield "no device found" and silent socket fallback.
Fix: set `IB_IF` to the HCA-name list, e.g. `rocep1s0f0,roceP2p1s0f0,rocep1s0f1,roceP2p1s0f1` for the full 4-cable mesh. Re-run `./scripts/verify-cluster.sh`, then `./scripts/stop.sh && ./scripts/start.sh`.

### vLLM hangs at "Capturing CUDA graphs" on first boot

Symptom: head logs stop at CUDA-graph capture; GPU util 100 % indefinitely.
Cause: known sm_120 bug under TP and (sometimes) PP.
Fix: add `--enforce-eager` to the recipe `command:` block. Decode drops ~5–10 % but it boots reliably.

### `huggingface_hub.errors.GatedRepoError` during weight load

Cause: `CONTAINER_HF_TOKEN` in `docker/.env` is empty or invalid. SSH non-interactive sessions don't source `.bashrc`, so the token must be set explicitly in `.env`.
Fix: populate `CONTAINER_HF_TOKEN`.

### `Error: Model name is required` from `hf-download.sh`

Cause: `-c <host>` is greedy and consumes positional args.
Fix: pass the model name before `-c <host>`. Example: `./hf-download.sh --config docker/.env cyankiwi/MiniMax-M2.7-AWQ-4bit -c <worker-host>`.

### Decode throughput unexpectedly low

Diagnostic order:
1. `NCCL_DEBUG=INFO` showing `Using network IB`? If not, fix RoCE first.
2. MTU 9000 on every IB port? Re-run `./scripts/verify-cluster.sh`.
3. Driver 590.x? Downgrade to 580.x — see [`networking.md`](networking.md).
4. Try TP=2 vs PP=2 (edit recipe `command:`). If PP wins, NCCL is in TCP fallback regardless of what the logs say.

### Container starts but `/v1/models` returns 503 or hangs

Cause: weights still loading; `--load-format fastsafetensors` keeps the worker responsive but `/v1/models` blocks until ready.
Fix: wait. `tail-logs.sh` shows progress. Hard ceiling on first boot is ~10 min; if > 15 min, suspect NVMe contention.

## Recipe and submodule maintenance

Bump the submodule:

```bash
cd third_party/spark-vllm-docker
git fetch && git checkout <new-commit>
cd ../.. && git add third_party/spark-vllm-docker
git commit -m "chore(submodule): bump spark-vllm-docker to <short-sha>"
```

Diff the overlay against upstream after each bump and re-apply the local overrides (TP=2, port 8080, flashinfer attention) if upstream changed defaults:

```bash
diff recipes/minimax-m2.7-awq.dgxs.yaml \
     third_party/spark-vllm-docker/recipes/minimax-m2.7-awq.yaml
```

## Benchmarks

All numbers are single-stream decode at batch 1, NCCL on `NET/IB` (RDMA via DMA-BUF on GB10), image pinned to vLLM `v0.21.1rc0`.

### Topology — TP vs PP

| Config | Cold | Warm sustained |
| --- | --- | --- |
| **TP=2, PP=1** (default) | 2.37 tok/s | ~22 tok/s |
| PP=2, TP=1 | 1.33 tok/s | ~21 tok/s |

TP=2 wins by a small margin on a 10B-active MoE at batch 1 with real IB RDMA — the per-token all-reduce is cheap while PP's pipeline bubble is not.

### Quant / backend

| Recipe | Attention | MoE backend | Warm decode |
| --- | --- | --- | --- |
| **`minimax-m2.7-awq.dgxs.yaml`** (default) | `flashinfer` | (auto, MARLIN) | **23.7 tok/s** |
| `minimax-m2.7-nvfp4.dgxs.yaml` | `flashinfer` | `flashinfer_cutlass` | 17.8 tok/s |

The NVFP4 recipe stays in-repo because NVFP4 is the future Blackwell-tuned path. Run it explicitly:

```bash
RECIPE=recipes/minimax-m2.7-nvfp4.dgxs.yaml ./scripts/start.sh
```

### `llama-benchy` (forum-comparable)

`./scripts/benchmark-llama-benchy.sh` defaults: pp2048, tg128, depth=0, runs=3, concurrency=1.

| Recipe | pp2048 (tok/s) | tg128 (tok/s) | TTFR (ms) |
| --- | --- | --- | --- |
| AWQ (default) | 1150 ± 24 | 23.45 ± 0.07 | 1970 ± 38 |

The NVIDIA dev forum (thread 366324) reports higher `tg128` for the same model class on similar hardware. The gap is real (not a methodology artifact); likely contributors to investigate: driver/firmware version, vLLM build SHA, NCCL collective settings, per-cable MTU across the 4-fabric mesh.

## Cleanup

`docker/.env` is gitignored. The AWQ weights at `/huggingface/hub/models--cyankiwi--MiniMax-M2.7-AWQ-4bit/` (~120 GB per node) can be removed with `huggingface-cli delete-cache --disable-tui`. Container images live in `docker image ls | grep vllm-node`.
