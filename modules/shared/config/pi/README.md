# Personal Pi configuration

Imported by `homes/amunoz/home.nix`; settings and extensions are linked into
`~/.pi/agent/`. Run `/reload` in an **idle** session after changing them. Do not
reload or restart healthy sessions that are executing tools.

## Larger GPT context window

**GPT-5.6 Sol (872k)** is the default for new sessions. The model allowlist and
cycling list contain only Sol and **GPT-6 Astra (272k)**; GPT-5.5 is removed.
Existing sessions retain their model until `/reload` followed by
`/model openai-codex/gpt-5.6-sol`. Astra's larger limit was not verified.

On 2026-10-30, the account-authenticated Codex model catalog
(`https://chatgpt.com/backend-api/codex/models?client_version=0.146.0`) reported
`context_window: 272000` and `max_context_window: 872000` for `gpt-5.6-sol`.
A single direct Pi SDK request via the existing Codex OAuth credentials and SSE
successfully processed **300,052 input tokens**, returning `CONTEXT_OK` (7 output
tokens). The synthetic probe included no repository content or session history.
This verifies operation above 272k, not a full 872k boundary stress test.

The long-context pricing tier is retained from Pi's bundled catalog; larger
requests can consume more subscription quota. Automatic compaction stays enabled
with the existing settings (default threshold: 872000 - 16384 = 855616 tokens).
No other sessions are restarted or switched automatically.

Run the offline registration and compaction checks with:

```bash
PI_PACKAGE_DIR="$(dirname "$(readlink -f "$(command -v pi)")")/../lib/node_modules/pi-monorepo" \
  node --test modules/shared/config/pi/tests/*.test.mjs
```

## Reliable Codex compaction

`reliable-compaction.ts` works around Pi 0.87.1 summary failures seen on
2026-10-28. The default compactor inherits the conversation's `xhigh` reasoning.
Its summary options omit transport, while the SDK only sets the configured
transport on the ordinary agent loop. The Codex provider defaults summaries to
WebSocket and does not immediately fall back to SSE after stream start. This
produced repeated `WebSocket idle timeout after 300000ms` errors and prevented
oversized sessions from making progress.

The hook uses Pi's exported `compact` implementation with the **same model**,
SSE, medium reasoning, no automatic retries, and a ten-minute total deadline.
It preserves the retained-message boundary, previous summary, split-turn
summaries, file-operation metadata and usage. The raw transcript is never
rewritten. Ordinary task execution retains its configured model and reasoning.
Failed, empty, truncated, or cancelled summaries are not committed; provider
safety rejections are not retried through another model or transport.

This uses Pi's compaction API; rerun the regression suite when upgrading Pi and
remove the workaround when the upstream behavior is fixed. For the Nix package:

```bash
PI_PACKAGE_DIR="$(dirname "$(readlink -f "$(command -v pi)")")/../lib/node_modules/pi-monorepo" \
  node --test modules/shared/config/pi/tests/reliable-compaction.test.mjs
```

The tests use the installed SDK with a mock provider and make no network calls.
