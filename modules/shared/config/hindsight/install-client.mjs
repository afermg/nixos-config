import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig } from "./hindsight.ts";

const home = homedir();
const source = dirname(fileURLToPath(import.meta.url));
const stamp = new Date().toISOString().replaceAll(":", "-");
const backupRoot = join(home, ".local/state/hindsight/client-install-backups", stamp);
const changed = [];
const skipped = [];

function install(relative, content, mode = 0o600) {
  const target = join(home, relative);
  if (existsSync(target) && readFileSync(target, "utf8") === content) return;
  // Out-of-store symlinks point into a live repository checkout; never edit it here.
  if (existsSync(target) && lstatSync(target).isSymbolicLink() && !realpathSync(target).startsWith("/nix/store/")) {
    skipped.push(relative);
    return;
  }
  mkdirSync(dirname(target), { recursive: true, mode: 0o700 });
  if (existsSync(target)) {
    const backup = join(backupRoot, relative);
    mkdirSync(dirname(backup), { recursive: true, mode: 0o700 });
    writeFileSync(backup, readFileSync(target), { mode: 0o600 });
  }
  const temporary = `${target}.${process.pid}.tmp`;
  writeFileSync(temporary, content, { mode });
  chmodSync(temporary, mode);
  renameSync(temporary, target);
  changed.push(relative);
}

for (const relative of [".config/hindsight", ".local/state/hindsight", ".local/share/hindsight-client"]) {
  const directory = join(home, relative);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  if (lstatSync(directory).isSymbolicLink()) throw new Error(`Refusing symlink directory ${relative}`);
  chmodSync(directory, 0o700);
}

const configPath = join(home, ".config/hindsight/config.json");
const previousConfig = existsSync(configPath) ? JSON.parse(readFileSync(configPath, "utf8")) : {};
const config = {
  ...loadConfig(),
  ...previousConfig,
  api_url: "http://oppy.tail27b080.ts.net:8888",
  token_file: join(home, ".config/hindsight/api-token"),
  state_dir: join(home, ".local/state/hindsight"),
};
install(".config/hindsight/config.json", `${JSON.stringify(config)}\n`);
for (const file of ["hindsight.ts", "hindsight-memory.mjs"]) {
  install(`.local/share/hindsight-client/${file}`, readFileSync(join(source, file), "utf8"));
}
install(".local/bin/hindsight-memory", '#!/bin/sh\nexec node "$HOME/.local/share/hindsight-client/hindsight-memory.mjs" "$@"\n', 0o700);
install(".pi/agent/extensions/hindsight.ts", readFileSync(join(source, "hindsight.ts"), "utf8"));

const guidance = readFileSync(join(source, "../codex/AGENTS.md"), "utf8");
const marker = "## Shared Hindsight memory";
const section = guidance.slice(guidance.indexOf(marker)).trim();
if (!section.startsWith(marker)) throw new Error("Missing shared memory guidance");
function withSection(relative, title) {
  const path = join(home, relative);
  let text = existsSync(path) ? readFileSync(path, "utf8") : `# ${title} — user-wide instructions\n`;
  if (text.includes(marker)) {
    const start = text.indexOf(marker);
    const next = text.indexOf("\n## ", start + marker.length);
    text = text.slice(0, start) + section + "\n" + (next < 0 ? "" : text.slice(next));
  } else {
    text = `${text.trimEnd()}\n\n${section}\n`;
  }
  install(relative, text);
}
withSection(".codex/AGENTS.md", "Codex");
withSection(".claude/CLAUDE.md", "Claude");
console.log(JSON.stringify({ changed, skipped, backup_directory: backupRoot, api_url: config.api_url }));
