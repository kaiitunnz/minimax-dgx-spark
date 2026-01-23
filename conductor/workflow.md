# Workflow - minimax-inference

## Development Workflow

### TDD Policy

**Strictness Level**: Flexible

- Tests required for utility scripts that perform complex operations
- Focus on working configurations over comprehensive test coverage
- Smoke tests to verify inference endpoints respond correctly
- Benchmark scripts to capture performance baselines

### What Requires Tests

| Component        | Test Requirement                              |
| ---------------- | --------------------------------------------- |
| Setup scripts    | Idempotency verification                      |
| Python utilities | Unit tests for non-trivial logic              |
| API endpoints    | Smoke test (responds, correct format)         |
| Configurations   | Validation that values are in expected ranges |

### What Doesn't Require Tests

- Docker compose files (manual verification)
- One-off scripts
- Documentation

---

## Git Workflow

### Commit Strategy

**Format**: Conventional Commits

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types**:
| Type | Description |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `chore` | Maintenance tasks, dependency updates |
| `refactor` | Code restructuring without behavior change |
| `test` | Adding or updating tests |
| `perf` | Performance improvements |

**Examples**:

```bash
feat(docker): add llama.cpp server container
fix(ollama): correct context window parameter
docs(setup): add model download instructions
chore(deps): update CUDA base image to 12.4
perf(inference): tune batch size for better throughput
```

### Branch Strategy

For a personal project, a simple approach:

- `main` - stable, working configurations
- Feature branches optional for larger changes

---

## Code Review

**Policy**: None - self-review, personal project

### Self-Review Checklist

Before committing:

- [ ] Scripts are idempotent (safe to re-run)
- [ ] Error messages are actionable
- [ ] Configuration values are documented
- [ ] No secrets or credentials in committed files

---

## Verification Checkpoints

**Policy**: After each phase completion - verify inference works before moving on

### Checkpoint Process

1. **Complete phase implementation**
2. **Run verification steps** (documented per phase)
3. **Record results** in track progress notes
4. **Proceed only if verification passes**

### Standard Verification Tests

#### Endpoint Health

```bash
curl http://localhost:8080/health
# Expected: {"status": "ok"}
```

#### Model Loading

```bash
curl http://localhost:8080/v1/models
# Expected: List includes minimax-m2
```

#### Inference Response

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "minimax-m2", "messages": [{"role": "user", "content": "Say hello"}]}'
# Expected: Valid JSON response with assistant message
```

#### Open Code Integration

```bash
opencode --model minimax-m2 "What is 2+2?"
# Expected: Correct response, no connection errors (ensure /health is 200 first)
```

---

## Task Lifecycle

### States

| State         | Description                                |
| ------------- | ------------------------------------------ |
| `pending`     | Not yet started                            |
| `in_progress` | Currently being worked on                  |
| `blocked`     | Waiting on external dependency or decision |
| `completed`   | Done and verified                          |
| `skipped`     | Intentionally not done (with rationale)    |

### Phase Completion Criteria

A phase is complete when:

1. All tasks in the phase are `completed` or `skipped`
2. Verification checkpoint passes
3. Progress documented in track file

---

## Troubleshooting Workflow

When something fails:

1. **Capture the error**: Full output, not just the message
2. **Check known issues**: Review track's troubleshooting section
3. **Isolate the layer**: Is it Docker, CUDA, model, or configuration?
4. **Document the fix**: Add to troubleshooting section for future reference

### Debug Commands

```bash
# Check GPU visibility
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi

# Check Ollama logs
journalctl -u ollama -f

# Check llama.cpp server logs
docker logs llama-server -f

# Test raw inference (bypass API)
curl -X POST http://localhost:8080/completion \
  -d '{"prompt": "Hello", "n_predict": 10}'
```

---

## Session Management

### Starting a Session

1. Verify hardware state: `nvidia-smi`
2. Start inference server: `docker compose up -d`
3. Verify endpoint: `curl localhost:8080/health`
4. Open conductor status: `/conductor:status`

### Ending a Session

1. Stop inference server: `docker compose down`
2. Commit any changes: `git status && git add -p && git commit`
3. Update track progress if applicable

### Recovering from Crashes

```bash
# Kill orphaned processes
pkill -f llama-server
pkill -f ollama

# Reset Docker state
docker compose down -v
docker system prune -f

# Restart fresh
docker compose up -d
```
