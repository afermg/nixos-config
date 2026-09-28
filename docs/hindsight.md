# Hindsight on ix

`ix` hosts the shared Hindsight REST API over Tailscale. Pi is the only agent
adapter. The first ix deployment restores the last moby backup so recall keeps
working while moby is off. New retention/extraction workers stay disabled until
ix has its own dedicated Codex OAuth login; do not copy moby's live OAuth state.

## Pinned server

- Hindsight: `0.8.6`
- Source revision: `08995e3013858e705fb4ca27c0ade3a286ef4750`
- API-only image: `ghcr.io/vectorize-io/hindsight-api:0.8.6@sha256:3db1536d84a14a10afbd08cc8f82bf4eec03c123d950705226c999bea14ca0f0`
- Endpoint on ix: `http://127.0.0.1:8888` locally and `http://ix.tail5e510f.ts.net:8888` over Tailscale
- Extraction provider/model: disabled on ix until a dedicated login is created
- MCP and the Control Plane are disabled.

The API bearer token is stored as `secrets/hindsight-api-token.age` for hosts
that use agenix. ix keeps an owner-only runtime copy at
`~/.config/hindsight/api-token`; the token is not embedded in the Nix store.

## State

The live database is `/var/lib/hindsight/pg0`. Never put that directory in
Syncthing. Model cache and temporary backup state are under `/var/lib/hindsight/`.

When extraction is enabled later, use a dedicated writable Codex auth home at
`~/.local/state/hindsight-codex` and keep it out of synchronization:

```bash
install -d -m 0700 ~/.local/state/hindsight-codex
CODEX_HOME=~/.local/state/hindsight-codex codex login --device-auth
sudo systemctl restart podman-hindsight-api.service
```

## Deploy

After committing the managed source, use the ordinary ix activation:

```bash
sudo nixos-rebuild switch --flake .#ix
```

While validating an uncommitted tree on ix, force a path flake so new files are
not omitted:

```bash
sudo nixos-rebuild switch --flake "path:$PWD#ix"
```

Cold initialization may take more than a minute while local embedding and
reranking models download and PostgreSQL initializes.

## Backups

`hindsight-backup.timer` runs Sunday at 03:15 with up to 30 minutes of random
delay and catches up after downtime. It runs `hindsight-admin backup`, encrypts
the zip to both the personal and ix host age recipients, removes the plaintext,
and writes new ix archives under:

```text
~/.local/share/syncthing/hindsight-backups/ix/
```

Historical moby archives copied during migration remain under:

```text
~/.local/share/syncthing/hindsight-backups/moby/
```

Create an archive immediately:

```bash
sudo systemctl start hindsight-backup.service
journalctl -u hindsight-backup.service
```

Test a new ix archive without touching the active database:

```bash
sudo hindsight-restore-test \
  ~/.local/share/syncthing/hindsight-backups/ix/hindsight-TIMESTAMP.zip.age \
  BANK_ID EXPECTED_SENTINEL
```

The test decrypts with ix's host key into a temporary isolated data path, starts
a separate API on `127.0.0.1:18888`, restores there, requires the expected
sentinel to be recallable, and removes the temporary container and data. Older
moby archives were encrypted for moby/personal recipients and need a personal
key for one-time migration restores.

## Checks

```bash
curl -fsS http://127.0.0.1:8888/health
curl -fsS http://ix.tail5e510f.ts.net:8888/health
sudo systemctl status podman-hindsight-api.service hindsight-backup.timer
sudo podman inspect hindsight-api --format '{{.ImageDigest}} {{.State.Health.Status}}'
sudo podman logs --since 10m hindsight-api
```

Authenticated bank listing requires the owner-only token file. Do not put the
token directly on a command line or print it in logs.
