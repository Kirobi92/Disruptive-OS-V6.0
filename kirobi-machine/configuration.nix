# kirobi-machine/configuration.nix
# Vollständige NixOS-Konfiguration der KI-Maschine
# Hardware: AMD Ryzen 9 5900X + NVIDIA RTX 3090 (24 GB VRAM)
#
# ANPASSEN VOR VERWENDUNG:
#   - boot.loader.grub.device  → Dein Boot-Laufwerk (z.B. "/dev/nvme0n1")
#   - networking.interfaces    → Dein Netzwerkinterface (z.B. "enp4s0")
#   - fileSystems."/"          → Deine Root-Partition UUID
#   - users.users.sven.hashedPassword → Mit `mkpasswd` generieren
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    # Hardware-Scan-Ergebnis (nach `nixos-generate-config` erstellt)
    # ./hardware-configuration.nix
  ];

  # ============================================================
  # BOOTLOADER
  # ============================================================
  boot = {
    # GRUB2 (UEFI-Modus)
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot";
      # Maximale Anzahl der gespeicherten Generationen
      systemd-boot.configurationLimit = 10;
    };

    # Aktueller Kernel für beste AMD/NVIDIA-Unterstützung
    kernelPackages = pkgs.linuxPackages_latest;

    # Kernel-Parameter für NVIDIA und Performance
    kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "nvidia-drm.modeset=1"
      "transparent_hugepage=always"
    ];

    # Kernel-Module
    kernelModules = [ "kvm-amd" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
    extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

    # Initrd-Module für frühen GPU-Zugriff
    initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  };

  # ============================================================
  # DATEISYSTEM
  # ============================================================
  fileSystems = {
    # Root-Partition (UUID anpassen!)
    "/" = {
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" ];
    };

    # EFI-Partition
    "/boot" = {
      device = "/dev/disk/by-uuid/YYYY-YYYY";
      fsType = "vfat";
    };

    # Kirobi-Arbeitsverzeichnis (separates Laufwerk oder Partition)
    "/kirobi" = {
      device = "/dev/disk/by-uuid/ZZZZZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZZZZZZZZZ";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" "nofail" ];
    };
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/SWAP-UUID"; }
  ];

  # ============================================================
  # NETZWERK
  # ============================================================
  networking = {
    hostName = "kirobi-machine";

    # NetworkManager für einfache Netzwerkverwaltung
    networkmanager.enable = true;

    # Firewall
    firewall = {
      enable = true;
      # Ollama API (nur lokal)
      allowedTCPPorts = [ 11434 ];
      # SSH
      allowedTCPPorts = [ 22 ];
    };
  };

  # ============================================================
  # NVIDIA GPU — RTX 3090
  # ============================================================
  hardware = {
    # NVIDIA Proprietäre Treiber (für maximale CUDA-Leistung)
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      # Proprietäre Treiber (nicht Open-Source) — notwendig für RTX 3090 CUDA
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # OpenGL für GPU-Beschleunigung
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        vaapiVdpau
        libvdpau-va-gl
      ];
    };

    # Allgemeine Hardware-Unterstützung
    enableAllFirmware = true;
    cpu.amd.updateMicrocode = true;
  };

  # Grafiktreiber auf NVIDIA setzen
  services.xserver.videoDrivers = [ "nvidia" ];

  # ============================================================
  # DOCKER
  # ============================================================
  virtualisation.docker = {
    enable = true;
    # NVIDIA Container Runtime für GPU-Zugriff in Containern
    enableNvidia = true;
    daemon.settings = {
      # Standard-Logging-Treiber
      log-driver = "journald";
      # Storage-Treiber
      storage-driver = "overlay2";
    };
  };

  # NVIDIA Container Toolkit
  hardware.nvidia-container-toolkit.enable = true;

  # ============================================================
  # OLLAMA — Lokaler LLM-Server mit CUDA
  # ============================================================
  services.ollama = {
    enable = true;
    # CUDA-Beschleunigung aktivieren
    acceleration = "cuda";
    # Ollama lauscht auf allen Interfaces (für Netzwerkzugriff)
    host = "0.0.0.0";
    port = 11434;
    # Modelle im Kirobi-Verzeichnis speichern
    home = "/kirobi/ollama";
    # Umgebungsvariablen für CUDA-Optimierung
    environmentVariables = {
      OLLAMA_NUM_PARALLEL = "4";        # Parallele Anfragen
      OLLAMA_MAX_LOADED_MODELS = "2";   # Gleichzeitig geladene Modelle
      CUDA_VISIBLE_DEVICES = "0";       # RTX 3090 als primäre GPU
    };
  };

  # ============================================================
  # SYSTEMDIENSTE
  # ============================================================
  services = {
    # SSH-Server
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
      };
    };

    # Zeitzone
    timesyncd.enable = true;

    # Tailscale VPN
    tailscale = {
      enable = true;
      useRoutingFeatures = "client";
    };
  };

  # ============================================================
  # SYSTEM-PAKETE
  # ============================================================
  environment.systemPackages = with pkgs; [
    # Basis-Werkzeuge
    git
    wget
    curl
    htop
    btop
    nvtop          # GPU-Monitoring
    neovim
    tmux
    ripgrep
    fd
    jq
    yq

    # NVIDIA-Werkzeuge
    nvtopPackages.nvidia
    cudatoolkit

    # Python für Kirobi
    python311
    python311Packages.pip
    python311Packages.virtualenv

    # Docker-Werkzeuge
    docker-compose
    lazydocker

    # Nix-Werkzeuge
    nix-tree
    nix-diff
    nixpkgs-fmt

    # Kirobi-spezifische Pakete
    ollama
    nodejs  # Für Paperclip
  ];

  # ============================================================
  # BENUTZER
  # ============================================================
  users = {
    # Unveränderliche Benutzer (kein adduser/useradd)
    mutableUsers = false;

    # Benutzergruppen
    groups = {
      family = { };
      kirobi = { };
    };

    users = {
      # Hauptbenutzer: sven
      sven = {
        isNormalUser = true;
        description = "Sven — Hauptadministrator & KI-Operator";
        # Gruppen: wheel (sudo), docker, video (GPU), kirobi
        extraGroups = [ "wheel" "docker" "video" "audio" "networkmanager" "kirobi" "family" ];
        # SSH Public Key (eigenen Key eintragen!)
        openssh.authorizedKeys.keys = [
          # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... sven@desktop"
        ];
        # Gehashtes Passwort: mit `mkpasswd -m sha-512` generieren
        hashedPassword = "CHANGEME";
        shell = pkgs.bash;
      };

      # Root deaktivieren (nur sudo)
      root = {
        hashedPassword = "!";  # Deaktiviert direktes root-Login
      };
    };
  };

  # Sudo ohne Passwort für wheel (optional, sicherer: mit Passwort)
  security.sudo.wheelNeedsPassword = true;

  # ============================================================
  # SYSTEMD-SERVICES: KIROBI
  # ============================================================
  systemd.services.kirobi = {
    description = "Kirobi Autonomous AI Orchestrator";
    after = [ "network.target" "ollama.service" "docker.service" ];
    wants = [ "ollama.service" ];
    wantedBy = [ ];  # Nicht automatisch starten — manuell via play.sh

    serviceConfig = {
      Type = "simple";
      User = "sven";
      WorkingDirectory = "/kirobi";
      ExecStart = "${pkgs.python311}/bin/python3 /kirobi/kirobi-core/engine/agent_loop.py";
      Restart = "on-failure";
      RestartSec = "10s";
      # Umgebungsvariablen
      Environment = [
        "OLLAMA_HOST=http://localhost:11434"
        "KIROBI_HOME=/kirobi"
        "PYTHONPATH=/kirobi/kirobi-core"
      ];
      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "kirobi";
    };
  };

  # ============================================================
  # NIX-KONFIGURATION
  # ============================================================
  nix = {
    settings = {
      # Experimentelle Features aktivieren (Flakes, nix-command)
      experimental-features = [ "nix-command" "flakes" ];
      # Auto-Optimierung des Nix-Stores
      auto-optimise-store = true;
      # Substituter für schnellere Downloads
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkN8ET8iAivaKBY4XPPO0="
      ];
    };
    # Garbage Collection
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
  i18n = {
    defaultLocale = "de_DE.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "de_DE.UTF-8";
      LC_IDENTIFICATION = "de_DE.UTF-8";
      LC_MEASUREMENT = "de_DE.UTF-8";
      LC_MONETARY = "de_DE.UTF-8";
      LC_NAME = "de_DE.UTF-8";
      LC_NUMERIC = "de_DE.UTF-8";
      LC_PAPER = "de_DE.UTF-8";
      LC_TELEPHONE = "de_DE.UTF-8";
      LC_TIME = "de_DE.UTF-8";
    };
  };

  # Tastaturlayout
  console.keyMap = "de";

  # ============================================================
  # PERFORMANCE-OPTIMIERUNGEN
  # ============================================================
  # CPU-Frequenz-Skalierung auf Performance setzen
  powerManagement.cpuFreqGovernor = "performance";

  # Kernel-Sysctl-Optimierungen für KI-Workloads
  boot.kernel.sysctl = {
    # Speicher-Optimierungen
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 60;
    "vm.dirty_background_ratio" = 5;
    # Netzwerk-Optimierungen für lokale KI-API
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
  };

  # NixOS State-Version (NICHT ÄNDERN nach erster Installation!)
  system.stateVersion = "24.11";
}
