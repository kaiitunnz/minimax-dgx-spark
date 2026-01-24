# Contributing to MiniMax Inference Server

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Ways to Contribute

- **Bug reports**: Open an issue describing the problem, including reproduction steps
- **Feature requests**: Propose new features or improvements via issues
- **Documentation**: Improve README, add guides, fix typos
- **Code contributions**: Submit pull requests for bug fixes or features
- **Configuration improvements**: Optimize settings for different hardware/use cases

## Before You Start

1. **Check existing issues**: Search for similar issues or feature requests
2. **Open an issue first**: For significant changes, discuss the approach before implementing
3. **Test on DGX Spark**: Ensure changes work on the target hardware (or note limitations)

## Development Setup

### Prerequisites

- NVIDIA DGX Spark (GB10 Grace Blackwell) or compatible ARM64 + NVIDIA GPU system
- Docker with NVIDIA Container Toolkit
- Ubuntu 24.04 (recommended)

### Setup

```bash
git clone https://github.com/your-username/minimax.git
cd minimax

# Download model (107GB)
huggingface-cli download mradermacher/MiniMax-M2.1-REAP-40-GGUF \
  --include 'MiniMax-M2.1-REAP-40.Q6_K.gguf' \
  --local-dir ./models

# Start server
./scripts/start.sh

# Run tests
curl http://localhost:8080/health
```

## Contribution Guidelines

### Code Style

**Shell Scripts:**

- Follow Google Shell Style Guide
- Use `shellcheck` for linting
- Always include `set -euo pipefail`
- Use `readonly` for constants
- Quote all variables

**Python (if added):**

- Use ruff for linting and formatting
- Type hints required
- Follow conventions in `conductor/code_styleguides/python.md`

**Documentation:**

- Use GitHub-flavored Markdown
- Keep line length reasonable (~80-100 chars)
- Include code examples where applicable

### Commit Messages

Use conventional commit format:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding/updating tests
- `chore`: Maintenance tasks

**Examples:**

```
feat(docker): add support for multi-GPU setups
fix(config): correct KV cache quantization flags
docs(readme): add troubleshooting for OOM errors
perf(llama): optimize batch size for 96K context
```

### Pull Request Process

1. **Fork the repository** and create a feature branch

   ```bash
   git checkout -b feat/your-feature-name
   ```

2. **Make your changes**
   - Write clear, focused commits
   - Include tests/verification steps
   - Update documentation

3. **Test thoroughly**
   - Verify server starts without errors
   - Test inference endpoints
   - Check memory usage is stable
   - Validate with Open Code (if applicable)

4. **Submit pull request**
   - Clear title describing the change
   - Reference related issues
   - Include testing steps
   - Note any breaking changes

5. **Address review feedback**
   - Respond to comments
   - Make requested changes
   - Re-test after modifications

### Pull Request Template

```markdown
## Description

Brief description of what this PR does.

## Motivation

Why is this change needed?

## Changes

- List key changes
- Include configuration updates
- Note any new dependencies

## Testing

Describe how you tested this:

- [ ] Server starts successfully
- [ ] Inference works correctly
- [ ] Memory usage is stable
- [ ] No performance regression

## Hardware

Tested on: [DGX Spark / Other ARM64 / x86_64]

## Checklist

- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] No secrets/PII in code
- [ ] Tested on target hardware
```

## Configuration Contributions

When proposing configuration changes:

1. **Document the use case**: What workload/scenario is this for?
2. **Include benchmarks**: Performance metrics before/after
3. **Note tradeoffs**: Memory vs speed, quality vs throughput, etc.
4. **Test stability**: Run for extended periods, check for memory leaks
5. **Specify hardware**: DGX Spark specs, GPU memory, etc.

### Example Configuration Change

```yaml
# Before (baseline)
- "-c"
- "131072"  # 128K context
- "-np"
- "4"      # 4 parallel slots
Performance: ~18 tok/s generation, ~54 tok/s prompt processing

# After (proposed)
- "-c"
- "98304"  # 96K context
- "-np"
- "2"      # 2 parallel slots
Performance: ~10 tok/s, 10GB VRAM
Tradeoff: Fewer concurrent requests, more context per request
Use case: Large codebase analysis with deep context
```

## Documentation Contributions

Good documentation is crucial for this project:

- **README updates**: Keep installation/usage sections current
- **Troubleshooting**: Add common issues and solutions
- **Configuration guides**: Document optimization strategies
- **Hardware compatibility**: Note tested platforms and limitations
- **Performance tuning**: Share benchmarks and best practices

## Hardware-Specific Notes

### DGX Spark (Primary Target)

- **Grace Blackwell GB10**: 128GB unified memory, 20 ARM64 cores
- **MoE models**: Use `-ngl 999` to offload all layers to GPU (unified memory handles full model)
- **Context limits**: Test up to 96K with 4 parallel slots
- **Memory monitoring**: Watch unified memory usage via `nvidia-smi`

### Other Platforms

If testing on other hardware, please note:

- CPU architecture (ARM64 / x86_64)
- GPU model and VRAM
- Total system memory
- Driver version
- Any required configuration changes

## Issue Reporting

### Bug Reports

Include:

- **Description**: What happened vs what you expected
- **Steps to reproduce**: Minimal example to trigger the bug
- **Environment**: Hardware, OS, Docker version, driver version
- **Logs**: Relevant error messages (`docker compose logs`)
- **Configuration**: Your `docker-compose.yml` (if modified)

### Feature Requests

Include:

- **Use case**: What problem does this solve?
- **Proposed solution**: How would this work?
- **Alternatives**: Other approaches you considered
- **Impact**: Who benefits from this feature?

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and improve
- Give credit where due

## Questions?

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For general questions and ideas
- **README**: Start here for setup and usage

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

Thank you for contributing to MiniMax Inference Server! 🚀
