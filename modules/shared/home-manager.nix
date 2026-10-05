{
  config,
  pkgs,
  lib,
  user ? "alan",
  ...
}:
let
  name = "Alán F. Muñoz";
  email = "afer.mg@gmail.com";
in
{
  # Shared shell configuration

  # home.file.".ssh/allowed_signers".text = "* ${id_ed25519_pub}";
  git = {
    enable = true;
    ignores = [ "*.swp" ];
    settings.user.name = name;
    settings.user.email = email;
    lfs = {
      enable = true;
    };
    # extraConfig = {
    #   # Sign all commits using ssh key
    #   commit.gpgsign = true;
    #   gpg.format = "ssh";
    #   gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
    #   user.signingkey = "~/.ssh/id_ed25519.pub";
    #   init.defaultBranch = "main";
    #   core = {
    #   editor = "emacs";
    #     autocrlf = "input";
    #   };
    #   pull.rebase = true;
    #   rebase.autoStash = true;
    # };
  };

  # SSH is configured by the common home profile's config/ssh/ssh.nix import,
  # so Darwin, Moby, and Oppy use the same trusted-host forwarding policy.
}
