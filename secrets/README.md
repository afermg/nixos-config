# secrets/

Encrypted secrets for this NixOS config, managed by [agenix].

Each `*.age` file is a payload (a token, a key, a `.netrc`, an
environment file, …) encrypted to the SSH public keys listed in
`secrets.nix`. At system activation, agenix decrypts everything it
needs and exposes the cleartext at `/run/agenix/<name>` (or a custom
path, see *Where the decrypted secret lands* below). Only the holders
of the corresponding SSH **private** keys can ever read the cleartext;
the `.age` files themselves are safe to commit and push.

## Public key roster

`secrets.nix` lists which keys can decrypt each file:

- `personal_key` — your personal Ed25519 SSH key (decrypts on every
  workstation that has the matching private key in
  `~/.ssh/id_ed25519`).
- `moby_key` — the host SSH key of `moby` (gpa85-cad).
  `/etc/ssh/ssh_host_ed25519_key` on that machine. Required so
  systemd can decrypt secrets at boot without human interaction.

Every secret should have both in `publicKeys`. If you forget one, the
machine that's missing simply can't read it (and agenix will fail at
activation time on that host).

## Where the decrypted secret lands

Default: `/run/agenix/<name>` on tmpfs, owner=`root`, mode `0400`.
This is a runtime path; nothing survives a reboot apart from being
decrypted again at next activation.

Override via the `path`, `owner`, `group`, `mode`, and `symlink`
options on `age.secrets.<name>`:

```nix
age.secrets.netrc-overleaf = {
  file = ../../secrets/netrc-overleaf.age;
  path = "/home/amunoz/.netrc";   # write the decrypted content here
  owner = "amunoz";
  group = "users";
  mode = "0600";
  symlink = false;                # write the file directly, not a symlink
};
```

`symlink = false` matters when the consumer (e.g. libcurl reading
`~/.netrc`) needs a real file and not a symlink into `/run/agenix/`.

## Operations

All commands run from this directory unless noted.

### Create a new secret

```bash
cd ~/.local/share/src/nixos-config/secrets

# 1. Add the filename to secrets.nix:
#      "myservice-token.age".publicKeys = keys;
$EDITOR secrets.nix

# 2. Encrypt your payload to both recipients.
#    Easiest path — pass the cleartext on stdin:
echo -n 'TOKEN=hunter2' | \
  nix run nixpkgs#age -- \
    -r 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4' \
    -r 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClOuXVukvwqgE+UDxJShus+JGprTC8QIoc1G/Ege5KK' \
    -o myservice-token.age

# OR encrypt a whole file:
nix run nixpkgs#age -- \
    -r '<personal pubkey>' -r '<moby pubkey>' \
    -o myservice-token.age \
    /path/to/cleartext

# OR (interactive) use agenix's wrapper, which reads recipients from
# secrets.nix automatically:
nix run github:ryantm/agenix -- -e myservice-token.age

# 3. Reference it in a NixOS module:
#      age.secrets.myservice-token = { file = ../../secrets/myservice-token.age; ... };

# 4. Commit (the .age file is safe to commit/push).
git add myservice-token.age secrets.nix
git commit -m "secrets: add myservice token"
```

### Read (decrypt) a secret

Inspect cleartext without modifying anything:

```bash
# On a host that has the private key for one of the listed recipients:
nix run nixpkgs#age -- -d -i ~/.ssh/id_ed25519 secrets/myservice-token.age

# Or, when the secret is already activated on this host (decrypted by
# agenix to /run/agenix/<name>), just read it as root:
sudo cat /run/agenix/myservice-token

# Or, when path= was set, read it at that path:
sudo cat /home/amunoz/.netrc        # owned by amunoz, no sudo needed for you
```

### Edit a secret

Two approaches.

**A. Interactive, via agenix's wrapper** — opens `$EDITOR` on the
decrypted text, re-encrypts on save. Best for the common case:

