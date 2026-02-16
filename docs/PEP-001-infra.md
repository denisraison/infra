# PEP 001: Postador AI Infrastructure

| Field       | Value                              |
| ----------- | ---------------------------------- |
| **Title**   | Postador AI Infrastructure as Code |
| **Author**  | Denis                              |
| **Status**  | Draft                              |
| **Created** | 2026-02-17                         |
| **Target**  | Production                         |

## Summary

Declarative, version controlled infrastructure for Postador AI using OpenTofu (Terraform fork) to provision Hetzner Cloud resources and NixOS to configure the server. A single CAX11 ARM64 instance in Germany runs multiple PocketBase instances behind Caddy reverse proxy with automatic TLS.

## Motivation

Postador AI currently runs on Fly.io which becomes expensive when scaling to multiple apps. We need a cost effective, reproducible infrastructure that:

- Costs under R$35/month (~US$6)
- Runs multiple PocketBase instances on a single server
- Is fully declarative and version controlled
- Can be rebuilt from scratch in minutes
- Requires minimal ongoing maintenance

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Hetzner Cloud CAX11                │
│          ARM64 · 2 vCPU · 4GB RAM              │
│            Falkenstein, Germany                  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │              NixOS 24.11                  │  │
│  │                                           │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │     Caddy (reverse proxy + TLS)     │  │  │
│  │  │         :80 / :443                  │  │  │
│  │  └──────┬──────────┬───────────────────┘  │  │
│  │         │          │                      │  │
│  │    ┌────▼───┐ ┌────▼───┐                  │  │
│  │    │ PB #1  │ │ PB #2  │  ...             │  │
│  │    │ :8090  │ │ :8091  │                  │  │
│  │    └────────┘ └────────┘                  │  │
│  │                                           │  │
│  │  systemd services · journald logging      │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Firewall: 22 (SSH), 80 (HTTP), 443 (HTTPS)    │
└─────────────────────────────────────────────────┘
         │
         │  ~220ms latency
         ▼
    Brazilian Users
```

## Technology Choices

### OpenTofu over Terraform

OpenTofu is the open source fork of Terraform, created after HashiCorp changed Terraform's license to BSL in 2023. It is 1:1 compatible with Terraform HCL and providers, maintained by the Linux Foundation, and will remain truly open source (MPL 2.0). All Terraform documentation and tutorials apply directly.

### NixOS over Ubuntu + Docker

NixOS provides declarative server configuration in a single file. The entire server state (packages, services, firewall, users) is defined in code and can be reproduced exactly. Compared to Docker on Ubuntu:

- **Memory**: NixOS base ~150MB vs Docker + Coolify ~1.5GB
- **Complexity**: Single `configuration.nix` vs Dockerfiles + compose + orchestrator
- **Rollback**: Built in `nixos-rebuild switch --rollback` vs manual container management
- **Updates**: `nixos-rebuild switch` applies everything atomically

### Caddy over Nginx

Caddy provides automatic HTTPS via Let's Encrypt with zero configuration. A simple Caddyfile handles reverse proxy, TLS certificates, and renewal. No certbot cron jobs or manual certificate management.

### PocketBase

Single Go binary with embedded SQLite. Each instance runs as a systemd service on its own port with its own data directory. ARM64 builds are officially supported. Memory usage is ~10 to 20MB per idle instance.

## Hetzner Cloud CAX11 Specs

| Resource | Value                  |
| -------- | ---------------------- |
| CPU      | 2 vCPU (Ampere Altra)  |
| RAM      | 4 GB                   |
| Storage  | 40 GB NVMe             |
| Transfer | 20 TB/month            |
| IPv4     | 1 public               |
| IPv6     | /64 subnet             |
| Location | Nuremberg (nbg1)       |
| Price    | €4.75/month (~US$5.05) |

### Estimated resource usage

| Component      | RAM         | CPU (idle) |
| -------------- | ----------- | ---------- |
| NixOS base     | ~150 MB     | minimal    |
| Caddy          | ~30 MB      | minimal    |
| PocketBase × 5 | ~100 MB     | minimal    |
| **Total**      | **~280 MB** | **< 5%**   |

This leaves ~3.7 GB of RAM for growth, caching, and burst traffic.

## Repository Structure

```
postador-infra/
├── README.md
├── .gitignore
├── .envrc                      # direnv for nix shell
├── flake.nix                   # Nix flake for dev tools
├── flake.lock
│
├── tofu/                       # OpenTofu (Terraform) configs
│   ├── main.tf                 # Provider + server resource
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # IP addresses, etc.
│   ├── firewall.tf             # Hetzner firewall rules
│   ├── dns.tf                  # DNS records (optional)
│   └── terraform.tfvars.example
│
├── nixos/                      # NixOS configuration
│   ├── configuration.nix       # Main server config
│   ├── hardware.nix            # Hardware specific (generated)
│   ├── networking.nix          # Network + firewall
│   ├── services/
│   │   ├── caddy.nix           # Caddy reverse proxy config
│   │   └── pocketbase.nix      # PocketBase service definitions
│   └── users.nix               # User accounts + SSH keys
│
├── scripts/
│   ├── bootstrap.sh            # Initial nixos-infect setup
│   ├── deploy.sh               # Push config + rebuild
│   └── backup.sh               # SQLite backup to S3/R2
│
└── docs/
    └── PEP-001-infrastructure.md
