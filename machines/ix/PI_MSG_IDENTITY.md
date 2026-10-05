# ix XMPP bot address migration — 2026-10-02

The ix interactive bot and its job digests now use **ix@ix.tail5e510f.ts.net**.
The phone owner remains **alan@ix.tail5e510f.ts.net**; the owner's password was
not changed. Add the new bot contact in Conversations and use unencrypted chat
mode (no OMEMO support; transport TLS remains verified).

## Changes and verification

- Set `services.pi-msg.botUsername = "ix"` in `homes/ix/home.nix`.
- Created the new ejabberd account with an independently generated password.
- Updated `secrets/pi-msg-ix.age`, encrypted to the same existing public recipients;
  verified encryption/decryption round-trip without printing credentials.
- Added a regression assertion to `machines/ix/tests/test_application_policy.py`;
  all 17 application-policy tests pass.
- Preserved the old `pi` account and password. **Do not delete it casually:** the
  moby profile still uses `pi@ix...`; that host/account was outside this migration.
- Restarted ix's pi-msg service and observed `ix@ix...` connected to ejabberd,
  alongside the owner's Conversations connection. Sent a test message from the
  new JID. A reply round trip must be confirmed by the phone user.
- Digests read the shared live config, so no hard-coded sender changes were needed.
- Existing default session pointers and Pi sessions are preserved. Client-side
  chat history for the old JID is not moved to the new contact.

## Scoped, reboot-persistent activation

The source checkout already contained unrelated pending Emacs/email changes.
To avoid deploying them, **no full NixOS/Home Manager switch was performed**.
Only the three XMPP-specific generated scripts were built from the updated module:

- agenix decryptor (its configured secrets list is verified to contain only pi-msg);
- pi-msg config validator;
- account-registration helper.

They are retained through this Nix GC root:

```
/home/amunoz/.local/share/pi-msg-identity/current
  -> /nix/store/dvzi2ag3a952a9jhs2hfmgzwhbv7cdcg-pi-msg-ix-identity
```

Two persistent user-service drop-ins select the updated decryptor and validator:

```
~/.config/systemd/user/agenix.service.d/50-ix-identity.conf
~/.config/systemd/user/pi-msg.service.d/50-ix-identity.conf
```

The first replaces agenix `ExecStart` with `current/decrypt-secrets`; the second
replaces pi-msg `ExecStartPre` with `current/check-config`. The original
Nix-managed units, their boot enablement, and dependency ordering are unchanged.
The configuration is still decrypted into private `/run/user/1000/agenix` storage
and its existing `~/.config/pi-msg/config.json` symlink. There is no new plaintext
credential on persistent disk or in the Nix store.

The bot, agenix, ejabberd, Tailscale, and digest timer are enabled. User lingering
is enabled and the account-readiness marker is a 0600 file on persistent ext4.
A real service restart exercised decryption, validation and reconnection under
the new identity. **No machine reboot was performed.**

## Next normal Nix deployment: reconcile these drop-ins

**Do not leave the scoped agenix override in place indefinitely if adding other
age secrets.** It intentionally captures the current pi-msg-only configuration.
After reviewing pending work and deploying the updated source normally:

1. Confirm the newly generated base units select the updated ix validator and
   an agenix decryptor using the new ciphertext (and any newly configured secrets).
2. Remove only the two `50-ix-identity.conf` files listed above.
3. Run `systemctl --user daemon-reload` and `systemctl --user restart pi-msg.service`.
4. Verify the active JID is still ix, the service is enabled/healthy, and phone
   `/session` works. Then the scoped GC root can be retired if no longer needed.

Until that full deployment, the globally installed `pi-msg-register-accounts`
helper is still the old generation. **Do not use it to reset this new bot.** If
an intentional account/password reset is needed before normal deployment, use:

```
~/.local/share/pi-msg-identity/current/register-accounts
```

It prompts for and resets the phone owner's password as well; registration is
not needed merely to use the new bot address. Follow an intended reset with an
explicit service start/restart; the upstream helper uses `try-restart`.

## Rollback

Private migration backups (old encrypted secret and original home.nix, no
plaintext password) are at:

```
~/.local/state/pi-msg/jid-migration-20261002/
```

The build expression and non-secret migration status are saved there too.
Before a later full deployment, reverting to the original pi identity requires
stopping the bot, restoring the two source files from these backups, removing
only the two scoped drop-ins, reloading systemd, and starting the bot. The original
base agenix unit still references the old ciphertext and original validator.
Verify the old JID reconnects. Do not unregister either account or change the
phone password as a rollback step. After a full deployment, evaluate rollback
against the then-current generation instead of blindly applying these steps.

Unrelated source modifications were left untouched. Migration source changes
are not committed or pushed automatically.
