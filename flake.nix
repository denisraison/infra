{
  description = "Infrastructure — Hetzner CAX11 ARM64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    rekan.url = "github:denisraison/rekan";
    rekan-staging.url = "github:denisraison/rekan";
  };

  outputs = { nixpkgs, rekan, rekan-staging, ... }:
    let
      sharedModules = [
        rekan.nixosModules.default
        ./nixos/configuration.nix
      ];
      specialArgs = { inherit rekan rekan-staging; };
    in
    {
      # Local deploy from x86_64 workstation (cross-compiled, no emulation)
      nixosConfigurations.prod = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        inherit specialArgs;
        modules = sharedModules ++ [({ lib, ... }: {
          services.rekan.instances.prod = {
            package = lib.mkForce rekan.packages.x86_64-linux.api-cross-aarch64;
            webRoot = lib.mkForce (rekan.packages.x86_64-linux.web.override {
              publicEnv.PUBLIC_WHATSAPP_NUMBER = "5511940699184";
            });
          };
        })];
      };

      # Server-side rebuild (fallback when away from workstation)
      nixosConfigurations.prod-remote = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        inherit specialArgs;
        modules = sharedModules;
      };
    };
}
