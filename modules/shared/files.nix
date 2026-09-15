{
  pkgs,
  config,
  ...
}:
{
  # Initializes Emacs with org-mode so we can tangle the main config.
  # `mkOutOfStoreSymlink' points the managed file at the repo path instead
  # of copying it into the read-only Nix store, so edits to init.el land
  # in the repo and take effect on the next Emacs start without a
  # home-manager rebuild. Same treatment applied across Linux and Darwin
  # (both import this file via homes/amunoz/home.nix).
  ".emacs.d/init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/src/nixos-config/modules/shared/config/emacs/init.el";
  };
  # config.org is intentionally not linked here — init.el already reads it
  # directly from the repo path, so it stays editable with zero setup.

  # Let Git verify SSH-signed commits made by this identity.
  ".ssh/allowed_signers".text = "* ${builtins.readFile ../../homes/amunoz/id_ed25519.pub}";

  # Email configuration (mbsync stays as a raw file; msmtp is now generated
  # by home-manager via accounts.email in home.nix, since msmtp requires the
  # rc file to be mode 0600 — impossible on a read-only /nix/store symlink.)
  ".mbsyncrc" = {
    text = builtins.readFile ../shared/config/email/mbsyncrc;
  };
  ".local/bin/mirror-purdue-mail" = {
    source = ./config/email/mirror-purdue.py;
    executable = true;
  };
}
