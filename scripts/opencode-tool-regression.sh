#!/usr/bin/env bash
set -euo pipefail

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"
PROMPT='Use bash to list all Markdown files in the current directory.'

LOG_OUTPUT="$("$OPENCODE_BIN" run --print-logs "$PROMPT" 2>&1)"

if [ "${SHOW_LOGS:-0}" != "0" ]; then
  printf '%s\n' "$LOG_OUTPUT"
fi

if command -v rg >/dev/null 2>&1; then
  if ! printf '%s\n' "$LOG_OUTPUT" | rg -q 'permission permission=bash'; then
    echo "Expected bash permission evaluation in logs, but did not find it." >&2
    exit 1
  fi
  if printf '%s\n' "$LOG_OUTPUT" | rg -q 'permission permission=glob'; then
    echo "Unexpected glob permission evaluation in logs." >&2
    exit 1
  fi
else
  if ! printf '%s\n' "$LOG_OUTPUT" | grep -qE 'permission permission=bash'; then
    echo "Expected bash permission evaluation in logs, but did not find it." >&2
    exit 1
  fi
  if printf '%s\n' "$LOG_OUTPUT" | grep -qE 'permission permission=glob'; then
    echo "Unexpected glob permission evaluation in logs." >&2
    exit 1
  fi
fi

echo "OK: tool-calling regression check passed (bash used, glob not used)."
