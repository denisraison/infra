{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./users.nix
    ./services/caddy.nix
  ];

  system.stateVersion = "23.11";
  time.timeZone = "UTC";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Workaround for https://github.com/NixOS/nix/issues/8502
  services.logrotate.checkConfig = false;

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  networking.hostName = "prod";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    git
    sqlite
  ];

  services.rekan = {
    enable = true;
    domain = "rekan.com.br";
    envFile = "/run/secrets/rekan.env";
  };
}