```bash
nix run github:ryantm/agenix -- -e secrets/myservice-token.age
```

**B. Manual** — useful if you have automation or want to script:

```bash
# Decrypt to a temp file (ramfs/tmpfs to avoid hitting disk in clear)
TMP=$(mktemp --tmpdir=/dev/shm secret.XXXXXX)
nix run nixpkgs#age -- -d -i ~/.ssh/id_ed25519 \
    secrets/myservice-token.age > "$TMP"

$EDITOR "$TMP"

# Re-encrypt
nix run nixpkgs#age -- \
    -r '<personal pubkey>' -r '<moby pubkey>' \
    -o secrets/myservice-token.age \
    "$TMP"
shred -u "$TMP"
```

After editing, deploy the change:

```bash
git add secrets/myservice-token.age
git commit -m "secrets: rotate myservice token"
sudo nixos-rebuild switch --flake .#moby
```

agenix re-decrypts on activation; no service restart needed unless
the consumer caches the value (then `systemctl restart <unit>`).

### Re-key (after adding/removing a public key in `secrets.nix`)

When you add a new workstation or change a key, every secret needs
to be re-encrypted to the new recipient list:

```bash
# Edit secrets.nix first to add/remove pubkeys
$EDITOR secrets.nix

# Then re-encrypt all secrets in-place
nix run github:ryantm/agenix -- -r
```

agenix iterates every secret, decrypts with the available private
key, re-encrypts to the new recipient set. **You must have a private
key matching one of the OLD recipients on the machine you run this
from** — otherwise nothing can be decrypted and the operation fails.

Commit the resulting `.age` file changes.

### Delete a secret

```bash
# 1. Remove the NixOS reference (age.secrets.<name>) and any consumer
$EDITOR machines/moby/...nix

# 2. Remove the entry from secrets.nix
$EDITOR secrets.nix

# 3. Delete the file
git rm secrets/myservice-token.age
git commit -m "secrets: drop myservice token"
sudo nixos-rebuild switch --flake .#moby
```

After activation, `/run/agenix/myservice-token` (and any custom
`path = …`) disappears on the next boot. To remove the runtime
artifact immediately:

```bash
sudo rm -f /run/agenix/myservice-token
# plus any custom path:
sudo rm -f /home/amunoz/.netrc       # ⚠ only do this when sure
```

If the secret was ever leaked or in any way exposed, **rotate it at
the source** (regenerate the token in Cloudflare / Overleaf /
whatever issued it) before just deleting the file. Removing the
cyphertext from git history requires a force-pushed history rewrite
(`git filter-repo`) — usually not worth it; rotation makes the
leaked value useless instead.

## Conventions

- One secret per file, named `<purpose>-<service>.age`
  (e.g. `cloudflared-overleaf.age`, `netrc-overleaf.age`).
- Treat decrypted content as opaque — store it in whatever format the
  consumer wants (`KEY=value` for `EnvironmentFile=`, raw netrc, raw
  JSON, etc.).
- Never check in plaintext alongside `.age`. The `.gitignore` should
  cover the common temp filenames; double-check before pushing.
- The age cyphertexts are not space-efficient (~520 bytes overhead
  per recipient) but neither is the repo — don't worry about size.

## See also

- [agenix README] — upstream docs, all options for `age.secrets.<name>`.
- `homes/amunoz/...` — where home-manager-level consumers reference
  the secrets (e.g. the `~/.netrc` path).
- `machines/moby/overleaf.nix` — archived, non-imported former consumer of
  `cloudflared-overleaf`; see `machines/moby/OVERLEAF_ARCHIVE.md` for the
  active Oppy/Karkinos setup. The `netrc-overleaf` secret remains useful to
  clients of the current Git Bridge.

[agenix]: https://github.com/ryantm/agenix
[agenix README]: https://github.com/ryantm/agenix?tab=readme-ov-file#age-nix
