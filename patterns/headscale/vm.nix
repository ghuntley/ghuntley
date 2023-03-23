{ pkgs, lib, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
  services.openssh.enable = true;

  environment.systemPackages = [
    pkgs.curl
    pkgs.git
    pkgs.tailscale
    pkgs.nix
  ];

  nixos-shell.mounts = {
    mountHome = false;
    mountNixProfile = false;
    cache = "none"; # default is "loose"
  };

  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
  ];

  users.users.root = {
    # Password is "linux"
    hashedPassword = lib.mkForce "$6$VbYV0ad/Zmrx3mFz$2ywvFQ/fSOG.dbUCaImGUIg9gLi/BKnKzYhbO.rWLedq82GrzpIoSoi3hZm950kJy3FpcM0bcDbGwvbx4aLve1";
  };

  services.tailscale.enable = true;

  services.headscale.enable = true;
  services.headscale.derp.autoUpdate = true;
  services.headscale.derp.updateFrequency = "5m";
  services.headscale.ephemeralNodeInactivityTimeout = "30m";
  services.headscale.database.type = "sqlite3";
  services.headscale.dns.magicDns = true;
  services.headscale.dns.baseDomain = "ts.ghuntley.net";
  # services.headscale.tls.letsencrypt.hostname = "ts.ghuntley.net";
}
