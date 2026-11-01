# Personal Pi configuration

Imported by `homes/amunoz/home.nix`; settings and extensions are linked into
`~/.pi/agent/`. Run `/reload` in an **idle** session after changing them. Do not
reload or restart healthy sessions that are executing tools.

## GPT-6.1 Sol default

**GPT-6.1 Sol (500k)** is the default for new sessions. The model allowlist and
cycling list contain only Sol 6.1 and **GPT-6 Astra (272k)**. GPT-5.5 and
GPT-5.6 Sol are removed. Existing sessions retain their model and cycling scope:
reload while idle, update `/scoped-models` to these two models, then select
`/model openai-codex/gpt-6.1-sol`. Do not interrupt active sessions.

OpenAI documents [500k context for Codex](https://developers.openai.com/codex/models)
and [1.05M for the API](https://developers.openai.com/api/docs/models/gpt-6.1-sol).
Use the Codex value here, rather than copying the previous model's 872k limit.
The account's catalog queried as Codex 0.146.0 still lists older models, but a
direct Pi SDK request for `gpt-6.1-sol` with existing OAuth credentials succeeded
(returned `OK`, 20 input tokens, 5 output tokens). This is an availability test,
not a full-context stress test or independent proof of backend model identity.

Cost metadata follows the published API rates and long-context tier. These are
API-equivalent estimates: the docs say subscription usage has no long-context
surcharge. Automatic compaction stays enabled; the default threshold is
500000 - 16384 = 483616 tokens. Existing histories above that need compaction.

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
