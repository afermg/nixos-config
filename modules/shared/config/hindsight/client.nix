{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  hindsightConfig = {
    api_url = "http://oppy.tail27b080.ts.net:8888";
    token_file = "${home}/.config/hindsight/api-token";
    state_dir = "${home}/.local/state/hindsight";
    reflect_mission = "Maintain durable technical knowledge about this Git repository across coding agents.";
    retain_mission = "Extract project decisions, architecture, conventions, user preferences, and useful failed approaches. Preserve exact non-secret technical identifiers verbatim, including hashes, hostnames, paths, flags, commands, versions, and configuration values. Every explicit non-secret identifier and configuration value must appear verbatim in the extracted memory text, not only as an entity. Never extract or retain credentials, private keys, authentication tokens, or other secrets. Ignore transient command output and routine chatter.";
  };
in
{
  age.secrets.hindsight-api-token = {
    file = ../../../../secrets/hindsight-api-token.age;
    path = "${home}/.config/hindsight/api-token";
    mode = "0600";
    symlink = false;
  };

  home.file = {
    ".local/share/hindsight-client/hindsight.ts" = { source = ./hindsight.ts; force = true; };
    ".local/share/hindsight-client/hindsight-memory.mjs" = { source = ./hindsight-memory.mjs; force = true; };
    ".local/bin/hindsight-memory" = {
      executable = true;
      force = true;
      text = ''
        #!${pkgs.runtimeShell}
        exec ${pkgs.nodejs}/bin/node "${home}/.local/share/hindsight-client/hindsight-memory.mjs" "$@"
      '';
    };
    ".config/hindsight/config.json" = {
      text = builtins.toJSON hindsightConfig;
      force = true;
    };
    ".pi/agent/extensions/hindsight.ts" = {
      source = ./hindsight.ts;
      force = true;
    };
  };

  home.activation.hindsightPrivateState = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 \
      "${home}/.config/hindsight" \
      "${home}/.local/state/hindsight" \
      "${home}/.local/state/hindsight/turns"
  '';
}
