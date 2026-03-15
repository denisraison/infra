{ pkgs, ... }:

{
  # Ensure secrets directory and files are readable by the authelia-main user
  systemd.tmpfiles.rules = [
    "d /etc/authelia-secrets 0750 root authelia-main -"
    "z /etc/authelia-secrets/* 0400 authelia-main authelia-main -"
  ];

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = "/etc/authelia-secrets/jwt_secret";
      storageEncryptionKeyFile = "/etc/authelia-secrets/storage_encryption_key";
      oidcHmacSecretFile = "/etc/authelia-secrets/hmac_secret";
      oidcIssuerPrivateKeyFile = "/etc/authelia-secrets/oidc.key";
    };

    settings = {
      theme = "dark";
      server.address = "tcp://127.0.0.1:9091";
      server.asset_path = "${./assets}";
      log.level = "info";

      authentication_backend.file.path = "${./users.yml}";
      authentication_backend.file.search.email = true;

      session.cookies = [
        {
          domain = "raison.dev";
          authelia_url = "https://id.raison.dev";
        }
      ];

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      notifier.filesystem.filename = "/var/lib/authelia-main/notifications.log";

      access_control.default_policy = "one_factor";

      identity_providers.oidc = {
        clients = [
          {
            client_id = "tailscale";
            client_name = "Tailscale";
            client_secret = "$pbkdf2-sha512$310000$1nqSxFp8QJcu0Jz1nNRN6A$A7IFcUylENza99rlvARrJdBI0v4JFwh5h6Iaroo.U6QpXJ3EPeUM/mMnB2FyvtmicjjSzbKzLpRdVkN/YYlzCQ";
            authorization_policy = "one_factor";
            redirect_uris = [ "https://login.tailscale.com/a/oauth_response" ];
            scopes = [ "openid" "email" "profile" ];
            grant_types = [ "authorization_code" ];
            response_types = [ "code" ];
            require_pkce = false;
          }
        ];
      };
    };
  };
}
