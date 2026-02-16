{ config, pkgs, lib, ... }:

let
  pbInstances = import ./pb-instances.nix;

  pocketbase = pkgs.stdenv.mkDerivation rec {
    pname = "pocketbase";
    version = "0.25.9";
    src = pkgs.fetchurl {
      url = "https://github.com/pocketbase/pocketbase/releases/download/v${version}/pocketbase_${version}_linux_arm64.zip";
      sha256 = "1plxp6zz3325fv7rdjjlsdbrcdw58gc5kfl25shb94lbdr74489a";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    unpackPhase = "unzip $src";
    installPhase = ''
      mkdir -p $out/bin
      cp pocketbase $out/bin/
      chmod +x $out/bin/pocketbase
    '';
  };
in {
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

  networking.hostName = "postador-prod";
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

  # PocketBase systemd services
  systemd.services = lib.mapAttrs' (name: cfg:
    lib.nameValuePair "pocketbase-${name}" {
      description = "PocketBase ${name}";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pocketbase}/bin/pocketbase serve --http=127.0.0.1:${toString cfg.port} --dir=/var/lib/pocketbase/${name}";
        WorkingDirectory = "/var/lib/pocketbase/${name}";
        Restart = "always";
        RestartSec = 5;

        DynamicUser = true;
        StateDirectory = "pocketbase/${name}";
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    }
  ) pbInstances;
}
