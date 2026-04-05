# kirobi-machine/flake.nix
# Nix Flake für die KI-Maschine (Ryzen 9 5900X + RTX 3090)
# Verwendung: nixos-rebuild switch --flake .#kirobi-machine
{
  description = "Disruptive OS V6.0 — Kirobi KI-Maschine (Ryzen 9 5900X + RTX 3090)";

  inputs = {
    # Stabiler NixOS-Kanal
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Hardware-spezifische NixOS-Optimierungen
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Home-Manager für User-Umgebungen
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agenix für verschlüsselte Secrets (age-Verschlüsselung)
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
    nixosConfigurations.kirobi-machine = nixpkgs.lib.nixosSystem {
      inherit system;

      # Alle Inputs als specialArgs weitergeben
      specialArgs = { inherit inputs; };

      modules = [
        # Hardware-spezifische Konfiguration für NVIDIA
        nixos-hardware.nixosModules.common-cpu-amd
        nixos-hardware.nixosModules.common-gpu-nvidia-nonprime

        # Hauptkonfiguration
        ./configuration.nix

        # Home-Manager Integration
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
