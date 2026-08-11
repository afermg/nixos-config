{
  description = "Crafting systems";

  inputs = {
    # Nixpkgs
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # darwin inputs
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    # system and flake util
    systems.url = "github:nix-systems/default";

    # disko (partitioning)
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # agenix (secrets)
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hardware.url = "github:nixos/nixos-hardware";

    # firefox-addons = {
    #   url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    emacs-overlay.url = "github:nix-community/emacs-overlay";

    claude-code.url = "github:sadjow/claude-code-nix";

    overleaf-nix = {
      url = "github:afermg/overleaf-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    marimohub-nix = {
      url = "github:afermg/marimohub-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      systems,
      flake-utils,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      lib = nixpkgs.lib // home-manager.lib;
      forEachSystem = f: lib.genAttrs (import systems) (system: f pkgsFor.${system});
      pkgsFor = lib.genAttrs (import systems) (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );
    in
    {
      inherit lib;

      # custom modules
      nixosModules = import ./modules/nixos { inherit inputs outputs; };
      darwinModules.aerospace = import ./modules/darwin/aerospace.nix;
      # homeManagerModules = import ./modules/home-manager { inherit allowed-unfree-packages; };

      overlays = import ./overlays { inherit inputs outputs; };

      # Single source of truth for amunoz's Linux home-manager profile.
      # Used by this flake's own moby system and `homeConfigurations."amunoz@moby"`,
      # and intended for external consumption by other flakes that want to
      # apply the same profile to a user named `amunoz`. Bakes in overlays +
      # agenix so consumers don't re-plumb them. The namespaced input argument
      # cannot be shadowed by a consumer's generic `extraSpecialArgs.inputs`.
      homeModules.amunoz = {
        _module.args = {
          inherit inputs outputs;
          amunozInputs = inputs;
        };
        imports = [
          agenix.homeManagerModules.default
          ./homes/amunoz/home.nix
        ];
        nixpkgs = {
          config.allowUnfree = true;
          overlays = [
            outputs.overlays.emacs
            outputs.overlays.stable
            outputs.overlays.claude-code
          ];
        };
      };

      # Reusable host-specific Pi/XMPP bridge. Consumers configure the domain,
      # encrypted account file, and whether the local registration helper is
      # appropriate for that host.
      homeModules.pi-msg = {
        imports = [
          agenix.homeManagerModules.default
          ./modules/shared/config/pi-msg/pi-msg.nix
        ];
      };

      # packages = forEachSystem (pkgs: import ./pkgs {inherit pkgs;});
      devShells = forEachSystem (pkgs: import ./shell.nix { inherit pkgs inputs; });
      # formatter = forEachSystem (pkgs: pkgs.nixfmt-rfc-style);
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        moby = lib.nixosSystem {
          modules = [
            ./machines/moby
            agenix.nixosModules.default

            {
              age.secrets = {
                tailscale.file = ./secrets/tailscale.age;
              };
            }
          ];

          specialArgs = { inherit inputs outputs; };
        };
      };

      # Darwin configuration entrypoint
      # Available through 'darwin-rebuild --flake .#your-hostname'
      darwinConfigurations =
        let
          mkDarwin =
            user:
            inputs.darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              modules = [ ./machines/darwin ];
              specialArgs = { inherit inputs outputs user; };
            };
        in
        {
          darwin001 = mkDarwin "alan";
          darwin002 = mkDarwin "amunozgo";
        };

      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager switch --flake .#your-username@your-hostname'
      homeConfigurations =
        let
          mkDarwinHome =
            user:
            lib.homeManagerConfiguration {
              pkgs = pkgsFor.aarch64-darwin;
              extraSpecialArgs = {
                inherit inputs outputs;
                username = user;
              };
              modules = [
                agenix.homeManagerModules.default
                ./homes/amunoz/darwin.nix
              ];
            };
        in
        {
          "amunoz@moby" = lib.homeManagerConfiguration {
            pkgs = pkgsFor.x86_64-linux;
            extraSpecialArgs = { inherit inputs outputs; };
            modules = [
              outputs.homeModules.amunoz
              outputs.homeModules.pi-msg
              ./modules/shared/config/syncthing/sync.nix
              {
                services.pi-msg = {
                  enable = true;
                  domain = "moby.tail5e510f.ts.net";
                  secretFile = ./secrets/pi-msg.age;
                  registerLocalAccounts = true;
                };
              }
            ];
          };

          "amunoz@oppy" = lib.homeManagerConfiguration {
            pkgs = pkgsFor.x86_64-linux;
            extraSpecialArgs = { inherit inputs outputs; };
            modules = [
              outputs.homeModules.amunoz
              outputs.homeModules.pi-msg
              {
                # Decrypt the existing Overleaf git-bridge credentials with
                # ~/.ssh/id_ed25519 when this Home Manager profile activates.
                age.secrets.netrc-overleaf = {
                  file = ./secrets/netrc-overleaf.age;
                  path = "/home/amunoz/.netrc";
                  mode = "0600";
                  symlink = false;
                };

                services.pi-msg = {
                  enable = true;
                  domain = "moby.tail5e510f.ts.net";
                  botUsername = "pi-oppy";
                  secretFile = ./secrets/pi-msg-oppy.age;
                  registrationSshHost = "moby.tail5e510f.ts.net";
                };
              }
            ];
          };

          "amunoz@spirit" = lib.homeManagerConfiguration {
            pkgs = pkgsFor.x86_64-linux;
            extraSpecialArgs = { inherit inputs outputs; };
            modules = [ outputs.homeModules.amunoz ];
          };

          "amunoz@karkinos" = lib.homeManagerConfiguration {
            pkgs = pkgsFor.x86_64-linux;
            extraSpecialArgs = { inherit inputs outputs; };
            modules = [ outputs.homeModules.amunoz ];
          };

          "zchen@moby" = lib.homeManagerConfiguration {
            pkgs = pkgsFor.x86_64-linux;
            extraSpecialArgs = { inherit inputs outputs; };
            modules = [ ./homes/zchen/moby.nix ];
          };

          "alan@darwin001" = mkDarwinHome "alan";
          "amunozgo@darwin002" = mkDarwinHome "amunozgo";
        };
    };
}