```

## Implementation Plan

### Phase 1: Provision (OpenTofu)

OpenTofu creates the Hetzner Cloud resources:

```hcl
# tofu/main.tf
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "default" {
  name       = "postador-deploy"
  public_key = var.ssh_public_key
}

resource "hcloud_firewall" "postador" {
  name = "postador-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "postador" {
  name        = "postador-prod"
  server_type = "cax11"
  location    = "fsn1"
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.default.id]

  firewall_ids = [hcloud_firewall.postador.id]

  user_data = <<-EOF
    #cloud-config
    runcmd:
      - curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | PROVIDER=hetznercloud NIX_CHANNEL=nixos-24.11 bash 2>&1 | tee /tmp/infect.log
  EOF

  lifecycle {
    ignore_changes = [user_data, image]
  }
}
```

```hcl
# tofu/variables.tf
variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}
```

```hcl
# tofu/outputs.tf
output "server_ip" {
  value = hcloud_server.postador.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.postador.ipv6_address
}
```

### Phase 2: Configure (NixOS)

After nixos-infect completes, deploy the NixOS configuration:

```nix
# nixos/configuration.nix
{ config, pkgs, lib, ... }:

let
  # Define PocketBase instances
  pbInstances = {
    postador = { port = 8090; domain = "api.postador.com.br"; };
    # Add more instances as needed:
    # app2 = { port = 8091; domain = "api.app2.com.br"; };
  };

  # PocketBase ARM64 binary
  pocketbase = pkgs.stdenv.mkDerivation rec {
    pname = "pocketbase";
    version = "0.25.9";
    src = pkgs.fetchurl {
      url = "https://github.com/pocketbase/pocketbase/releases/download/v${version}/pocketbase_${version}_linux_arm64.zip";
      sha256 = lib.fakeHash; # Replace with real hash on first build
    };
    nativeBuildInputs = [ pkgs.unzip ];
    unpackPhase = "unzip $src";
    installPhase = ''
      mkdir -p $out/bin
      cp pocketbase $out/bin/
      chmod +x $out/bin/pocketbase
    '';
  };

in {
  imports = [
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ./services/caddy.nix
  ];

  # System basics
  system.stateVersion = "24.11";
  time.timeZone = "America/Sao_Paulo";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    git
    sqlite
  ];

  # Generate PocketBase systemd services
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

        # Hardening
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
```

```nix
# nixos/networking.nix
{ config, ... }:

