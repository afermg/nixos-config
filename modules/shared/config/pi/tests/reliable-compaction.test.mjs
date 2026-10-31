import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";
import { test } from "node:test";

// Use the installed Pi's SDK so these tests also catch API drift on upgrades.
// On Nix: PI_PACKAGE_DIR="$(dirname "$(readlink -f "$(command -v pi)")")/../lib/node_modules/pi-monorepo" node --test ...
const require = createRequire(process.env.PI_PACKAGE_DIR
  ? join(process.env.PI_PACKAGE_DIR, "package.json") : import.meta.url);
const { createJiti } = require("jiti");
const jiti = createJiti(import.meta.url, {
  alias: { "@earendil-works/pi-coding-agent": process.env.PI_PACKAGE_DIR
    ? join(process.env.PI_PACKAGE_DIR, "dist/index.js")
    : import.meta.resolve("@earendil-works/pi-coding-agent") },
});
const { default: extension } = await jiti.import("../reliable-compaction.ts");

function fixture(overrides = {}) {
  let handler;
  extension({ on(name, fn) { assert.equal(name, "session_before_compact"); handler = fn; } });
  const controller = new AbortController();
  const calls = [], notices = [];
  const usage = { input: 100, output: 30, cacheRead: 0, cacheWrite: 0, totalTokens: 130,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
  const model = { id: "gpt-6-astra", provider: "openai-codex", api: "openai-codex-responses", reasoning: true, maxTokens: 128000 };
  const event = {
    preparation: {
      firstKeptEntryId: "keep-this", tokensBefore: 260000,
      previousSummary: "Keep the existing decisions and unfinished tasks.",
      messagesToSummarize: [{ role: "user", content: "Fix the pending bug; do not deploy.", timestamp: 1 }],
      turnPrefixMessages: [], isSplitTurn: false,
      fileOps: { read: new Set(["read.ts"]), written: new Set(["new.ts"]), edited: new Set() },
      settings: { enabled: true, reserveTokens: 16384, keepRecentTokens: 20000 },
    },
    branchEntries: [], signal: controller.signal, customInstructions: "Preserve approval limits",
  };
  const ctx = {
    model, ui: { notify(text, level) { notices.push({ text, level }); } },
    modelRegistry: { async streamSimple(requestModel, context, options) {
      calls.push({ model: requestModel, context, options });
      if (overrides.reject) throw new Error(overrides.reject);
      return { async result() { return { role: "assistant", content: [{ type: "text", text: "## Goal\nFix the bug, without deploying." }], stopReason: "stop", usage, ...overrides.response }; } };
    } },
  };
  return { event, ctx, calls, notices, controller, usage, run: () => handler(event, ctx) };
}

test("SSE/medium summaries retain the current model, boundaries, instructions, usage and files", async () => {
  const f = fixture(); const before = structuredClone(f.event.preparation);
  const result = await f.run();
  assert.equal(f.calls.length, 1);
  const { options, context, model } = f.calls[0];
  assert.equal(model, f.ctx.model);
  assert.equal(options.transport, "sse"); assert.equal(options.reasoning, "medium");
  assert.equal(options.maxRetries, 0); assert.equal(options.cacheRetention, "none");
  assert.equal(options.timeoutMs, 300000); assert.ok(options.sessionId);
  assert.match(JSON.stringify(context), /existing decisions/); assert.match(JSON.stringify(context), /approval limits/);
  assert.equal(result.compaction.firstKeptEntryId, "keep-this");
  assert.equal(result.compaction.tokensBefore, 260000);
  assert.deepEqual(result.compaction.usage, f.usage);
  assert.deepEqual(result.compaction.details, { readFiles: ["read.ts"], modifiedFiles: ["new.ts"], reliableCompaction: 1 });
  assert.deepEqual(f.event.preparation, before);
});

test("split turns keep both summaries and cumulative file metadata", async () => {
  const f = fixture();
  f.event.preparation.isSplitTurn = true;
  f.event.preparation.turnPrefixMessages = [{ role: "user", content: "Next stage", timestamp: 2 }];
  f.event.branchEntries = [{ type: "compaction", fromHook: true, details: {
    reliableCompaction: 1, readFiles: ["previous.ts"], modifiedFiles: ["old-change.ts"],
  } }];
  const result = await f.run();
  assert.equal(f.calls.length, 2); assert.match(result.compaction.summary, /Turn Context/);
  assert.deepEqual(result.compaction.details.readFiles, ["previous.ts", "read.ts"]);
  assert.deepEqual(result.compaction.details.modifiedFiles, ["new.ts", "old-change.ts"]);
  assert.equal(result.compaction.usage.totalTokens, 260);
});

for (const [name, overrides] of [
  ["transport error", { response: { stopReason: "error", errorMessage: "WebSocket idle timeout" } }],
  ["provider safety rejection", { response: { stopReason: "error", errorMessage: "Content flagged for possible biological risk" } }],
  ["token cap", { response: { stopReason: "length" } }],
  ["empty result", { response: { content: [] } }],
  ["tool call", { response: { content: [{ type: "toolCall", name: "bash", arguments: {} }] } }],
  ["thrown exception", { reject: "Network failure" }],
]) test(`${name} cancels without persisting or falling back/retrying`, async () => {
  const f = fixture(overrides); assert.deepEqual(await f.run(), { cancel: true });
  assert.equal(f.calls.length, 1); assert.equal(f.notices.at(-1).level, "error");
});

test("cancellation is respected even if a provider returns text", async () => {
  const f = fixture(); f.controller.abort();
  assert.deepEqual(await f.run(), { cancel: true });
  assert.equal(f.notices.filter((n) => n.level === "error").length, 0);
});

test("unrelated providers keep default compaction", async () => {
  const f = fixture(); f.ctx.model = { ...f.ctx.model, provider: "other" };
  assert.equal(await f.run(), undefined); assert.equal(f.calls.length, 0);
});
