{ config, lib, ... }:
let
  destinations = {
    "mbp alan-purdue-mbp alan-purdue-mbp.tail5e510f.ts.net" = {
      HostName = "alan-purdue-mbp.tail5e510f.ts.net";
      User = "alan";
    };
    "oppy oppy.tail5e510f.ts.net" = {
      HostName = "oppy.tail5e510f.ts.net";
      User = "amunoz";
    };
    "moby moby.tail5e510f.ts.net" = {
      HostName = "moby.tail5e510f.ts.net";
      User = "amunoz";
    };
  };
in
{
  # Public host keys only. The dedicated private identity stays on ix, outside
  # Git, agenix and the Nix store; it is not the signing/age or host identity.
  home.file.".ssh/known_hosts_ix".source = ./ssh_known_hosts;
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings =
      lib.mapAttrs (
        _: destination:
        destination
        // {
          IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519_ix_hosts";
          IdentitiesOnly = true;
          IdentityAgent = "none";
          ForwardAgent = false;
          StrictHostKeyChecking = "yes";
          UserKnownHostsFile = "${config.home.homeDirectory}/.ssh/known_hosts_ix";
        }
      ) destinations
      // {
        "*".ForwardAgent = false;
        # Preserve ix's existing independent GitHub signing/authentication key.
        "github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519_github_ix";
          IdentitiesOnly = true;
        };
      };
  };
}
