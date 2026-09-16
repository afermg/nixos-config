#!/usr/bin/env node
import { pathToFileURL } from "node:url";

function decodeJwtPayload(token) {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("OpenAI access credential is not a JWT");
  }
  return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
}

try {
  const modulePath = process.argv[2];
  if (!modulePath) throw new Error("Missing Pi SDK module path");

  const { ModelRuntime } = await import(pathToFileURL(modulePath).href);
  const runtime = await ModelRuntime.create({ allowModelNetwork: false });
  const result = await runtime.getAuth("openai-codex");
  const accessToken = result?.auth.apiKey;
  if (!accessToken) throw new Error("Pi OpenAI Codex login is unavailable");

  const payload = decodeJwtPayload(accessToken);
  const accountId = payload?.["https://api.openai.com/auth"]?.chatgpt_account_id;
  const expiresAt = payload?.exp;
  if (!accountId || typeof expiresAt !== "number") {
    throw new Error("Pi OpenAI Codex credential is missing required claims");
  }

  process.stdout.write(JSON.stringify({ accessToken, accountId, expiresAt }));
} catch {
  process.stderr.write(
    "Pi OpenAI Codex authentication is unavailable; run /login in Pi.\n",
  );
  process.exitCode = 1;
}
