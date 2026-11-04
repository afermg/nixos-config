# Darwin Tailscale DNS ownership

## Why the resolver must not be a Nix symlink

The pinned nix-darwin Tailscale module creates `environment.etc."resolver/ts.net"`
with a `100.100.100.100` nameserver. That produces:

```text
/etc/resolver/ts.net -> /etc/static/resolver/ts.net -> /nix/store/...
```

Tailscale 1.102.4 manages its own split-DNS resolver files using directory-scoped
file access (`os.OpenRoot("/etc/resolver")`). It cannot write through a symlink
that escapes that directory. The observed error was:

```text
Tailscale failed to set the DNS configuration of your device:
openat ts.net: path escapes from parent
```

The Darwin configuration therefore disables **only that `environment.etc`
entry**. `services.tailscale.enable` remains true; the daemon, package, saved
profiles and tailnet-provided DNS settings are unchanged. Do not replace this
with a global nameserver override or install a second Tailscale daemon/app.

## Existing installation / activation

Do not edit immutable Nix store targets. Back up the existing symlink and its
contents outside `/etc/resolver` before a live repair: every file in the resolver
directory can affect DNS, including an in-place backup.

For the incident that motivated this change, an administrator atomically replaced
only the conflicting symlink with a regular file containing the same nameserver.
Tailscale then reapplied its existing DNS configuration, replacing that regular
file with its own generated contents. Private root-owned backup/rollback material
was retained. Both public DNS and MagicDNS were tested; no broad DNS reset or
system rebuild was used for the live repair.

This source change prevents a later nix-darwin activation from recreating the
symlink. It is not itself an instruction to rebuild a dirty checkout or activate
unrelated host changes. The pinned nix-darwin activation removes stale links into
`/etc/static` and does not replace a regular resolver file excluded from its etc
manifest. A daemon still reporting a previous error may need its existing DNS
configuration reapplied in a controlled window; preserve the original accept-DNS
setting and recovery path rather than leaving DNS disabled.

## Checks

Evaluate both Darwin configurations without building or activating a system:

```sh
bash tests/tailscale-dns.sh
```

This asserts that the daemon remains enabled, the static resolver entry and
`overrideLocalDns` are disabled, and the generated `system.build.etc` command
excludes `resolver/ts.net`. Both `darwin001` and `darwin002` must return `true`.

After a deliberately reviewed activation/live repair:

- `/etc/resolver/ts.net`, if present, must not point into `/etc/static` or the Nix
  store; allow tailscaled to create/remove its generated resolver entries.
- The DNS health error must clear, public lookup must work, and a known active
  tailnet FQDN must resolve through macOS's resolver (`dscacheutil -q host -a name
  <fqdn>`), not just a direct query to Tailscale's DNS server.
- Verify fresh, strict-host-key OpenSSH by FQDN separately from name resolution.

## Separate transport issue

Fixing DNS did **not** alone fix the Spirit migration's numeric TCP/SSH failure.
The freshly received lab peer map lacked Spirit's home DERP relay while its old
profile advertised that relay. Restarting only Spirit's `tailscaled` in a guarded
window restored the advertisement; after the peer handshake settled, numeric SSH,
FQDN SSH and a LAN jump through Spirit succeeded. Do not widen ACLs, rotate keys,
or blame all numeric failures on DNS. `Running` and `Online` are not sufficient
acceptance checks; verify the actual peer path and a fresh authenticated session.
