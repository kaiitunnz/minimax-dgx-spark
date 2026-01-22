# Product Definition - minimax-inference

## Overview

**Project Name:** minimax-inference

**Description:** A local inference server for running Minimax AI models on DGX Spark hardware.

**Project Type:** Greenfield (new project)

---

## Problem Statement

Cloud inference APIs are expensive and have latency; local inference on DGX provides faster, cost-effective model serving. Setting up Minimax models for local development requires complex GPU configuration and dependencies. Additionally, this enables experimentation with Open Code harness/CLI for automation development on the DGX Spark platform.

### Core Pain Points

1. **Cost**: Cloud API pricing scales poorly for development/experimentation workloads
2. **Latency**: Network round-trips add overhead to inference requests
3. **Complexity**: GPU configuration, CUDA dependencies, and model loading require specialized knowledge
4. **Integration**: Connecting local LLMs to coding tools like Open Code requires specific endpoint configurations

---

## Target Users

**Primary User:** Personal use - developer building AI-powered automation and agents using Open Code tooling, experimenting with Minimax models for local development workflows on DGX Spark hardware.

### User Profile

- Senior AI engineer with deep technical knowledge
- Comfortable with GPU infrastructure, Docker, and CLI tooling
- Primary workflow involves Open Code for AI-assisted coding
- Values performance optimization and reproducible setups

---

## Key Goals

1. **Get Minimax models running locally with Ollama endpoints for Open Code integration**
   - Primary success metric: Open Code successfully connects and generates code completions
   - Endpoint format: OpenAI-compatible API at `localhost:11434/v1`

2. **Optimize inference performance for the DGX Spark GPU configuration**
   - Target: Maximize tokens/second while maintaining reasonable latency
   - Leverage DGX Spark's unified memory architecture and NVIDIA optimizations

3. **Create a reproducible setup that can be easily reset or reconfigured**
   - Docker-based deployment for isolation and portability
   - Version-controlled configuration files
   - Clear documentation for setup/teardown procedures

---

## Success Criteria

- [x] Minimax M2 (or M2.1) model loads and responds to inference requests ✓
- [x] Open Code connects to local endpoint and functions correctly ✓
- [x] Setup can be reproduced from scratch using documented steps ✓
- [x] Performance meets acceptable threshold for interactive coding use ✓ (~11 tok/s)

---

## Out of Scope

- Multi-user serving / production deployment
- Fine-tuning or training workflows
- Cloud deployment or remote access
- Web UI or monitoring dashboards
