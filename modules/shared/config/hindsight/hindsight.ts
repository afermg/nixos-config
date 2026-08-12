import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { homedir } from "node:os";

const DEFAULT_API_URL = "http://100.94.5.85:8888";
const REFLECT_MISSION =
  "Maintain durable technical knowledge about this Git repository across coding agents.";
const RETAIN_MISSION =
  "Extract project decisions, architecture, conventions, user preferences, and useful failed approaches. Preserve exact non-secret technical identifiers verbatim, including hashes, hostnames, paths, flags, commands, versions, and configuration values. Every explicit non-secret identifier and configuration value must appear verbatim in the extracted memory text, not only as an entity. Never extract or retain credentials, private keys, authentication tokens, or other secrets. Ignore transient command output and routine chatter.";
const MEMORY_BLOCK = /<hindsight_memories>[\s\S]*?<\/hindsight_memories>/gi;
const SECRET_PATTERNS = [
  /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----/,
  /\bBearer\s+[A-Za-z0-9._~+/=-]{12,}/i,
  /\b(?:sk-(?:proj-|or-v1-)?|ghp_|github_pat_|glpat-|xox[baprs]-|gsk_|hsk_|AIza|AKIA)[A-Za-z0-9_./+=-]{8,}/,
  /^\s*(?:export\s+)?[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|CREDENTIAL)[A-Z0-9_]*\s*=\s*['"]?[^\s'"]{8,}/im,
  /["'][^"']*(?:token|secret|password|passwd|api[_-]?key|private[_-]?key|credential)[^"']*["']\s*:\s*["'][^"']{8,}["']/i,
];

type Config = {
  api_url: string;
  token_file: string;
  state_dir: string;
  reflect_mission: string;
  retain_mission: string;
};
type Pending = { session: string; turn: string; prompt: string; secret: boolean };

function expandHome(path: string): string {
  return path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
}

export function loadConfig(): Config {
  const configPath = expandHome(
    process.env.HINDSIGHT_CONFIG ?? "~/.config/hindsight/config.json",
  );
  let data: Record<string, string> = {};
  try {
    data = JSON.parse(readFileSync(configPath, "utf8"));
  } catch {}
  return {
    api_url: (process.env.HINDSIGHT_API_URL ?? data.api_url ?? DEFAULT_API_URL).replace(/\/$/, ""),
    token_file: expandHome(
      process.env.HINDSIGHT_API_TOKEN_FILE ?? data.token_file ?? "~/.config/hindsight/api-token",
    ),
    state_dir: expandHome(
      process.env.HINDSIGHT_STATE_DIR ?? data.state_dir ?? "~/.local/state/hindsight",
    ),
    reflect_mission: data.reflect_mission ?? REFLECT_MISSION,
    retain_mission: data.retain_mission ?? RETAIN_MISSION,
  };
}

function ensurePrivateDir(path: string): void {
  mkdirSync(path, { recursive: true, mode: 0o700 });
  chmodSync(path, 0o700);
}

function atomicJson(path: string, value: unknown): void {
  ensurePrivateDir(dirname(path));
  const temporary = `${path}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(value)}\n`, { mode: 0o600 });
  chmodSync(temporary, 0o600);
  renameSync(temporary, path);
}

function readJson(path: string, fallback: any): any {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return fallback;
  }
}

export function containsSecret(text: string): boolean {
  return SECRET_PATTERNS.some((pattern) => pattern.test(text ?? ""));
}

function stripMemory(text: string): string {
  return (text ?? "").replace(MEMORY_BLOCK, "").trim();
}

