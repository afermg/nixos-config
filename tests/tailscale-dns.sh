#!/usr/bin/env bash
# Evaluate resolver ownership only; do not build or activate either Darwin host.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
for host in darwin001 darwin002; do
  printf '%s: ' "$host"
  nix --extra-experimental-features 'nix-command flakes' eval \
    --json --no-write-lock-file "$repo#darwinConfigurations.$host.config" \
    --apply 'c:
      assert c.services.tailscale.enable;
      assert !c.environment.etc."resolver/ts.net".enable;
      assert !c.services.tailscale.overrideLocalDns;
      assert builtins.length (builtins.split "resolver/ts[.]net" c.system.build.etc.buildCommand) == 1;
      true'
  printf '\n'
done
