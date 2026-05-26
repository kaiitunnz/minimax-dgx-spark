# docker/

Environment template for the vLLM cluster. The container image and SSH-based
launcher live in `third_party/spark-vllm-docker`; we drive them via the
wrapper scripts under `scripts/`.

- `.env.example` — copy to `.env` and edit. Gitignored. Defines cluster
  topology, RoCE interfaces, HF token, and `CONTAINER_*` passthroughs.

See the top-level [README](../README.md) for the Quick Start and
[`docs/m2.7-dual-spark/runbook.md`](../docs/m2.7-dual-spark/runbook.md) for
day-to-day ops.
