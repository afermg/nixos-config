# Native ARM dependencies for the shared Emacs configuration, without a desktop.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fish
    fzf
    git
    gh
    curl
    unzip
    gcc
    gnumake
    cmake
    libtool
    pkg-config
    python3
    uv
    jq
    ripgrep
    fd
    duckdb
    graphviz
    gnuplot
    pandoc
    hugo
    imagemagick
    poppler-utils
    mermaid-cli
    racket-minimal
    sbcl
    nil
    nixfmt
    ruff
    marksman
    yaml-language-server
    harper
    shellcheck
    shfmt
    rbw
    pinentry-curses
    (runCommand "epdfinfo" { } ''
      mkdir -p "$out/bin"
      ln -s ${emacsPackages.pdf-tools}/share/emacs/site-lisp/elpa/pdf-tools-*/epdfinfo "$out/bin/epdfinfo"
    '')
    (writeShellApplication {
      name = "gptel-pi-openai-auth";
      runtimeInputs = [ nodejs ];
      text = ''
        exec node ${../../modules/shared/config/pi/gptel-openai-auth.mjs} \
          ${pi-coding-agent}/lib/node_modules/pi-monorepo/dist/index.js
      '';
    })
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