export function resolveBankId(cwd: string): string {
  if (process.env.HINDSIGHT_BANK_ID) return process.env.HINDSIGHT_BANK_ID;
  let realCwd: string;
  try {
    realCwd = realpathSync(resolve(cwd));
  } catch {
    realCwd = resolve(cwd);
  }
  try {
    const common = execFileSync(
      "git",
      ["-C", realCwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
      { encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    const normalized = resolve(common).replaceAll("\\", "/");
    if (normalized.includes("/.git/modules/")) {
      const top = execFileSync("git", ["-C", realCwd, "rev-parse", "--show-toplevel"], {
        encoding: "utf8",
        timeout: 3000,
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      return basename(resolve(top));
    }
    return basename(dirname(normalized));
  } catch {
    return basename(realCwd) || "root";
  }
}

function token(config: Config): string {
  const value = readFileSync(config.token_file, "utf8").trim();
  if (!value || !containsSecret(value)) throw new Error("invalid token file");
  return value;
}

async function api(
  config: Config,
  method: string,
  path: string,
  body?: unknown,
  timeout = 8000,
): Promise<any> {
  const response = await fetch(`${config.api_url}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token(config)}`,
      "Content-Type": "application/json",
      "User-Agent": "hindsight-pi/1",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(timeout),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : {};
}

function bankPath(bank: string, suffix: string): string {
  return `/v1/default/banks/${encodeURIComponent(bank)}${suffix}`;
}

async function ensureMissions(config: Config, bank: string): Promise<void> {
  ensurePrivateDir(config.state_dir);
  const path = join(config.state_dir, "bank-missions-pi.json");
  const cache = readJson(path, {});
  const desired = {
    reflect_mission: config.reflect_mission,
    retain_mission: config.retain_mission,
  };
  if (JSON.stringify(cache[bank]) === JSON.stringify(desired)) return;
  await api(config, "PATCH", bankPath(bank, "/config"), { updates: desired });
  cache[bank] = desired;
  atomicJson(path, cache);
}

async function recall(config: Config, bank: string, prompt: string): Promise<string> {
  await ensureMissions(config, bank);
  const response = await api(
    config,
    "POST",
    bankPath(bank, "/memories/recall"),
    {
      query: prompt.slice(0, 800),
      max_tokens: 1024,
      budget: "mid",
      types: ["world", "experience"],
    },
    10000,
  );
  const lines = (response.results ?? [])
    .filter((result: any) => typeof result.text === "string" && result.text.trim())
    .map((result: any) => `- [${result.type ?? "memory"}] ${result.text.trim()}`);
  if (!lines.length) return "";
  const context = [
    "<hindsight_memories>",
    "Relevant memories from past conversations (prioritize recent when conflicting).",
    "Only use memories that are directly useful to continue this conversation; ignore the rest.",
    `Current time - ${new Date().toISOString()}`,
    "",
    ...lines,
    "</hindsight_memories>",
  ].join("\n");
  if (containsSecret(context)) throw new Error("recalled content matched secret policy");
  atomicJson(join(config.state_dir, "last-recall-pi.json"), {
    bank,
    context,
    saved_at: new Date().toISOString(),
  });
  return context;
}

function textFromAssistant(message: any): string {
  if (!message || message.role !== "assistant" || !Array.isArray(message.content)) return "";
  return message.content
    .filter((part: any) => part?.type === "text" && typeof part.text === "string")
    .map((part: any) => part.text)
    .join("\n")
    .trim();
}

async function retain(
  config: Config,
  bank: string,
  pending: Pending,
  answer: string,
): Promise<void> {
  const prompt = stripMemory(pending.prompt);
  answer = stripMemory(answer);
  const content = `User:\n${prompt}\n\nAssistant:\n${answer}`;
  if (!prompt || !answer || containsSecret(content)) throw new Error("turn matched secret policy");
  await ensureMissions(config, bank);
  const digest = createHash("sha256")
    .update(`pi\0${pending.session}\0${pending.turn}`)
    .digest("hex");
  await api(config, "POST", bankPath(bank, "/memories"), {
    items: [
      {
        content,
        document_id: `pi-${digest}`,
        context: "pi",
        metadata: { agent: "pi", project: bank },
        tags: ["agent:pi"],
      },
    ],
    async: true,
  });
}

function shortError(operation: string, error: unknown): void {
  const kind = error instanceof Error ? error.name : "Error";
  console.error(`[Hindsight] ${operation} unavailable (${kind})`);
}

export default function hindsight(pi: ExtensionAPI): void {
  const config = loadConfig();
  const pending = new Map<string, Pending>();

  pi.on("session_start", async () => {
    try {
      await api(config, "GET", "/health", undefined, 4000);
    } catch (error) {
      shortError("health check", error);
    }
  });

  pi.on("before_agent_start", async (event, ctx) => {
    const session =
      ctx.sessionManager.getSessionId?.() ??
      ctx.sessionManager.getSessionFile?.() ??
      "ephemeral";
    const leaf = ctx.sessionManager.getLeafId?.() ?? "";
    const turn = leaf || createHash("sha256").update(event.prompt).digest("hex");
    const secret = containsSecret(event.prompt);
    pending.set(session, { session, turn, prompt: secret ? "" : event.prompt, secret });
    if (secret) {
      console.error("[Hindsight] turn skipped by the local secret policy");
      return;
    }
    try {
      const bank = resolveBankId(ctx.cwd);
      const context = await recall(config, bank, event.prompt);
      if (context) return { systemPrompt: `${event.systemPrompt}\n\n${context}` };
    } catch (error) {
      shortError("recall", error);
    }
  });

  pi.on("agent_end", async (event, ctx) => {
    const session =
      ctx.sessionManager.getSessionId?.() ??
      ctx.sessionManager.getSessionFile?.() ??
      "ephemeral";
    const staged = pending.get(session);
    if (!staged) return;
    if (staged.secret) {
      pending.delete(session);
      return;
    }
    const assistants = event.messages.filter((message: any) => message?.role === "assistant");
    const answer = assistants.map(textFromAssistant).filter(Boolean).at(-1) ?? "";
    if (!answer) return;
    try {
      await retain(config, resolveBankId(ctx.cwd), staged, answer);
      pending.delete(session);
    } catch (error) {
      shortError("retain", error);
    }
  });
}