{
  networking.hostName = "postador-prod";

  # Use systemd-networkd (Hetzner Cloud standard)
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "enp1s0"; # ARM64 interface name
    networkConfig.DHCP = "ipv4";
    address = [
      # Replace with your assigned IPv6
      # "2a01:4f8:xxxx:xxxx::1/64"
    ];
    routes = [
      { Gateway = "fe80::1"; }
    ];
  };

  # NixOS firewall (in addition to Hetzner firewall)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };
}
```

```nix
# nixos/services/caddy.nix
{ config, lib, ... }:

let
  pbInstances = {
    postador = { port = 8090; domain = "api.postador.com.br"; };
  };

  # Generate Caddy virtualHosts from PocketBase instances
  caddyHosts = lib.mapAttrs' (name: cfg:
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
}
```

```nix
# nixos/users.nix
{ config, ... }:

{
  users.users.denis = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # Replace with your actual SSH public key
      "ssh-ed25519 AAAA... denis@workstation"
    ];
  };

  # SSH hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
```

### Phase 3: Deployment Workflow

```bash
#!/usr/bin/env bash
# scripts/deploy.sh
#
# Usage: ./scripts/deploy.sh [switch|test|dry-activate]

set -euo pipefail

SERVER_IP=$(cd tofu && tofu output -raw server_ip)
ACTION="${1:-switch}"

echo "Deploying NixOS config to $SERVER_IP (action: $ACTION)..."

# Sync NixOS config to server
rsync -avz --delete \
  nixos/ \
  "denis@${SERVER_IP}:/etc/nixos/"

# Rebuild remotely
ssh "denis@${SERVER_IP}" \
  "sudo nixos-rebuild ${ACTION}"

echo "Deploy complete!"
```

For CI/CD (optional GitHub Actions):

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
    paths: ["nixos/**"]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy NixOS config
        env:
          SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          SERVER_IP: ${{ secrets.SERVER_IP }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan "$SERVER_IP" >> ~/.ssh/known_hosts

          rsync -avz --delete nixos/ "denis@${SERVER_IP}:/etc/nixos/"
          ssh "denis@${SERVER_IP}" "sudo nixos-rebuild switch"
```

### Phase 4: Backups (Litestream or cron)

SQLite databases can be continuously replicated to S3 compatible storage using Litestream, or backed up on a schedule:

```bash
#!/usr/bin/env bash
# scripts/backup.sh
# Simple cron based SQLite backup to Hetzner Object Storage or Cloudflare R2

set -euo pipefail

BACKUP_DIR="/var/lib/pocketbase-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

for instance_dir in /var/lib/pocketbase/*/; do
  name=$(basename "$instance_dir")
  db_path="${instance_dir}pb_data/data.db"

  if [ -f "$db_path" ]; then
    mkdir -p "${BACKUP_DIR}/${name}"
    sqlite3 "$db_path" ".backup '${BACKUP_DIR}/${name}/data-${TIMESTAMP}.db'"
    echo "Backed up ${name}"
  fi
done

# Optional: sync to S3/R2
# aws s3 sync "$BACKUP_DIR" "s3://postador-backups/" --endpoint-url "$S3_ENDPOINT"
```

## Bootstrapping from Zero

Complete steps to go from nothing to running:

```bash
# 1. Clone the repo
git clone git@github.com:denis/postador-infra.git
cd postador-infra

# 2. Set up secrets
cp tofu/terraform.tfvars.example tofu/terraform.tfvars
# Edit with your Hetzner API token and SSH key

# 3. Provision the server
cd tofu
tofu init
tofu plan
tofu apply
# Note: server will take ~10 minutes to nixos-infect

# 4. Wait for nixos-infect to finish
# Check: ssh root@<ip> -- if you get NixOS welcome, it's done

# 5. Deploy NixOS configuration
cd ..
./scripts/deploy.sh

# 6. Point DNS
# A record: api.postador.com.br -> <server_ip>
# AAAA record: api.postador.com.br -> <server_ipv6>

# 7. Verify
curl https://api.postador.com.br/api/health
```

## Adding a New PocketBase Instance

To add a new app, edit the `pbInstances` attribute set in both `configuration.nix` and `services/caddy.nix`:

