# Hindsight on Oppy

Oppy hosts the shared Hindsight API and database. **ix must not run a Hindsight
server, model worker, or backup timer**; its email and Home Assistant services
are unchanged. Pi clients use `http://oppy.tail5e510f.ts.net:8888` over Tailscale.
MCP and the Control Plane are disabled.

## Configuration

- Server: `modules/shared/config/hindsight/server.nix` and `server.sh`.
- Opt-in: `services.hindsightServer.enable = true` only in `homeModules.amunoz-oppy`.
- Runtime: rootless Podman, managed by `systemctl --user`; user lingering is required.
- Image: `ghcr.io/vectorize-io/hindsight-api:0.8.6@sha256:3db1536d84a14a10afbd08cc8f82bf4eec03c123d950705226c999bea14ca0f0`.
- Extraction: dedicated Codex OAuth, `gpt-6-astra`, low reasoning. This model was
  verified with the account; `gpt-5.4-mini` and `gpt-5.5` were rejected by it.
- Embeddings: local CPU `BAAI/bge-small-en-v1.5` (384 dimensions), matching the
  original moby database. Codex is **not** used for embeddings.
- Reranker: RRF. Retention worker enabled, two slots. Automatic consolidation disabled.
- Limits: four CPUs, 8 GiB RAM, 2 GiB shared memory, two embedding threads.
  PostgreSQL's restored-data queries exceeded Podman's default 64 MiB `/dev/shm`;
  do not remove the explicit shared-memory allocation.
- Listeners: loopback and Oppy's Tailscale IPv4 only, not public/LAN interfaces.
- Authentication: `secrets/hindsight-api-token.age`, decrypted to the owner-only
  `~/.config/hindsight/api-token`. The token is written into a private runtime
  environment file, never embedded in the Nix store or command arguments.

## State and login

Live state is under `~/.local/share/hindsight/` on Oppy:

- `pg0/`: database; never synchronize this live directory.
- `cache/`: local model cache.
- `staging/`: temporary backup export, deleted after encryption.
- `backups/`: encrypted snapshots.
- `migration/`: preserved encrypted source backup.

The dedicated writable OAuth profile is `~/.local/state/hindsight-codex`.
For a new login, run **on Oppy**:

```bash
install -d -m 0700 ~/.local/state/hindsight-codex
CODEX_HOME="$HOME/.local/state/hindsight-codex" codex login --device-auth
systemctl --user restart hindsight-api.service
```

Do not clone normal Pi/Codex credentials or run two refreshing clients against
copies of the same OAuth state. During this migration the newly created,
previously unused dedicated ix login was transferred securely; ix's live auth
file was removed and its Hindsight units masked before Oppy used it.

## Deploy and operate

Normal complete profile activation, after reviewing unrelated pending changes:

```bash
home-manager switch --flake .#amunoz@oppy
```

For the initial migration, only the evaluated Hindsight Home Manager units,
client configuration, and extension were installed. Their store paths have GC
roots under `~/.local/state/hindsight/client-install/`. No full system/profile
switch was performed, avoiding activation of unrelated pending edits.

```bash
systemctl --user status hindsight-api.service hindsight-backup.timer
curl -fsS http://127.0.0.1:8888/health
curl -fsS http://oppy.tail5e510f.ts.net:8888/health
podman stats --no-stream hindsight-api
```

The public health endpoint does not require credentials. Bank/memory endpoints
must return HTTP 401 without the bearer token. Read the token from its file in
an HTTP client; do not paste it into shell commands or logs. Run `/reload` in
existing Pi sessions after installing/updating the client.

## ix retirement

`machines/ix/default.nix` no longer imports `hindsight.nix`. The old ix server
module remains unimported for historical reference. `homes/ix/hindsight.nix` is
only a lightweight Pi client pointing at Oppy.

The running ix generation still contains the former server. Its units are
stopped and persistently masked with `/dev/null` links under
`/etc/systemd/system.control/`:

- `podman-hindsight-api.service`
- `hindsight-backup.service`
- `hindsight-backup.timer`

This higher-priority unit path was necessary because ix's generated
`/etc/systemd/system` is read-only; ordinary `systemctl mask --runtime` did not
override it. A later ix rebuild should use the updated source (without the
server import). Do not unmask the old generation. Existing encrypted archives
on ix were preserved; no database or model computation runs there.

## Backups and restoration

`hindsight-backup.timer` runs Sunday at 03:15 with up to 30 minutes of jitter and
catches up after downtime. It exports through `hindsight-admin`, encrypts to the
personal SSH age recipient, and deletes the plaintext. Snapshots are currently
**local to Oppy**; this service does not arrange off-host replication or prune
existing archives.

```bash
systemctl --user start hindsight-backup.service
journalctl --user -u hindsight-backup.service
```

Restoration is destructive to the destination database. First verify the
archive, record current counts, and take a backup. Pause the worker with a
service drop-in setting `Environment=HINDSIGHT_WORKER_ENABLED=false`, then
restart. Decrypt into a private temporary directory and place the archive at
`~/.local/share/hindsight/staging/restore.zip` (mode 0600):

```bash
podman exec hindsight-api hindsight-admin restore /backups/restore.zip --yes
```

Check bank/fact counts, restored recall, and pending/processing operations before
removing the worker override and restarting. Delete temporary plaintext. Do not
switch embedding models just because they share a vector dimension.

## Migration validation

The 2026-09-27 moby archive restored seven banks and 17,552 facts. Its original
384-dimensional embedding model was retained. No pending or processing jobs
were present in the restored archive.

Validation covered:

- Real Pi extension loader, health hook, per-bank missions, async retain,
  extraction worker, embeddings, recall, and prompt injection.
- Authenticated recall from ix against Oppy; unauthenticated bank access denied.
- Restored-memory recall after service restarts.
- Removal of the disposable smoke-test bank, returning to original counts.
- Successful encrypted backup and enabled weekly timer.
- Pi adapter regression tests and ix application policy tests.
