import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const require = createRequire(process.env.PI_PACKAGE_DIR
  ? join(process.env.PI_PACKAGE_DIR, "package.json") : import.meta.url);
const { createJiti } = require("jiti");
const jiti = createJiti(import.meta.url);
const { default: extension } = await jiti.import("../model-allowlist.ts");
const settings = JSON.parse(await readFile(new URL("../settings.json", import.meta.url), "utf8"));
let provider, config;
extension({ registerProvider(id, value) { provider = id; config = value; } });

// No credentials, network requests, or agent sessions are needed for these checks.
test("Sol is the default, Astra is retained, and GPT-5.5 is removed", () => {
  assert.equal(provider, "openai-codex");
  assert.equal(config.api, "openai-codex-responses");
  assert.equal(config.baseUrl, "https://chatgpt.com/backend-api");
  assert.equal(settings.defaultModel, "gpt-6.1-sol");
  assert.deepEqual(settings.enabledModels, ["openai-codex/gpt-6.1-sol", "openai-codex/gpt-6-astra"]);
  const models = new Map(config.models.map(m => [m.id, m]));
  assert.equal(models.size, config.models.length);
  assert.equal(models.size, 2);
  assert.equal(models.has("gpt-5.5"), false);
  assert.equal(models.has("gpt-5.6-sol"), false);
  assert.equal(models.get("gpt-6-astra").contextWindow, 272000);
  const sol = models.get("gpt-6.1-sol");
  assert.equal(sol.contextWindow, 500000);
  assert.equal(sol.maxTokens, 128000);
  assert.equal(sol.cost.input, 2);
  assert.equal(sol.cost.output, 10);
  assert.equal(sol.cost.cacheRead, 0.1);
  assert.equal(sol.cost.cacheWrite, 2.5);
  assert.equal(sol.thinkingLevelMap.max, "max");
  assert.deepEqual(sol.cost.tiers, [{
    inputTokensAbove: 272000, input: 4, output: 15, cacheRead: 0.2, cacheWrite: 5,
  }]);
  for (const id of models.keys()) assert.ok(settings.enabledModels.includes(`${provider}/${id}`));
  assert.notEqual(settings.compaction?.enabled, false);
});

test("installed Pi runtime accepts the provider configuration", async () => {
  const sdk = process.env.PI_PACKAGE_DIR
    ? pathToFileURL(join(process.env.PI_PACKAGE_DIR, "dist/index.js")).href
    : "@earendil-works/pi-coding-agent";
  const { ModelRuntime } = await import(sdk);
  const runtime = await ModelRuntime.create({
    credentials: { get: async () => undefined, set: async () => {}, delete: async () => {}, list: async () => [] },
    modelsPath: null, refreshOnCreate: false, allowModelNetwork: false,
  });
  runtime.registerProvider(provider, config);
  assert.equal(runtime.getError(), undefined);
  assert.equal(runtime.getModel(provider, "gpt-6.1-sol").contextWindow, 500000);
  assert.equal(runtime.getModel(provider, "gpt-5.5"), undefined);
  assert.equal(runtime.getModel(provider, "gpt-5.6-sol"), undefined);
});
