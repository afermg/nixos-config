# ix outbound SSH

`home.nix` imports `ssh.nix`, independently of the desktop SSH profile. The
runtime-only identity `/home/amunoz/.ssh/id_ed25519_ix_hosts` was generated on
ix, is owned by `amunoz`, mode `0600`, and has no passphrase for unattended use.
It is neither the signing/age identity nor an SSH host key. Only its public
counterpart is tracked. Never copy the private key to another machine or into
Nix; loss of ix requires generating and authorizing a replacement.

| Alias (also accepts destination FQDN) | Destination | User | Authorization declaration |
| --- | --- | --- | --- |
| `mbp`, `alan-purdue-mbp` | `alan-purdue-mbp.tail5e510f.ts.net` | `alan` | `machines/darwin/default.nix`, only `darwin001` / user `alan` |
| `oppy` | `oppy.tail5e510f.ts.net` | `amunoz` | `homes/amunoz/oppy-ssh.nix`, imported by `homeModules.amunoz-oppy` |
| `moby` | `moby.tail5e510f.ts.net` | `amunoz` | `machines/moby/default.nix` |

The dedicated identity is offered only to these names. All three blocks use
`IdentitiesOnly yes`, `IdentityAgent none`, `ForwardAgent no`, and
`StrictHostKeyChecking yes`. GitHub keeps its existing separate identity. The
shared desktop profile and its forwarding policy are unchanged.

## Host identity and public fingerprints

`ssh_known_hosts` becomes `~/.ssh/known_hosts_ix`. Mac's key was verified through
an authenticated connection using Oppy's existing known_hosts, then compared
with the destination's public host key. Oppy's key was read locally and also
matched its existing trusted entry. Moby's key came **only** from Oppy's existing
local known_hosts, matching `secrets/secrets.nix`; no moby connection or probe
was made. Its live identity/reachability is unverified while it is down.

- ix dedicated user key: `SHA256:ckjRqWQYvuJEouHg3WISMvDTblLrp2m2bBoSvtWW0cY`
- mbp ED25519 host key: `SHA256:igR950p0lDptR0nO/W2nGAtaxr0th50ojvXAhuHSip8`
- oppy ED25519 host key: `SHA256:oaUdJAmQrPVnn1bvamsr/9MCrngV4uxHCcK9Rh3/DV4`
- moby ED25519 host key (historical, not live): `SHA256:Ji5CsPRkCydH1WmchqelCkS9V9A+YpMmUFD0Vci7LUc`

## Checks

Static regression checks evaluate the real Nix configuration and OpenSSH's
`ssh -G`; they never contact any destination (including moby):

```sh
python3 homes/ix/test_ssh.py
```

The following actual tests passed from ix on 2026-10-26, independently of an
agent. Verbose checks also confirmed the server accepted the dedicated key's
fingerprint above, not a different identity. Run from Oppy:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 \
  -o ForwardAgent=no -o StrictHostKeyChecking=yes ix 'env -u SSH_AUTH_SOCK sh -s' <<'EOF'
set -eu
for host in mbp oppy; do
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 \
    -o ForwardAgent=no "$host" 'id -un; hostname; printenv SSH_AUTH_SOCK || true'
done
EOF
```

Results: `mbp` returned `alan`, `Mac`; `oppy` returned `amunoz`, `oppy`; neither
reported an agent socket. Do not extend this live loop to moby until the owner
explicitly permits testing it.

## Runtime deployment versus pending Nix activation

Only narrow runtime files were installed; no system/Home Manager activation or
service restart was performed:

- ix: `~/.ssh/config` exactly matches evaluated Home Manager text;
  `~/.ssh/known_hosts_ix` exactly matches the public source file.
- Oppy: previously absent `~/.ssh/authorized_keys` now matches ix's public file.
  Existing `/etc/ssh/authorized_keys.d/amunoz` was not changed.
- Mac: previously absent `/Users/alan/.ssh/authorized_keys` now contains the same
  public key. Nix-darwin will durably authorize it through
  `/etc/ssh/nix_authorized_keys.d/alan` and its existing AuthorizedKeysCommand.
- Moby: **source only**, pending activation and testing; never contacted.

The Nix declarations are integrated into this checkout; host-specific Nix
activation remains pending against each host's active baseline. The lighting-only
ix generation deployed separately does not include these SSH declarations.
During future Home Manager activation, use the configured backup facility or
remove only the exact matching runtime files before replacing them with managed
links. Do not overwrite unrelated authorized keys. After Darwin activation and
a fresh ix login succeeds using the Nix-managed authorization, its temporary
user authorized_keys file can be removed if it still contains only this key.

## Rollback of these narrow runtime changes

Verified backup directory on each modified host: `~/.ssh/backup-ix-hosts-20261026`.
On ix it holds the original `config` and a `known_hosts_ix.absent` marker.
On Oppy and Mac it holds an `authorized_keys.absent` marker. No pre-existing
user authorized_keys files were overwritten. These commands are rollback
instructions, **not executed**; first ensure no later edits or activation occurred:

- ix: restore `config` from that directory with `cp -p`, then remove
  `~/.ssh/known_hosts_ix` (it was absent before).
- Oppy and Mac: remove only the added dedicated key from `~/.ssh/authorized_keys`;
  if the file still exactly matches the tracked public file, remove the file.
- Keep ix's private key until access and rollback are settled. If retiring it,
  remove its public authorization first and then delete it locally on ix.

The original ix config backup SHA256 is
`07962154323613bafc400d377b02826dccdf7376d526e4cc035cef1591d4c3b3`.
The installed client config SHA256 is
`e42e8f2df5c16609da2f73d6b2aab9ef6b7b3f747f43923602a6c008fc8e86d0`.
