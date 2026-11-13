import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { run } from "../hindsight-memory.mjs";

const root = mkdtempSync(join(tmpdir(), "hindsight-cli-test-"));
const originalConfig = process.env.HINDSIGHT_CONFIG;
const originalFetch = globalThis.fetch;
const config = join(root, "config.json");
const token = join(root, "token");
process.env.HINDSIGHT_CONFIG = config;
writeFileSync(token, "HS_FAKE_CLI_TOKEN_0123456789\n", { mode: 0o600 });
writeFileSync(config, JSON.stringify({ api_url: "http://127.0.0.1:9999", token_file: token }));
let calls = [];
let response = {};
let status = 200;
globalThis.fetch = async (url, options) => {
  calls.push({ url, ...options, body: options.body ? JSON.parse(options.body) : undefined });
  return new Response(JSON.stringify(response), { status });
};

try {
  response = { status: "healthy" };
  assert.equal((await run(["health"])).status, "healthy");
  assert.equal(calls.at(-1).headers.Authorization, undefined);

  response = { banks: [{ bank_id: "org", fact_count: 2, mission: "not needed" }] };
  assert.deepEqual(await run(["banks"]), { banks: [{ bank_id: "org", fact_count: 2 }] });
  assert.equal(calls.at(-1).headers.Authorization, "Bearer HS_FAKE_CLI_TOKEN_0123456789");
  assert.equal(calls.at(-1).redirect, "error");

  response = { results: [{ id: "memory-1", text: "Verified fact", score: 1 }] };
  const recalled = await run(["recall", "--bank", "space and / slash", "--query", "bridge"]);
  assert.equal(recalled.bank, "space and / slash");
  assert.deepEqual(recalled.results, [{ id: "memory-1", text: "Verified fact" }]);
  assert.match(calls.at(-1).url, /space%20and%20%2F%20slash\/memories\/recall$/);
  assert.equal(calls.at(-1).body.query, "bridge");

  response = { success: true };
  const saved = await run(["retain", "--bank", "org", "--document-id", "bridge-setup"], () => "Verified bridge setup.");
  assert.equal(saved.success, true);
  assert.equal(calls.at(-1).body.items[0].document_id, "bridge-setup");
  assert.equal(calls.at(-1).body.items[0].content, "Verified bridge setup.");
  assert.equal(calls.at(-1).body.async, false);

  const previousCalls = calls.length;
  await assert.rejects(run(["recall"]), /nonempty/);
  await assert.rejects(run(["recall", "--query", "Bearer HS_FAKE_SECRET_0123456789"]), /non-secret/);
  await assert.rejects(run(["retain"], () => "note"), /document-id/);
  await assert.rejects(run(["retain", "--document-id", "test"], () => ""), /1–16000/);
  await assert.rejects(run(["retain", "--document-id", "test"], () => "Bearer HS_FAKE_SECRET_0123456789"), /non-secret/);
  await assert.rejects(run(["retain", "--document-id", "test"], () => "x".repeat(16001)), /1–16000/);
  await assert.rejects(run(["unknown"]), /Expected/);
  assert.equal(calls.length, previousCalls);

  response = { results: [{ text: "Bearer HS_FAKE_RECALLED_0123456789" }] };
  await assert.rejects(run(["recall", "--query", "setup"]), /secret policy/);

  status = 401;
  response = { detail: "Private diagnostic that must not leak" };
  await assert.rejects(run(["banks"]), error => error.message === "Hindsight banks: HTTP 401");
  assert.equal((await run(["--help"])).usage.length, 4);
  console.log("Hindsight CLI tests passed");
} finally {
  globalThis.fetch = originalFetch;
  if (originalConfig === undefined) delete process.env.HINDSIGHT_CONFIG;
  else process.env.HINDSIGHT_CONFIG = originalConfig;
  rmSync(root, { recursive: true, force: true });
}
