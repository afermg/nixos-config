# Atuin Threads with T3

Atuin Threads indexes native agent transcripts; it does not sync T3's database.
This profile installs Atuin 18.24.6 and an `atuin-mcp` launcher, with **conversation
capture and tool-payload capture off by default**. The separate `nixpkgs-atuin`
input leaves the fleet's main nixpkgs pin unchanged.

## Enable capture deliberately

The personal `homes/amunoz/home.nix` imports the module and enables the package.
In that home config (or a host-specific personal module), opt in with:

```nix
programs.atuinThreads = {
  enable = true;
  capture = true;
  captureTools = false;
};
```

Other Home Manager consumers can import
`inputs.nixos-config.homeModules.atuin-threads` and enable both
`programs.atuin.enable` and `programs.atuinThreads.enable`.

- Capture includes supported local agent conversations, **not just T3 sessions**.
- The existing personal Atuin config has encrypted cloud sync enabled. Captured
  conversations enter that same sync store. Turning capture off later does not
  erase previously captured or synced records.
- `captureTools = true` additionally retains tool arguments/results (including
  file contents). Atuin applies redaction, but it is not a guarantee that every
  secret is removed. Leave this off unless those payloads are appropriate to keep.
- No login, historical import, provider registration, or activation is performed
  by this PR. The existing agenix key and Atuin login are reused.
- Capture enables the Home Manager daemon on Linux and Darwin. Startup guards
  refuse to start without the encryption key; Linux retains the personal profile's
  existing agenix ordering, and Darwin waits for the key before starting.

Build/review, then activate the appropriate profile yourself, for example:

```sh
home-manager switch --flake '.#amunoz@oppy'
atuin --version
atuin config get threads.capture
atuin config get threads.capture_tools
systemctl --user status atuin-daemon  # Linux
```

For nix-darwin use the corresponding standalone Home Manager profile or system
rebuild; inspect the `org.nix-community.home.atuin-daemon` LaunchAgent with
`launchctl`. Do not run `atuin config enable threads` or `atuin threads enable`:
Home Manager owns `config.toml`, so change the Nix option instead. If `atuin resume`
offers to enable capture before you have opted in, decline that prompt.

Consumers such as Neusis must remove older `programs.atuin.package = lib.mkForce ...`
overrides: the module checks the **effective** package and rejects versions below
18.24. Also check `command -v atuin`: a separately managed `~/.local/bin/atuin`
can shadow Home Manager's executable. Update that link to the effective package.

## Register MCP with the provider T3 actually uses

Registration is a separate, explicit step on the **T3 server machine**, under the
same account and provider environment. It makes shell history and captured agent
history available to that provider, not only to one T3 thread. It is deliberately
not a Home Manager activation hook: agent configuration may contain auth and may
be a writable symlink into this repo.

For a provider's normal user configuration, choose only the command you need:

```sh
atuin mcp install pi
atuin mcp install claude
atuin mcp install codex
atuin mcp install opencode
```

The upstream installer registers `atuin mcp` and may replace an existing server
named `atuin`. Review any changes to tracked provider configuration. Pi must have
its native `pi mcp` command available; do not install a second MCP extension just
for this integration. Restart the T3 agent session after registration.

For manual registration, use the absolute, stable Home Manager profile path to
`atuin-mcp` (for example `/home/amunoz/.nix-profile/bin/atuin-mcp`) with **no args**.
It executes the selected Nix package's `atuin mcp`, without depending on the T3
service's PATH. Do not use `readlink -f` to register a transient Nix store path.
A generic stdio server entry is:

```json
{
  "mcpServers": {
    "atuin": {
      "command": "/home/amunoz/.nix-profile/bin/atuin-mcp",
      "args": []
    }
  }
}
```

This is an example for clients accepting `mcpServers`, **not a T3 settings file**;
Codex and OpenCode have different configuration schemas. The upstream installer
handles those formats. Confirm that the new T3 session exposes
`atuin_threads_list`, `atuin_threads_search`, and `atuin_threads_read`. Availability
inside a particular T3 provider has to be verified live; CLI registration alone
is not proof that its T3 instance loads the same configuration.

## Native transcript discovery and custom provider homes

For ordinary provider homes, Atuin discovers:

| Provider | Default transcript location |
| --- | --- |
| Claude Code | `~/.claude/projects` |
| Codex | `~/.codex/sessions` |
| Pi | `~/.pi/agent/sessions` |

T3's Pi provider preserves native Pi sessions. Atuin can discover those without
reading T3's database. T3 thread IDs and native agent session IDs are different.
Providers that do not persist supported transcripts cannot be captured this way.

Custom T3 provider homes/launch arguments are **not automatically inherited by
Atuin's background daemon**. Atuin supports `CLAUDE_CONFIG_DIR`, `CODEX_HOME`,
`PI_CODING_AGENT_DIR`, and `PI_CODING_AGENT_SESSION_DIR`; Pi's global `sessionDir`
is also supported. Match the daemon's environment to the relevant provider when
using custom locations. On Linux, for example:

```nix
systemd.user.services.atuin-daemon.Service.Environment = [
  "PI_CODING_AGENT_SESSION_DIR=/absolute/path/to/pi/sessions"
];
```

On Darwin use `launchd.agents.atuin-daemon.config.EnvironmentVariables`. Restart
the daemon after changing its environment. Use the same environment for manual
imports, MCP, and resuming as needed. One set of environment variables selects
one home per harness; this module does not aggregate arbitrary additional T3
provider homes or translate T3's `--session-dir` launch arguments.

## Smoke test and optional history import

After opting in, write a harmless unique phrase in a new supported agent session,
then check:

```sh
atuin threads list
atuin threads search 'your unique test phrase'
atuin resume
```

Capture follows ongoing work. To import older sessions deliberately, use
`atuin threads import --harness pi` (or `claude-code`, `codex`, `opencode`), or
`atuin threads import` for all supported agents. Imports can copy extensive
history into the synced store; they are never run automatically here.

On another enrolled machine, use the same Atuin account/encryption key and sync,
then search or resume. Resuming launches a native agent: it does **not** recreate
T3 PR links, worktree bindings, schedules, or previews. Repository files,
worktrees, credentials, and running processes are not transferred.

## Validation

```sh
nix eval --impure --json --expr \
  'import ./tests/atuin-threads.nix { flake = builtins.getFlake (toString ./.); }'
nix build --no-link '.#homeConfigurations."amunoz@oppy".config.programs.atuin.package'
launcher=$(nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in builtins.filter (p: f.lib.getName p == "atuin-mcp") f.homeConfigurations."amunoz@oppy".config.home.packages')
python tests/atuin-mcp.py "$launcher/bin/atuin-mcp"
```

The module tests cover disabled behavior, privacy defaults, explicit capture,
Linux/Darwin daemon configuration, key guards, the MCP launcher, and rejection of
an older package forced by a consuming flake. The MCP smoke test uses an isolated
temporary home, disables sync/capture, and checks the stdio handshake and thread
tool discovery without reading real history. Live T3 discovery and cross-machine
sync need the explicit opt-in/login steps above and are not automated tests.

References: [announcement](https://blog.atuin.sh/threads-agent-sessions/),
[Atuin Threads settings](https://github.com/atuinsh/atuin/blob/v18.24.6/crates/atuin-client/src/settings/threads.rs),
[MCP registration](https://github.com/atuinsh/atuin/blob/v18.24.6/crates/atuin-common/src/harnesstools/mcp.rs).
