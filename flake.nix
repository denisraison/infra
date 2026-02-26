{
  description = "Infrastructure — Hetzner CAX11 ARM64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    rekan.url = "github:denisraison/rekan";
    rekan-staging.url = "github:denisraison/rekan";
  };

  outputs = { nixpkgs, rekan, rekan-staging, ... }: {
    nixosConfigurations.prod = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit rekan rekan-staging; };
      modules = [
        rekan.nixosModules.default
        ./nixos/configuration.nix
      ];
    };
  };
}
