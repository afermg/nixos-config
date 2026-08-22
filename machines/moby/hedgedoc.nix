# HedgeDoc — collaborative Markdown editor (moby-only).
#
# Exposure: bound to 127.0.0.1:4000 so nothing on the LAN can reach it
# directly. Access today is via `tailscale serve` on moby, which
# terminates HTTPS at moby.tail5e510f.ts.net and proxies to localhost
# — so the only clients that can reach HedgeDoc are devices on this
# tailnet. The `tailscale serve` config lives in tailscaled's state
# file (/var/lib/tailscale/tailscaled.state), not in this flake; it
# survives reboots and rebuilds but NOT `tailscale logout` or a tailnet
# re-auth. Re-issue if that happens:
#     sudo tailscale serve --bg http://localhost:4000
#
# State: HedgeDoc keeps its sqlite db + uploads under
# /var/lib/hedgedoc/. Back that directory up to keep notes safe.
#
# Going public on hedgedoc.quasimorphic.com (future): use the maintained
# Karkinos connector pattern linked from ./OVERLEAF_ARCHIVE.md — add an
# age-encrypted tunnel token, a `systemd.services.cloudflared-hedgedoc` unit, and
# change `domain` below to "hedgedoc.quasimorphic.com". Don't open
# any inbound ports on the host firewall — the tunnel is outbound-only.
#
# Session secret comes from secrets/hedgedoc-env.age (an env file
# containing `CMD_SESSION_SECRET=...`); HedgeDoc reads the env var
# natively, so logins survive service restarts.
{ config, ... }:
{
  age.secrets.hedgedoc-env = {
    file = ../../secrets/hedgedoc-env.age;
    owner = "hedgedoc";
    group = "hedgedoc";
    mode = "0400";
  };

  services.hedgedoc = {
    environmentFile = config.age.secrets.hedgedoc-env.path;
    enable = true;
    settings = {
      host = "127.0.0.1";
      # Preserve the established Moby origin on 4000 rather than reusing its
      # upstream default port.
      port = 4000;

      # Public hostname HedgeDoc emits in generated links, WebSocket
      # origin checks, and CSP rules. Must match what the browser sees
      # in the address bar — otherwise styling/buttons break because
      # the JS tries to talk back to the wrong origin. Currently the
      # tailscale-serve magic-DNS name; swap for the Cloudflare
      # hostname when going public.
      domain = "moby.tail5e510f.ts.net";
      protocolUseSSL = true;

      # Private-collaboration defaults: must be signed in to do anything,
      # no anonymous "/new" URLs, new notes are collaborative among
      # signed-in users but invisible to anyone else.
      allowAnonymous = false;
      allowAnonymousEdits = false;
      allowFreeURL = false;
      defaultPermission = "limited";

      # Email signup is on for initial onboarding. Once your colleagues'
      # accounts exist, flip this to false to lock the door against
      # further self-registration. Existing logins keep working.
      allowEmailRegister = true;
    };
  };
}
