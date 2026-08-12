# Hindsight on moby

`moby` hosts the shared Hindsight REST API. Pi is the only agent adapter. The
server uses a dedicated Codex OAuth login from the ChatGPT subscription for
memory extraction; normal Codex and Claude Code sessions are not integrated.

## Pinned server

- Hindsight: `0.8.6`
- Source revision: `08995e3013858e705fb4ca27c0ade3a286ef4750`
- API-only image: `ghcr.io/vectorize-io/hindsight-api:0.8.6@sha256:3db1536d84a14a10afbd08cc8f82bf4eec03c123d950705226c999bea14ca0f0`
- Endpoint: `http://100.94.5.85:8888` over Tailscale
- Extraction provider/model: `openai-codex` / `gpt-5.4-mini`
- MCP and the Control Plane are disabled.

The API bearer token is stored as `secrets/hindsight-api-token.age`. The system
copy is decrypted to `/run/agenix/hindsight-api-token`; Pi receives an owner-only
copy at `~/.config/hindsight/api-token`.

## State

The live database is `/var/lib/hindsight/pg0`. Never put that directory in
Syncthing. Model cache and temporary backup state are under
`/var/lib/hindsight/`.

Hindsight has a dedicated writable Codex auth home at
`~/.local/state/hindsight-codex`. To create or repair that login without touching
normal Codex auth:

```bash
install -d -m 0700 ~/.local/state/hindsight-codex
CODEX_HOME=~/.local/state/hindsight-codex codex login --device-auth
sudo systemctl restart podman-hindsight-api.service
```

A machine-loss recovery can repeat this login. The OAuth file is intentionally
not synchronized.

## Deploy

After committing the managed source, use the ordinary activation:

```bash
sudo nixos-rebuild switch --flake .#moby
```

While validating an uncommitted tree, force a path flake so new files are not
omitted:

```bash
sudo nixos-rebuild switch --flake "path:$PWD#moby"
```

Cold initialization may take more than a minute while local embedding and
reranking models download and PostgreSQL initializes.

## Backups

`hindsight-backup.timer` runs Sunday at 03:15 with up to 30 minutes of random
delay and catches up after downtime. It runs `hindsight-admin backup`, encrypts
the zip to both the personal and moby age recipients, removes the plaintext,
and writes the result under:

```text
~/.local/share/syncthing/hindsight-backups/moby/
```

The `hindsight-backups` folder is bidirectional on `moby`, `darwin001`,
`darwin002`, `oppy`, and `spirit`. Archives are immutable and separated by
source hostname. About six months of weekly archives are retained; Syncthing
also keeps staggered versions for six months.

Create an archive immediately:

```bash
sudo systemctl start hindsight-backup.service
journalctl -u hindsight-backup.service
```

Test an archive without touching the active database:

```bash
sudo hindsight-restore-test \
  ~/.local/share/syncthing/hindsight-backups/moby/hindsight-TIMESTAMP.zip.age \
  BANK_ID EXPECTED_SENTINEL
```

The test decrypts into a temporary isolated data path, starts a separate API on
`127.0.0.1:18888`, restores there, requires the expected sentinel to be
recallable, and removes the temporary container and data.

## Checks

```bash
curl -fsS http://100.94.5.85:8888/health
sudo systemctl status podman-hindsight-api.service hindsight-backup.timer
sudo podman inspect hindsight-api --format '{{.ImageDigest}} {{.State.Health.Status}}'
sudo podman logs --since 10m hindsight-api
```

Authenticated bank listing requires the owner-only token file. Do not put the
token directly on a command line or print it in logs.
