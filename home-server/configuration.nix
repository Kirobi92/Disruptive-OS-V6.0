# home-server/configuration.nix
# Vollständige NixOS-Konfiguration des Home-Servers
# Storage: 2× 1 TB NVMe SSD (ZFS Mirror "tank") + 2 TB HDD (ZFS "backup")
#
# ANPASSEN VOR VERWENDUNG:
#   - boot.loader.grub.device    → Dein Boot-Laufwerk
#   - networking.interfaces      → Dein Netzwerkinterface
#   - fileSystems                → Deine Partitions-UUIDs
#   - services.nextcloud.hostName → Deine lokale Domain
#   - users.users.*.hashedPassword → Mit `mkpasswd -m sha-512` generieren
#   - age.secrets.* → Secrets mit agenix verschlüsseln
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    # ./hardware-configuration.nix  # nach `nixos-generate-config` einkommentieren
  ];

  # ============================================================
  # BOOTLOADER
  # ============================================================
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 10;
    };

    kernelPackages = pkgs.linuxPackages_latest;

    # ZFS-Unterstützung
    supportedFilesystems = [ "zfs" ];
    kernelParams = [ "zfs.zfs_arc_max=8589934592" ]; # ARC max 8 GB

    # ZFS-Pool beim Boot importieren
    zfs.extraPools = [ "tank" "backup" ];
    zfs.devNodes = "/dev/disk/by-id";
  };

  # ============================================================
  # DATEISYSTEM
  # ============================================================
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/YYYY-YYYY";
      fsType = "vfat";
    };
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/SWAP-UUID"; }
  ];

  # ============================================================
  # ZFS KONFIGURATION
  # ============================================================
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly"; # Monatliches Scrubbing
    };
    autoSnapshot = {
      enable = true;
      frequent = 4;   # Alle 15 Minuten, 4 behalten
      hourly = 24;    # Stündlich, 24 behalten
      daily = 7;      # Täglich, 7 behalten
      weekly = 4;     # Wöchentlich, 4 behalten
      monthly = 12;   # Monatlich, 12 behalten
    };
  };

  # ZFS-Mounts für alle Datasets
  fileSystems."/mnt/tank" = {
    device = "tank";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  fileSystems."/mnt/tank/private/sven" = {
    device = "tank/private/sven";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  fileSystems."/mnt/tank/private/samira" = {
    device = "tank/private/samira";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  fileSystems."/mnt/tank/private/sineo" = {
    device = "tank/private/sineo";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  fileSystems."/mnt/tank/shared/family" = {
    device = "tank/shared/family";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  fileSystems."/mnt/tank/kirobi" = {
    device = "tank/kirobi";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  fileSystems."/mnt/backup" = {
    device = "backup";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" ];
  };

  # ============================================================
  # NETZWERK
  # ============================================================
  networking = {
    hostName = "home-server";
    hostId = "ABCD1234"; # Für ZFS: `head -c 8 /etc/machine-id`

    networkmanager.enable = true;

    # Statische IP (empfohlen für Server)
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.168.1.10";
        prefixLength = 24;
      }];
    };

    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" "1.1.1.1" "8.8.8.8" ];

    # Firewall
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22    # SSH
        80    # HTTP (Redirect zu HTTPS)
        443   # HTTPS (Nextcloud)
        2049  # NFS
        2283  # Immich
        7575  # Homarr Dashboard
        8096  # Jellyfin
        9000  # MinIO S3 API
        9001  # MinIO Console
      ];
      allowedUDPPorts = [
        2049  # NFS
      ];
    };
  };

  # ============================================================
  # BENUTZER
  # ============================================================
  users = {
    mutableUsers = false;

    groups = {
      family = { };
      kirobi = { };
    };

    users = {
      # Administrator: sven
      sven = {
        isNormalUser = true;
        description = "Sven — Family Admin";
        extraGroups = [ "wheel" "family" "kirobi" "networkmanager" ];
        openssh.authorizedKeys.keys = [
          # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... sven@kirobi-machine"
        ];
        hashedPassword = "CHANGEME";
        shell = pkgs.bash;
      };

      # Familienmitglied: samira
      samira = {
        isNormalUser = true;
        description = "Samira";
        extraGroups = [ "family" ];
        hashedPassword = "CHANGEME";
        shell = pkgs.bash;
      };

      # Familienmitglied: sineo
      sineo = {
        isNormalUser = true;
        description = "Sineo";
        extraGroups = [ "family" ];
        hashedPassword = "CHANGEME";
        shell = pkgs.bash;
      };

      root = {
        hashedPassword = "!";
      };
    };
  };

  security.sudo.wheelNeedsPassword = true;

  # ============================================================
  # NEXTCLOUD
  # ============================================================
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud29;
    hostName = "cloud.home";  # Lokale Domain (in /etc/hosts eintragen)
    https = true;

    # Datenbank (PostgreSQL — performanter als SQLite)
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      adminpassFile = "/run/secrets/nextcloud-admin-password";  # via agenix
      # Datenspeicher auf ZFS
      datadir = "/mnt/tank/kirobi/nextcloud/data";
    };

    settings = {
      # Vertrauenswürdige Domains
      trusted_domains = [ "cloud.home" "192.168.1.10" "*.ts.net" ];
      # Performance
      maintenance_window_start = 2;
      default_phone_region = "DE";
    };

    # Maximale Upload-Größe
    maxUploadSize = "10G";

    # Automatische Zertifikate (selbst-signiert für lokale Domain)
    # Für echte Zertifikate: Let's Encrypt via ACME konfigurieren
  };

  # PostgreSQL für Nextcloud
  services.postgresql.enable = true;
  services.postgresql.ensureDatabases = [ "nextcloud" ];

  # Redis für Nextcloud-Caching
  services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
  };

  # ============================================================
  # IMMICH — Foto & Video Management
  # ============================================================
  services.immich = {
    enable = true;
    port = 2283;
    host = "0.0.0.0";
    # Medien auf ZFS speichern
    mediaLocation = "/mnt/tank/kirobi/immich";
    # PostgreSQL
    database.enable = true;
    # Machine Learning (Gesichtserkennung)
    machine-learning.enable = true;
  };

  # ============================================================
  # JELLYFIN — Medienserver
  # ============================================================
  services.jellyfin = {
    enable = true;
    user = "jellyfin";
    group = "jellyfin";
    # HTTP-Port
    openFirewall = true;
  };

  # Jellyfin Mediendaten auf ZFS
  systemd.tmpfiles.rules = [
    "d /mnt/tank/shared/family/media 0775 jellyfin family -"
    "d /mnt/tank/shared/family/media/filme 0775 jellyfin family -"
    "d /mnt/tank/shared/family/media/serien 0775 jellyfin family -"
    "d /mnt/tank/shared/family/media/musik 0775 jellyfin family -"
  ];

  # ============================================================
  # MINIO — S3-kompatibler Objektspeicher
  # ============================================================
  services.minio = {
    enable = true;
    # Datenspeicher auf ZFS
    dataDir = [ "/mnt/tank/kirobi/minio" ];
    # Konfigurationsverzeichnis
    configDir = "/var/lib/minio/config";
    # Ports
    listenAddress = ":9000";
    consoleAddress = ":9001";
    # Root-Credentials (via Secrets in Produktion!)
    rootCredentialsFile = "/run/secrets/minio-credentials";
  };

  # ============================================================
  # NFS — Netzwerkdateisystem
  # ============================================================
  services.nfs.server = {
    enable = true;
    exports = ''
      # Familienspeicher für alle lokalen Clients
      /mnt/tank/shared/family  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

      # Kirobi-Speicher für KI-Maschine
      /mnt/tank/kirobi         192.168.1.5(rw,sync,no_subtree_check,no_root_squash)

      # Private Bereiche (nur der jeweilige Client)
      # /mnt/tank/private/sven  192.168.1.5(rw,sync,no_subtree_check,root_squash)
    '';
    # NFS Version 4
    nfsd.nproc = 8;
  };

  # ============================================================
  # HOMARR — Dashboard
  # ============================================================
  # Homarr via Docker (noch nicht nativ in NixOS verfügbar)
  virtualisation.docker.enable = true;

  virtualisation.oci-containers.containers = {
    homarr = {
      image = "ghcr.io/ajnart/homarr:latest";
      autoStart = true;
      ports = [ "7575:7575" ];
      volumes = [
        "/var/lib/homarr/configs:/app/data/configs"
        "/var/lib/homarr/icons:/app/public/icons"
        "/var/lib/homarr/data:/data"
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
      environment = {
        DEFAULT_COLOR_SCHEME = "dark";
        TZ = "Europe/Berlin";
      };
    };
  };

  # ============================================================
  # TAILSCALE VPN
  # ============================================================
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    # Optional: Als Exit-Node konfigurieren
    # extraUpFlags = [ "--advertise-exit-node" ];
  };

  # ============================================================
  # SSH
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };

  # ============================================================
  # SYSTEM-PAKETE
  # ============================================================
  environment.systemPackages = with pkgs; [
    # Basis
    git wget curl htop btop neovim tmux
    # ZFS-Werkzeuge
    zfs zfstools sanoid
    # Netzwerk
    nfs-utils
    # Diagnose
    iotop nethogs nload
    # Nix
    nix-tree nixpkgs-fmt
    # Sonstige
    rsync rclone
  ];

  # ============================================================
  # NIX-KONFIGURATION
  # ============================================================
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkN8ET8iAivaKBY4XPPO0="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # ============================================================
  # LOKALISIERUNG
  # ============================================================
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";
  console.keyMap = "de";

  # ============================================================
  # PERFORMANCE
  # ============================================================
  boot.kernel.sysctl = {
    "vm.swappiness" = 1;  # ZFS verwaltet Speicher selbst
    "vm.dirty_ratio" = 40;
    "vm.dirty_background_ratio" = 10;
    # Netzwerk-Optimierungen
    "net.core.rmem_max" = 67108864;
    "net.core.wmem_max" = 67108864;
  };

  # NixOS State-Version
  system.stateVersion = "24.11";
}
