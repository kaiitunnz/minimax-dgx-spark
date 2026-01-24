# AGENTS.md

Local guidance for Open Code sessions in this repo.

## Tool-calling behavior

- Treat any repo question (files, paths, contents, status) as tool-required; never answer from memory.
- Prefer a single tool call per step; avoid repeated retries unless the tool failed.
- If the user explicitly asks for bash, use `bash` (do not substitute `glob`).
- For unconditional file listing (no search pattern), use `bash` and return the tool output; do not answer from memory.
- If the user does not specify a tool, prefer `bash` for file listing and `read` for file content.
- When listing files, run at most one listing tool and return the list directly.
- For text search or “list files containing X”, use the `grep` tool (not `bash`).
- For `bash` tool calls, include only the required `command` parameter (omit optional fields).
- If `grep` output already includes file paths, do not run a second search; derive the file list directly.
- Never use `glob` unless the user explicitly requests it.
- If a request implies filesystem access, state, or changes, call the appropriate tool first; do not respond with analysis-only text.
- Use at most one tool call per turn; if more data is needed, ask a follow-up question.
- Do not call `todowrite` unless the user explicitly asks for a todo list.
- If the user names a specific file, limit searches to that file (do not repo-wide grep).
- When you decide to use a tool, call it; do not output the tool name as plain text.
- Never emit tool-call XML tags (`<invoke>`, `<parameter>`, `<minimax:tool_call>`) in final responses.
- Do not emit chain-of-thought or internal reasoning; provide only concise final answers (≤150 words).
- After tool use, respond with a short, direct answer and stop; avoid long summaries.
- Keep tool outputs minimal and do not echo raw tool schemas.
- For summaries, limit to ≤5 bullets and ≤80 words; focus only on the requested section.
- When summarizing a specific section in a large file, locate the section heading first, then read only ~120–200 lines around it (avoid full-file reads).

## Response style

- Be concise and action-oriented.
- Avoid speculative steps; ask clarifying questions only when required.
- For yes/no questions or “please proceed” requests, reply with a direct “Yes.” or “No.” first, then act.
- When a tool is needed, call it immediately without analysis or preamble; do not describe the call.
