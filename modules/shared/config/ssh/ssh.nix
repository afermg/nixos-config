{ config, lib, ... }:
let
  trustedHosts = [
    "ix"
    "moby"
    "oppy"
  ];
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings =
      lib.listToAttrs (
        map (
          host:
          lib.nameValuePair "${host} ${host}.tail5e510f.ts.net" {
            HostName = "${host}.tail5e510f.ts.net";
            User = "amunoz";
            ForwardAgent = true;
            # Add a key used for authentication to an already-running agent.
            # This does not start an agent or unlock keys without a passphrase.
            AddKeysToAgent = "yes";
          }
        ) trustedHosts
      )
      // {
        # Home Manager renders the default block last: OpenSSH uses the first
        # value found. Never expose the agent to arbitrary destinations.
        "*".ForwardAgent = false;
        "github.com" = {
          IdentitiesOnly = true;
          IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
        };
      };
  };
}
