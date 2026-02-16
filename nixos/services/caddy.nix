{ lib, ... }:

let
  pbInstances = import ../pb-instances.nix;

  caddyHosts = lib.mapAttrs' (_name: cfg:
    lib.nameValuePair cfg.domain {
      extraConfig = ''
        reverse_proxy localhost:${toString cfg.port}
      '';
    }
  ) pbInstances;
in {
  services.caddy = {
    enable = true;
    virtualHosts = caddyHosts;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
