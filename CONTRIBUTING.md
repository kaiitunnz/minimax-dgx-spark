# Contributing to MiniMax Inference Server

## Ways to Contribute

- **Bug reports**: open an issue with reproduction steps, NCCL/IB log excerpts, and `./scripts/status.sh` output from both nodes.
- **Feature requests**: open an issue describing the use case and constraints (single-node, dual-node, batch profile).
- **Documentation**: improve README, runbook, networking guide, or in-line script comments.
- **Code contributions**: PRs for wrapper scripts, recipe overlays, tests, or upstream-submodule pin bumps.
- **Configuration improvements**: tuned `recipes/*.yaml`, NCCL env tweaks, GB10-specific workarounds.

## Before You Start

1. Search existing issues to avoid duplication.
2. For non-trivial changes, open an issue first to align on approach.
3. Test on the actual dual-Spark setup (or clearly note that you couldn't).

## Development Setup

```bash
git clone --recursive https://github.com/kaiitunnz/minimax-dgx-spark.git
cd minimax-dgx-spark

cp .env.example .env
$EDITOR .env                 # CLUSTER_NODES, ETH_IF, IB_IF, HF_TOKEN, ...

./scripts/verify-cluster.sh         # NCCL/IB/MTU/SSH preflight
./scripts/start.sh                  # Boots head + worker
curl -fsS http://localhost:8080/health
```

The submodule under `3rdparty/spark-vllm-docker/` ships the container image and SSH-based launcher; this repo owns the recipe overlay (`recipes/minimax-m2.7-awq.dgxs.yaml`), env, wrappers, tests, and docs.

## Code Style

### Shell Scripts

- Google Shell Style Guide; `shellcheck` clean.
- Always `set -euo pipefail`.
- Constants `UPPER_SNAKE_CASE` with `readonly`; variables `lower_snake_case`, always quoted.
- `die()` helper for fail-fast errors; `log()` for timestamped status lines.

### Python

- Python 3.11+; ruff config in `pyproject.toml` (`uv run ruff check .`, `uv run ruff format .`).
- Type hints on function signatures.
- Prefer `pathlib.Path`, f-strings, `httpx`.

### Documentation

- GitHub-flavored Markdown. Tables for env/flag references. Don't manually wrap paragraphs.
- Keep README focused on the happy path; deep ops content goes in `docs/m2.7-dual-spark/`.

## Commit Messages

Conventional-commit style, imperative subject:

```
<type>(<scope>): <description>

[optional body explaining the "why" if non-obvious]
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`.

**Scope examples:** `recipe`, `scripts`, `docker`, `tests`, `opencode`, `submodule`.

**Examples:**

```
feat(recipe): switch primary to PP=2 after dual-Spark bench
fix(scripts): pin NCCL_IB_GID_INDEX=3 to force RoCE v2
docs(networking): document MTU 9000 requirement on DAC link
chore(submodule): bump spark-vllm-docker to <commit-sha>
```

## Submodule Updates

`3rdparty/spark-vllm-docker/` is pinned to a specific upstream commit. To bump:

```bash
cd 3rdparty/spark-vllm-docker
git fetch && git checkout <new-commit>
cd ../..
git add 3rdparty/spark-vllm-docker
git commit -m "chore(submodule): bump spark-vllm-docker to <short-sha>"
```

Include a one-line note in the commit body explaining what upstream change motivated the bump.

## Recipe Overlay Convention

- One file per target deployment in `recipes/`: `<model>-<quant>.<suffix>.yaml`.
- Inherit from the upstream recipe; override only the fields specific to this hardware/setup (parallelism, port, model pin).
- Comment each override line with a one-line justification — future readers need to know why we diverged from upstream.

## Pull Request Process

1. Fork and branch:

   ```bash
   git checkout -b feat/your-change
   ```

2. Make focused commits. Update relevant docs in the same PR.

3. Test:
   - `shellcheck scripts/*.sh`
   - `uv run ruff check .`
   - `VLLM_TESTS_LIVE=1 pytest tests/test_vllm_health.py`
   - End-to-end OpenCode session if the change touches the inference path.

4. Open a PR with a clear title and body. Reference related issues; note any breaking changes; include benchmark numbers if you changed parallelism or sampling.

5. Address review feedback in additional commits (no force-push to a shared PR branch unless the reviewer asks).

## Configuration Contributions

When proposing a recipe or env change:

1. Document the use case (single-user coding, batched eval, etc.).
2. Include before/after benchmarks: decode tok/s at batch 1, TTFT at 1 K-token prompt, peak memory per node.
3. Note tradeoffs (latency vs throughput, quality vs speed).
4. Verify stability for at least one extended session.
5. Specify the exact hardware, driver, and vLLM commit you tested against.

## Bug Reports

Include:

- **Description**: actual vs expected behavior.
- **Reproduction**: minimal `curl` or OpenCode command that triggers it.
- **Environment**: GB10 driver version on both nodes (`nvidia-smi`), submodule commit hash, recipe file contents, `.env` with secrets redacted.
- **Logs**: `./scripts/tail-logs.sh` output around the failure, especially `NCCL_DEBUG=INFO` lines.
- **Topology**: confirm `Using network IB` (not `Socket`); confirm MTU 9000 on the IB link.

## Code of Conduct

- Be respectful and inclusive.
- Focus on constructive feedback.
- Give credit where due.

## License

By contributing, you agree your contributions are licensed under Apache License 2.0.
