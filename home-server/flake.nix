# home-server/flake.nix
# Nix Flake für den Home-Server (ZFS-Storage + Familiendienste)
# Verwendung: nixos-rebuild switch --flake .#home-server
{
  description = "Disruptive OS V6.0 — Home-Server (ZFS + Nextcloud + Immich + Jellyfin + MinIO)";

  inputs = {
    # Stabiler NixOS-Kanal
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Hardware-Optimierungen
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Home-Manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agenix für verschlüsselte Secrets
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, agenix, ... }@inputs:
  let
    system = "x86_64-linux";
  in
  {
    nixosConfigurations.home-server = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = { inherit inputs; };

      modules = [
        # Allgemeine Hardware-Optimierungen
        nixos-hardware.nixosModules.common-pc-ssd

        # Hauptkonfiguration
        ./configuration.nix

        # Home-Manager
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.sven = import ./home/sven.nix;
        }

        # Agenix Secrets Management
        agenix.nixosModules.default
      ];
    };
  };
}
