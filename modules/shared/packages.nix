{ pkgs }:
with pkgs;
[
  # browser
  firefox

  # Essential and standard GNU
  coreutils
  gawk
  gnused # The one and only sed
  wget # fetch stuff
  ps # processes
  screen # ssh in and out of a server
  parallel # GNU parallel
  killall # kill all the processes by name
  lsof # Files and their processes

  # terminals and shells
  # wezterm installed via programs.wezterm in home.nix
  # kitty
  fish

  # Almost essential
  git

  # Convenience
  tree
  tldr # quick explanations

  # files
  gnutar # The one and only tar
  rsync # sync data
  zip
  unzip # extract zips
  magic-wormhole # easy sharing

  ## faster/better X
  btop-cuda # nicer top
  ripgrep # faster grep in rust
  fd # faster find
  difftastic # better diffs
  dua # better du
  dust # interactive du in tust

  ## Useful when use-case shows itself
  gnuplot # no-fuss plotting
  bc # calculator
  fzf # fuzzy finder
  jq # process json
  mermaid-cli # text to diagrams

  # Development
  direnv # Per-project isolated environment
  racket # Runtime required by Emacs racket-mode/racket-xp-mode
  cargo # rust packages
  rustc # rust compiler
  cmake # c compiler
  clang # c language
  clang-tools # tools for c language
  # libgcc # build stuff # NOT A PACKAGE, move elsewhere

  ## Build chains
  gnumake # Necessary for emacs' vterm
  libtool # Necessary for emacs' vterm
  autoconf
  automake

  ## LSP/formatters/linters
  semgrep # generalistic semantic grep
  nil # Nix
  yaml-language-server # yaml
  lemminx # xml
  marksman # markdown
  ruff # python
  ltex-ls # latex/org-mode
  autotools-language-server # make

  ## Non-LSP code helpers
  shellcheck
  shfmt
  nixfmt-tree # Format entire directories of nix

  # fonts
  emacs-all-the-icons-fonts
  # fontconfig # Needed for napari
  # aporetic

  # containers
  podman # for container needs

  # email
  mu # Maildir indexer and mu4e backend
  mu.mu4e # Matching Emacs frontend, including generated mu4e-config.el
  isync # IMAP sync (mbsync)
  msmtp # SMTP client for sending mail
  rbw # Unofficial Bitwarden CLI with background agent
  pinentry-curses # PIN/password entry for terminal (needed by rbw over SSH)
  gnupg # Required by Emacs's plstore for encrypted token storage (org-gcal OAuth tokens)

  # writing
  pandoc # Convert between formats
  hugo # blogging
  go

  # media
  inkscape # Graphics editing
  ffmpeg # video processing needs
  imagemagick # image processing
  graphicsmagick # imagemagick (+speed, -features) alternative

  # nix utilities
  home-manager
  nix-index # locate packages that provide a certain file
  nix-search-cli # find nix packages
  nixfmt # Nix formatting (for nixpkgs)

  # ocamlPackages.cpdf # PDF compression tools
  # whois # check info on domain holders

]
