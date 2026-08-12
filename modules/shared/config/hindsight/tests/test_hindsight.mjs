import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import hindsight, { containsSecret, resolveBankId } from "../hindsight.ts";

function git(cwd, ...args) {
  return execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8" }).trim();
}

function initRepo(path) {
  mkdirSync(path, { recursive: true });
  git(path, "init", "-q");
  git(path, "config", "user.email", "test@example.invalid");
  git(path, "config", "user.name", "Hindsight Test");
  writeFileSync(join(path, "README"), "fixture\n");
  git(path, "add", "README");
  git(path, "commit", "-qm", "fixture");
}

const root = mkdtempSync(join(tmpdir(), "hindsight-pi-test-"));
const normal = join(root, "normal-repo");
initRepo(normal);
assert.equal(resolveBankId(normal), "normal-repo");

const worktree = join(root, "linked-worktree");
git(normal, "worktree", "add", "-q", "-b", "fixture-worktree", worktree);
assert.equal(resolveBankId(worktree), "normal-repo");

const symlink = join(root, "repo-symlink");
symlinkSync(normal, symlink);
assert.equal(resolveBankId(symlink), "normal-repo");

const spaced = join(root, "space and unicodé");
initRepo(spaced);
assert.equal(resolveBankId(spaced), "space and unicodé");

const child = join(root, "child-source");
const parent = join(root, "parent-repo");
initRepo(child);
initRepo(parent);
execFileSync(
  "git",
  ["-c", "protocol.file.allow=always", "-C", parent, "submodule", "add", "-q", child, "modules/my-submodule"],
  { encoding: "utf8" },
);
assert.equal(resolveBankId(join(parent, "modules/my-submodule")), "my-submodule");

const outside = join(root, "outside");
mkdirSync(outside);
assert.equal(resolveBankId(outside), "outside");
process.env.HINDSIGHT_BANK_ID = "explicit-fixture-bank";
assert.equal(resolveBankId(normal), "explicit-fixture-bank");
delete process.env.HINDSIGHT_BANK_ID;

const fixtures = JSON.parse(
  readFileSync(new URL("./secret-fixtures.json", import.meta.url), "utf8"),
);
for (const fixture of fixtures.secrets) {
  assert.equal(containsSecret(fixture.text), true, fixture.name);
}
for (const text of fixtures.benign) {
  assert.equal(containsSecret(text), false, text);
}

const configDir = join(root, "config");
const stateDir = join(root, "state");
mkdirSync(configDir, { recursive: true });
const tokenFile = join(configDir, "api-token");
writeFileSync(tokenFile, "hsk_test_only_abcdefghijklmnopqrstuvwxyz\n", { mode: 0o600 });
const configFile = join(configDir, "config.json");
writeFileSync(
  configFile,
  JSON.stringify({
    api_url: "http://127.0.0.1:9",
    token_file: tokenFile,
    state_dir: stateDir,
  }),
);
process.env.HINDSIGHT_CONFIG = configFile;

const handlers = new Map();
hindsight({ on(name, handler) { handlers.set(name, handler); } });
const sessionManager = {
  getSessionId: () => "fixture-session",
  getSessionFile: () => undefined,
  getLeafId: () => "fixture-turn",
};
const ctx = { cwd: normal, sessionManager };
let requests = 0;
globalThis.fetch = async () => {
  requests += 1;
  throw new Error("secret fixture must not reach fetch");
};
for (const fixture of fixtures.secrets) {
  await handlers.get("before_agent_start")(
    { prompt: fixture.text, systemPrompt: "system" },
    ctx,
  );
  await handlers.get("agent_end")(
    {
      messages: [
        { role: "assistant", content: [{ type: "text", text: "done" }] },
      ],
    },
    ctx,
  );
}
assert.equal(requests, 0, "secret fixtures caused an outbound request");

const responses = [
  {},
  { results: [] },
];
globalThis.fetch = async () => {
  requests += 1;
  const body = responses.shift() ?? {};
  return {
    ok: true,
    status: 200,
    text: async () => JSON.stringify(body),
  };
};
await handlers.get("before_agent_start")(
  { prompt: "Remember the build convention", systemPrompt: "system" },
  ctx,
);
const afterRecall = requests;
await handlers.get("agent_end")(
  {
    messages: [
      { role: "toolResult", content: [{ type: "text", text: "raw tool output" }] },
    ],
  },
  ctx,
);
assert.equal(requests, afterRecall, "tool-ending run retained raw tool output");

const changedMission = "Changed mission fixture";
writeFileSync(
  configFile,
  JSON.stringify({
    api_url: "http://127.0.0.1:9",
    token_file: tokenFile,
    state_dir: stateDir,
    reflect_mission: changedMission,
  }),
);
const changedHandlers = new Map();
hindsight({ on(name, handler) { changedHandlers.set(name, handler); } });
const calls = [];
globalThis.fetch = async (url, options) => {
  calls.push({ url: String(url), options });
  return { ok: true, status: 200, text: async () => JSON.stringify({ results: [] }) };
};
await changedHandlers.get("session_start")({}, ctx);
await changedHandlers.get("before_agent_start")(
  { prompt: "Check changed mission propagation", systemPrompt: "system" },
  ctx,
);
assert(calls.some((call) => call.url.endsWith("/health")), "session_start skipped health check");
assert(calls.every((call) => call.options.signal instanceof AbortSignal), "request timeout signal missing");
const patch = calls.find((call) => call.options.method === "PATCH");
assert(patch, "changed mission did not update an existing bank");
assert.equal(JSON.parse(patch.options.body).updates.reflect_mission, changedMission);

globalThis.fetch = async () => {
  throw new Error("fixture outage");
};
await changedHandlers.get("before_agent_start")(
  { prompt: "Fail open during an outage", systemPrompt: "system" },
  ctx,
);

console.log("Pi Hindsight resolver, mission, timeout, and secret-policy tests passed");
