{
  description = "Infrastructure — Hetzner CAX11 ARM64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    rekan.url = "github:denisraison/rekan";
  };

  outputs = { nixpkgs, rekan, ... }: {
    nixosConfigurations.prod = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        rekan.nixosModules.default
        ./nixos/configuration.nix
      ];
    };
  };
}
