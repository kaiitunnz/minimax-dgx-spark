# docker/

This directory holds the environment template and operator notes for the
vLLM cluster. The container image and SSH-based launcher live in the
`third_party/spark-vllm-docker` submodule; we drive it via our wrapper
scripts under `scripts/`.

## Files

- `.env.example` — copy to `.env`, edit, gitignored. Defines cluster topology,
  RoCE interfaces, HF token, and `CONTAINER_*` passthroughs.
- This README.

## Invocation cheatsheet

```bash
# One-time setup
cp docker/.env.example docker/.env
$EDITOR docker/.env

# Build the container image (head node + propagate to peers).
# Run from the submodule directory the first time.
( cd third_party/spark-vllm-docker && ./build-and-copy.sh -c )

# Boot the cluster with our recipe overlay.
./scripts/start.sh

# Other ops
./scripts/status.sh
./scripts/tail-logs.sh
./scripts/stop.sh
./scripts/verify-cluster.sh
```

`scripts/start.sh` invokes `third_party/spark-vllm-docker/run-recipe.sh
--config docker/.env recipes/minimax-m2.7-awq.dgxs.yaml`. The launcher
distributes container env (`CONTAINER_*` vars from `.env`) to both nodes
and orchestrates Ray + vLLM startup.
