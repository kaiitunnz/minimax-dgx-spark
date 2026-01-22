# Tracks Registry - minimax-inference

## Active Tracks

| Status | Track ID | Title | Phase | Created | Updated |
| ------ | -------- | ----- | ----- | ------- | ------- |

<!-- Tracks registered by /conductor:new-track -->

---

## Track Lifecycle

### Creating a Track

```
/conductor:new-track
```

Follow the interactive prompts to:
1. Define the track objective
2. Generate specification
3. Create phased implementation plan

### Track States

| State | Description |
|-------|-------------|
| `active` | Currently being worked on |
| `paused` | Temporarily on hold |
| `completed` | All phases finished |
| `archived` | No longer relevant |

### Managing Tracks

```
/conductor:manage          # List management options
/conductor:implement       # Work on active track
/conductor:status          # View current state
```

---

## Completed Tracks

| Track ID | Title | Completed | Notes |
| -------- | ----- | --------- | ----- |
| infra-setup_20260122 | Initial Infrastructure Setup | 2026-01-22 | llama.cpp + Ollama configured for DGX Spark, optimized for MoE models |

---

## Archived Tracks

| Track ID | Title | Archived | Reason |
| -------- | ----- | -------- | ------ |
