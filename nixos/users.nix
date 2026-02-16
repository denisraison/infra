{ ... }:

{
  users.users.denis = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIqQ0w0mze9GFhnC+pOHQEKYp0Ycj+V0jFRxtiscNpYe deeraison@gmail.com"
    ];
  };

  # Keep root SSH access during setup, can disable later
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIqQ0w0mze9GFhnC+pOHQEKYp0Ycj+V0jFRxtiscNpYe deeraison@gmail.com"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
