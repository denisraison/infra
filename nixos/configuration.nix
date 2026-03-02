{ pkgs, rekan-staging, ... }:

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

  services.rekan.instances = {
    prod = {
      domain = "rekan.com.br";
      envFile = "/etc/rekan.env";
      whatsappNumber = "5511940699184";
    };
    staging = {
      domain = "staging.rekan.com.br";
      port = 8091;
      envFile = "/etc/rekan-staging.env";
      whatsappNumber = "5511940699184";
      package = rekan-staging.packages.aarch64-linux.api;
      webRoot = rekan-staging.packages.aarch64-linux.web;
    };
  };
}
