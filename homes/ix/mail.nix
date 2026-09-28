# Provider credentials live in private runtime files, never in the Nix store.
# The initial seed gate protects first activation; policies match the source accounts.
{ config, pkgs, ... }:
let
  # Preserve existing runtime credentials/state and the shared lock across rollback.
  secretDir = "${config.xdg.configHome}/raspi4-secrets";
  isync = pkgs.isync.override { withCyrusSaslXoauth2 = true; };
  syncMail = pkgs.writeShellApplication {
    name = "ix-mail-sync";
    runtimeInputs = [
      isync
      pkgs.util-linux
      pkgs.python3
    ];
    text = ''
      if [ ! -f "${config.xdg.stateHome}/raspi4-deployment/mail-seed-complete" ]; then
        echo "Mail seed has not passed checksum verification; synchronization refused." >&2
        exit 1
      fi
      exec 9> "$HOME/.cache/raspi4-mail-sync.lock"
      flock -n 9
      mbsync -a
      export MIRROR_MAIL_PASSWORD_FILE="${secretDir}/quasimorphic-password"
      python3 ${../../modules/shared/config/email/mirror-mail.py} purdue broad broad-spam
      mbsync quasimorphic-archives quasimorphic:Junk
    '';
  };
  password = name: [
    "${pkgs.coreutils}/bin/cat"
    "${secretDir}/${name}-password"
  ];
in
{
  home.packages = [
    pkgs.mu
    isync
    syncMail
  ];
  programs.msmtp.enable = true;
  accounts.email = {
    maildirBasePath = ".mail";
    accounts = {
      quasimorphic = {
        primary = true;
        realName = "Alán F. Muñoz";
        address = "alan@quasimorphic.com";
        userName = "alan@quasimorphic.com";
        passwordCommand = password "quasimorphic";
        smtp = {
          host = "witcher.mxrouting.net";
          port = 465;
          tls.useStartTls = false;
        };
        msmtp.enable = true;
      };
      broad = {
        realName = "Alán F. Muñoz";
        address = "amunozgo@broadinstitute.org";
        userName = "amunozgo@broadinstitute.org";
        passwordCommand = password "broad";
        smtp = {
          host = "smtp.gmail.com";
          port = 465;
          tls.useStartTls = false;
        };
        msmtp.enable = true;
      };
      purdue = {
        realName = "Alán F. Muñoz";
        address = "amunozgo@purdue.edu";
        userName = "amunozgo@purdue.edu";
        passwordCommand = [
          "${pkgs.oama}/bin/oama"
          "access"
          "amunozgo@purdue.edu"
        ];
        smtp = {
          host = "smtp.office365.com";
          port = 587;
          tls.useStartTls = true;
        };
        msmtp = {
          enable = true;
          extraConfig.auth = "xoauth2";
        };
      };
    };
  };
  home.file.".mbsyncrc".text =
    builtins.replaceStrings
      [ "@QUASIMORPHIC_PASSWORD@" "@BROAD_PASSWORD@" "@OAMA@" ]
      [
        "${pkgs.coreutils}/bin/cat ${secretDir}/quasimorphic-password"
        "${pkgs.coreutils}/bin/cat ${secretDir}/broad-password"
        "${pkgs.oama}/bin/oama"
      ]
      (builtins.readFile ./mbsyncrc);
  # A Pi-only encryption key is created privately during token migration.
  # The moby signing/decryption private key is deliberately not copied.
  xdg.configFile."oama/config.yaml".text = ''
    encryption:
      tag: GPG
      contents: raspi4-oama
    services:
      microsoft:
        client_id: 9e5f94bc-e8a4-4e73-b8be-63364c29d753
        tenant: common
  '';
}
