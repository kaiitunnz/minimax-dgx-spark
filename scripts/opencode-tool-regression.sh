#!/usr/bin/env bash
# Tool-routing regression: ensure OpenCode picks `bash` (not `glob`) for a
# simple file-listing prompt. Hits whichever provider/model the OpenCode
# config resolves; override with OPENCODE_MODEL to pin a specific endpoint.
set -euo pipefail

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"
PROMPT='Use bash to list all Markdown files in the current directory.'

# OPENCODE_MODEL takes the same value as `opencode run -m`, e.g.
#   vllm/minimax-m2.7
# Leaving it empty lets OpenCode pick from its config (project-level
# opencode.json plus the user's global config). Set it explicitly when this
# script is run from CI or when the user's global default points elsewhere.
OPENCODE_MODEL="${OPENCODE_MODEL:-}"

cmd=("$OPENCODE_BIN" run --print-logs)
[[ -n "$OPENCODE_MODEL" ]] && cmd+=(-m "$OPENCODE_MODEL")
cmd+=("$PROMPT")

LOG_OUTPUT="$("${cmd[@]}" 2>&1)"

if [ "${SHOW_LOGS:-0}" != "0" ]; then
  printf '%s\n' "$LOG_OUTPUT"
fi

# Surface model/provider actually used so a wrong-default failure is obvious.
if printf '%s\n' "$LOG_OUTPUT" | grep -qE 'providerID=|llm.provider='; then
  printf '%s\n' "$LOG_OUTPUT" | grep -m 1 -E 'providerID=[^ ]+ modelID=[^ ]+' >&2 || true
fi

if printf '%s\n' "$LOG_OUTPUT" | grep -qE 'permission permission=glob'; then
  echo "Unexpected glob permission evaluation in logs." >&2
  exit 1
fi
if ! printf '%s\n' "$LOG_OUTPUT" | grep -qE 'permission permission=bash'; then
  echo "Expected bash permission evaluation in logs, but did not find it." >&2
  echo "Tip: re-run with SHOW_LOGS=1 to see which model/provider OpenCode used." >&2
  exit 1
fi

echo "OK: tool-calling regression check passed (bash used, glob not used)."
