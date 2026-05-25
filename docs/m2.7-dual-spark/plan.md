# Plan — Dual-DGX-Spark vLLM migration

Reference [`spec.md`](spec.md) for goals/acceptance, [`networking.md`](networking.md) for ConnectX-7 setup, [`runbook.md`](runbook.md) for ops.

## Phases

### Phase 0 — Hardware & topology verification

- SSH key-auth head ↔ worker
- Drivers in 580.x band on both nodes (warn on mismatch, fail on 590.x)
- RoCE MTU 9000 on every IB interface, both nodes (`~/scripts/mtu-fixup.sh` is the persistence helper)
- RoCE ping between nodes on every configured IB interface
- HF cache present at `HF_HOME` on both nodes

Tooling: `./scripts/verify-cluster.sh` runs all of the above against `docker/.env`.

### Phase 1 — Excise the llama.cpp stack (one commit)

- Delete `docker/docker-compose.yml`, `config/minimax-m2-chat-template.jinja`, `config/Modelfile.minimax-m2`.
- Stub `scripts/{start,stop,status}.sh` with a migration banner that points at this doc set.
- Rewrite `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `NOTICE`.
- Rewrite `config/opencode.json.example` for a single vLLM provider at `localhost:8080` with M2.7 sampling defaults (temp 1.0).
- Add `pyproject.toml` (ruff + pytest config; `huggingface-hub` dep).
- Acceptance: `git grep -niE 'llama\.cpp|gguf|ollama|reap-40|minimax-m2\.1'` returns only intentional migration banners.

### Phase 2 — Submodule + recipe overlay + scripts + weights

- Add `third_party/spark-vllm-docker` as a git submodule, pinned to a specific upstream commit (recorded in `.gitmodules` + the commit message).
- Create `recipes/minimax-m2.7-awq.dgxs.yaml` — overlay of upstream `recipes/minimax-m2.7-awq.yaml`. Overrides: `-pp 2 -tp 1` (instead of upstream's `-tp 2`), `--port 8080`.
- Create `docker/.env.example`. Populate `CLUSTER_NODES`, `ETH_IF`, `IB_IF` (start with card 2 only), `MASTER_PORT`, `HF_HOME`, `CONTAINER_HF_TOKEN`, `CONTAINER_NCCL_*`.
- Rewrite `scripts/start.sh` (calls `run-recipe.sh --config docker/.env <recipe>`), `scripts/stop.sh`, `scripts/status.sh`.
- New `scripts/verify-cluster.sh`, `scripts/tail-logs.sh`.
- Build container image once: `( cd third_party/spark-vllm-docker && ./build-and-copy.sh -c )`.
- Pull AWQ weights to both nodes: `./third_party/spark-vllm-docker/hf-download.sh --config docker/.env cyankiwi/MiniMax-M2.7-AWQ-4bit -c gx10-db5e` (~ 120 GB; rsyncs head → worker over RoCE).

### Phase 3 — First boot + topology bench

- `./scripts/start.sh`. Watch `tail-logs.sh` for `NCCL INFO Using network IB`. If `Socket`, stop and fix RoCE.
- Smoke: `curl http://localhost:8080/v1/models` returns the AWQ alias; a 50-token completion returns sensible output.
- Bench PP=2 (current recipe) with `./scripts/benchmark.sh`. Then edit recipe to `-tp 2 -pp 1`, restart, re-bench. Lock in the winner. Record numbers in [`runbook.md`](runbook.md).
- Fallbacks documented in [`runbook.md`](runbook.md): `--enforce-eager` for CUDA-graph hangs, `IB_IF` widening for low throughput.

### Phase 4 — OpenCode + tests + docs

- `config/opencode.json.example` model alias matches the recipe.
- `./scripts/opencode-tool-regression.sh` passes — bash preferred over glob.
- `tests/test_vllm_health.py` (live, gated by `VLLM_TESTS_LIVE=1`): `/health`, `/v1/models`, simple completion, tool-call emission.
- `tests/test_opencode_style.py` (existing, retargeted to M2.7 alias and sampling).

### Phase 5 — Deferred (filed, not blocked on)

- NVFP4 once vLLM #30163, #32826, #42516 resolve.
- Expert parallel once stable on sm_120.
- SGLang MTP speculative decode on worker if Phase 3 throughput < target.
- Rebuild AWQ for M2.7 if `cyankiwi/MiniMax-M2.7-AWQ-4bit` quality is inadequate.