```nix
pbInstances = {
  postador = { port = 8090; domain = "api.postador.com.br"; };
  newapp   = { port = 8091; domain = "api.newapp.com.br"; };  # <- add this
};
```

Then deploy:

```bash
./scripts/deploy.sh
```

NixOS will create the new systemd service, data directory, and Caddy virtual host automatically. Caddy will provision a TLS certificate for the new domain within seconds.

## Cost Analysis

| Item                          | Monthly Cost    |
| ----------------------------- | --------------- |
| Hetzner CAX11                 | €4.75 (~R$30)   |
| Domain (amortised)            | ~R$5            |
| Hetzner Object Storage (10GB) | €1.18 (~R$7)    |
| **Total**                     | **~R$42/month** |

Compared to Fly.io at ~R$100+/month for equivalent multi-app setup.

## Latency Considerations

Germany to São Paulo adds ~220ms round trip latency. This is acceptable for Postador AI because:

- AI content generation (the core feature) takes 2 to 10 seconds, dwarfing 220ms
- PocketBase API calls are not latency critical for this use case
- Cloudflare CDN can be added later to cache static assets if needed
- If latency ever becomes a problem, the entire config can be redeployed on a São Paulo VPS (Linode/Vultr/DO at ~$5 to $6/month) by changing one line in OpenTofu

## Security

- SSH key only authentication (no passwords)
- Root login disabled
- PocketBase runs as DynamicUser (no persistent system user)
- systemd service hardening (ProtectSystem, ProtectHome, NoNewPrivileges)
- Hetzner Cloud firewall + NixOS firewall (defense in depth)
- Automatic TLS via Caddy/Let's Encrypt
- Regular SQLite backups
  :w

## Future Improvements

- **Litestream**: Continuous SQLite replication to S3 for point in time recovery
- **Monitoring**: Prometheus + Grafana or simple uptime monitoring (UptimeRobot)
- **Nix Flakes**: Migrate from channel based config to flake for pinned dependencies
- **nixos-anywhere**: Replace nixos-infect with nixos-anywhere for cleaner installs
- **Secrets management**: agenix or sops-nix for encrypted secrets in git
- **Multi-region**: Add a second server in São Paulo if latency becomes an issue

## Decision Log

| Date       | Decision                           | Rationale                                         |
| ---------- | ---------------------------------- | ------------------------------------------------- |
| 2026-02-17 | Hetzner CAX11 over Linode/Vultr/DO | 4GB RAM + 2 vCPU for €4.75 vs 1GB + 1 vCPU for $5 |
| 2026-02-17 | Germany over São Paulo             | 4x resources for same price; latency acceptable   |
| 2026-02-17 | Nuremberg (nbg1) over Falkenstein  | fsn1 CAX11 unavailable; same region, same price   |
| 2026-02-17 | NixOS over Ubuntu + Docker         | Declarative config; ~10x less memory overhead     |
| 2026-02-17 | OpenTofu over Terraform            | Open source (MPL 2.0); 1:1 compatible             |
| 2026-02-17 | Caddy over Nginx                   | Automatic TLS; simpler config                     |
| 2026-02-17 | nixos-infect over ISO install      | Zero downtime provisioning via cloud-init         |

## References

- [NixOS on Hetzner Cloud Wiki](https://wiki.nixos.org/wiki/Install_NixOS_on_Hetzner_Cloud)
- [nixos-infect](https://github.com/elitak/nixos-infect)
- [PocketBase FAQ](https://pocketbase.io/faq/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Hetzner Cloud API](https://docs.hetzner.cloud/)
  type=code&redirect_uri=https%3A%2F%2Fplatform.clau
  de.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreat
  e_api_key+user%3Aprofile+user%3Ainference+user%3As
  essions%3Aclaude_code+user%3Amcp_servers&code_chal
  lenge=54tDFEYdpKBhnl_v2Q3RJFx5i_rtVOxOsqDTYFRLosw&
  code_challenge_method=S256&state=hqkY-2Wh-B-X8tT7Y
  Dqw_OdZDoRJQah4axEBUndtb2g )
