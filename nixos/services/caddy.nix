{ ... }:

{
  services.caddy = {
    enable = true;

    virtualHosts."id.raison.dev".extraConfig = ''
      reverse_proxy localhost:9091
    '';

    virtualHosts."raison.dev".extraConfig = ''
      handle /.well-known/webfinger {
        header Content-Type application/jrd+json
        respond `{"subject":"{query.resource}","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://id.raison.dev"}]}` 200
      }

      respond "Nothing here" 404
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
