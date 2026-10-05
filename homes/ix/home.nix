# Intentionally independent from homeModules.amunoz and the desktop profile.
# Applications were added only after normal boot, recovery, and rollback passed.
{ inputs, ... }:
{
  _module.args.piMsgInputs = inputs;

  imports = [
    inputs.agenix.homeManagerModules.default
    ../../modules/shared/config/pi-msg/pi-msg.nix
    ./applications.nix
  ];
  home = {
    username = "amunoz";
    homeDirectory = "/home/amunoz";
    stateVersion = "26.05";
  };
  programs.home-manager.enable = true;
  programs.bash.enable = true;
  # Git's config is read-only; declare the helper instead of gh auth setup-git.
  # Leave gh.hosts unset so login credentials stay in private runtime state.
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };
  programs.git = {
    enable = true;
    # Keep the private key in runtime state, outside Git and the Nix store.
    # Register its .pub counterpart with GitHub as a signing key.
    signing = {
      format = "ssh";
      key = "/home/amunoz/.ssh/id_ed25519_github_ix";
      signByDefault = true;
    };
    settings = {
      tag.gpgsign = true;
      user = {
        name = "Alán F. Muñoz";
        email = "afer.mg@gmail.com";
      };
    };
  };
  xdg.enable = true;

  age.identityPaths = [ "/home/amunoz/.ssh/id_ed25519_github_ix" ];

  services.pi-msg = {
    enable = true;
    domain = "ix.tail5e510f.ts.net";
    botUsername = "ix";
    secretFile = ../../secrets/pi-msg-ix.age;
    registerLocalAccounts = true;
    requireAccountsReadyMarker = true;
  };
}
