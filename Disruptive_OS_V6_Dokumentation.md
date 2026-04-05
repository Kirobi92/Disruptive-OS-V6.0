# 📚 Disruptive OS V6.0 — Zentrale Dokumentation

> **Version:** 6.0 | **Stand:** 2024 | **Maintainer:** sven

---

## Inhaltsverzeichnis

1. [Projektstruktur](#1-projektstruktur)
2. [Root-Dateien](#2-root-dateien)
3. [KI-Maschine (kirobi-machine/)](#3-ki-maschine-kirobi-machine)
4. [Home-Server (home-server/)](#4-home-server-home-server)
5. [Kirobi Core (kirobi-core/)](#5-kirobi-core-kirobi-core)
6. [Einrichtungsreihenfolge](#6-einrichtungsreihenfolge)
7. [Häufige Befehle](#7-häufige-befehle)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Projektstruktur

```
Disruptive-OS-V6.0/
├── README.md
├── LICENSE
├── .gitignore
├── .copilot-instructions.md
├── copilot-rules.yaml
├── Disruptive_OS_V6_Dokumentation.md    ← Diese Datei
│
├── kirobi-machine/
│   ├── flake.nix
│   ├── configuration.nix
│   └── play.sh
│
├── home-server/
│   ├── flake.nix
│   ├── configuration.nix
│   └── setup-zfs.sh
│
└── kirobi-core/
    ├── config.yaml
    └── engine/
        └── agent_loop.py
```

---

## 2. Root-Dateien

### `README.md`
Haupt-Readme des Projekts. Enthält:
- Projektübersicht und Philosophie
- Hardware-Architektur beider Maschinen
- Step-by-Step Getting-Started für KI-Maschine und Home-Server
- ZFS-Speicherlayout-Dokumentation
- Dienste-Übersicht mit Ports
- Netzwerk/Tailscale-Erklärung

### `LICENSE`
MIT-Lizenz. Das Projekt kann frei genutzt, modifiziert und verbreitet werden.

### `.gitignore`
Optimiert für:
- NixOS (result/, .direnv/, *.drv)
- Python (__pycache__, venv/, dist/)
- KI/ML Dateien (*.gguf, *.bin, *.safetensors — zu groß für Git)
- Secrets (*.key, *.pem, .env — NIEMALS committen)
- Editoren (.vscode/settings.json, .idea/)

### `.copilot-instructions.md`
Anweisungen für GitHub Copilot, damit er zum Projektstil passende Vorschläge macht:
- Nix-Flakes-First
- Python-Typisierung und Async
- Sicherheitsrichtlinien
- Lokaler Fokus (keine Cloud-Dienste)

### `copilot-rules.yaml`
Maschinenlesbare Regeln für Copilot und CI-Tools:
- Alle Nix/NixOS-Konventionen
- ZFS-Dataset-Struktur
- Service-Konfigurationen
- Kirobi KI-System-Parameter

---

## 3. KI-Maschine (`kirobi-machine/`)

### `kirobi-machine/flake.nix`
**Zweck:** Nix Flake als Einstiegspunkt für die KI-Maschine.

**Enthält:**
- `inputs`: nixpkgs 24.11, nixos-hardware, home-manager
- `outputs`: NixOS-Konfiguration `kirobi-machine`
- NVIDIA-spezifische Hardware-Module aus nixos-hardware
- Home-Manager-Integration für User `sven`

**Verwendung:**
```bash
nixos-rebuild switch --flake .#kirobi-machine
```

### `kirobi-machine/configuration.nix`
**Zweck:** Vollständige NixOS-Systemkonfiguration der KI-Maschine.

**Wichtige Konfigurationsbereiche:**
| Bereich | Details |
|---|---|
| Bootloader | GRUB2, EFI oder Legacy |
| Netzwerk | NetworkManager, Hostname: `kirobi-machine` |
| NVIDIA | Proprietäre Treiber, CUDA, power management |
| Ollama | Docker-Service mit CUDA-Beschleunigung |
| Docker | Service aktiviert, User `sven` in Docker-Gruppe |
| User `sven` | wheel, docker, video, audio, kirobi |
| Dateisystem | `/kirobi` gemountet auf dediziertem Speicher |
| Firewall | Aktiviert, nur nötige Ports offen |

**NVIDIA-Konfiguration (kritisch):**
```nix
hardware.nvidia = {
  modesetting.enable = true;
  powerManagement.enable = false;
  open = false;  # Proprietäre Treiber für maximale CUDA-Leistung
  nvidiaSettings = true;
  package = config.boot.kernelPackages.nvidiaPackages.stable;
};
```

### `kirobi-machine/play.sh`
**Zweck:** Autonomer Starter-Script für das Kirobi-System.

**Aktionen:**
1. Prüft Voraussetzungen (Docker, GPU, Ollama)
2. Lädt benötigte Ollama-Modelle (falls nicht vorhanden)
3. Startet den Paperclip-Service (Aufgaben-Queue)
4. Initialisiert und startet den Kirobi AgentLoop
5. Startet den Hermes-Kommunikationsagenten
6. Zeigt Status-Dashboard

**Verwendung:**
```bash
cd /kirobi
./play.sh           # Normal starten
./play.sh --update  # Update + Neustart
./play.sh --debug   # Mit Debug-Ausgabe
./play.sh --stop    # Alle Dienste stoppen
```

---

## 4. Home-Server (`home-server/`)

### `home-server/flake.nix`
**Zweck:** Nix Flake als Einstiegspunkt für den Home-Server.

**Enthält:**
- `inputs`: nixpkgs 24.11, nixos-hardware, home-manager, agenix (Secrets)
- `outputs`: NixOS-Konfiguration `home-server`
- Nextcloud, Immich, Jellyfin, MinIO, NFS, Homarr Module

**Verwendung:**
```bash
nixos-rebuild switch --flake .#home-server
```

### `home-server/configuration.nix`
**Zweck:** Vollständige NixOS-Systemkonfiguration des Home-Servers.

**Wichtige Konfigurationsbereiche:**

| Dienst | Port | Konfiguration |
|---|---|---|
| Nextcloud | 443 | HTTPS, lokale Domain, PostgreSQL |
| Immich | 2283 | Docker-Container, Media-Path |
| Jellyfin | 8096 | Native NixOS-Service |
| MinIO | 9000/9001 | S3-kompatibel, Console |
| NFS | 2049 | Exports für lokales Netzwerk |
| Homarr | 7575 | Dashboard |
| Tailscale | — | VPN |

**User-Konfiguration:**
```nix
users.users = {
  sven    = { isNormalUser = true; extraGroups = ["wheel" "family" "kirobi"]; };
  samira  = { isNormalUser = true; extraGroups = ["family"]; };
  sineo   = { isNormalUser = true; extraGroups = ["family"]; };
};
```

### `home-server/setup-zfs.sh`
**Zweck:** Skript zum einmaligen Anlegen aller ZFS-Pools und Datasets.

**⚠️ WARNUNG:** Dieses Skript formatiert Festplatten! Nur auf einem frischen System ausführen!

**Aktionen:**
1. Erstellt ZFS-Pool "tank" (Mirror aus 2 NVMe-Drives)
2. Erstellt ZFS-Pool "backup" (Single HDD)
3. Legt alle Datasets an (private, shared, kirobi)
4. Setzt Berechtigungen und Ownership
5. Konfiguriert automatische Snapshots
6. Aktiviert Komprimierung und Deduplizierung

**Verwendung:**
```bash
# Disk-IDs anpassen, dann:
sudo ./setup-zfs.sh

# Überprüfen:
zpool status
zfs list
```

---

## 5. Kirobi Core (`kirobi-core/`)

### `kirobi-core/config.yaml`
**Zweck:** Zentrale Konfiguration des Kirobi-Systems, optimiert für RTX 3090.

**Enthält:**
- Hardware-Profile (GPU, CUDA, VRAM)
- Modell-Konfigurationen (Ollama-Modelle, Kontextgröße)
- Performance-Tuning (Batch-Size, Thread-Count)
- AgentLoop-Parameter
- 4-Quadranten-Schwellenwerte
- Hermes-Kommunikations-Einstellungen

### `kirobi-core/engine/agent_loop.py`
**Zweck:** Kernkomponente des Kirobi-Systems — der autonome AgentLoop.

**Klassen:**

| Klasse | Beschreibung |
|---|---|
| `Task` | Datenklasse für eine einzelne Aufgabe mit Priorität, Status, Quadrant |
| `QuadrantClassifier` | Klassifiziert Aufgaben in die 4 Eisenhower-Quadranten |
| `KirobiBrain` | Schnittstelle zu Ollama (lokales LLM) |
| `AgentLoop` | Hauptschleife — plant, priorisiert und führt Aufgaben aus |
| `HermesAgent` | Kommunikationsagent für Benachrichtigungen |
| `SelfImprovementLoop` | Analysiert Performance und optimiert Parameter |

**Wichtige Methoden:**

```python
# AgentLoop
async def run()              # Startet die Hauptschleife
async def add_task(task)     # Fügt eine Aufgabe hinzu
async def process_task(task) # Verarbeitet eine einzelne Aufgabe
async def reflect()          # Reflexionsschritt nach jeder Aufgabe

# QuadrantClassifier
def classify(task) -> Quadrant   # Bestimmt den Quadranten
def prioritize(tasks) -> list    # Sortiert nach Priorität

# KirobiBrain
async def think(prompt) -> str   # Sendet Prompt an Ollama
async def plan(goal) -> list     # Erstellt Aufgabenplan für ein Ziel
```

---

## 6. Einrichtungsreihenfolge

### Empfohlene Reihenfolge für Ersteinrichtung:

```
1. Home-Server einrichten
   ├── NixOS installieren
   ├── setup-zfs.sh ausführen (ZFS-Pools anlegen)
   ├── nixos-rebuild switch --flake .#home-server
   └── Dienste überprüfen

2. KI-Maschine einrichten
   ├── NixOS installieren
   ├── nixos-rebuild switch --flake .#kirobi-machine
   ├── Ollama-Modelle laden
   └── play.sh ausführen

3. Netzwerk konfigurieren
   ├── Tailscale auf beiden Maschinen aktivieren
   ├── NFS-Mount auf KI-Maschine testen
   └── Homarr-Dashboard konfigurieren
```

---

## 7. Häufige Befehle

### NixOS

```bash
# System rebuilden
nixos-rebuild switch --flake .#kirobi-machine
nixos-rebuild switch --flake .#home-server

# Rollback auf vorherige Generation
nixos-rebuild --rollback switch

# Generationen anzeigen
nix-env --list-generations --profile /nix/var/nix/profiles/system

# Garbage Collection
nix-collect-garbage -d

# Flake-Inputs aktualisieren
nix flake update
```

### ZFS

```bash
# Pool-Status
zpool status
zpool status tank
zpool status backup

# Datasets anzeigen
zfs list
zfs list -r tank

# Snapshot erstellen
zfs snapshot tank/kirobi@vor-update-$(date +%Y%m%d)

# Snapshots anzeigen
zfs list -t snapshot

# Snapshot wiederherstellen
zfs rollback tank/kirobi@vor-update-20240101

# Automatische Snapshots (zfs-auto-snapshot)
systemctl status zfs-auto-snapshot-daily
```

### Ollama

```bash
# Modelle anzeigen
ollama list

# Modell laden
ollama pull llama3.1:70b
ollama pull codellama:34b
ollama pull nomic-embed-text

# Modell testen
ollama run llama3.1:70b "Hallo Kirobi!"

# GPU-Nutzung prüfen
nvidia-smi
```

### Dienste (Home-Server)

```bash
# Status aller Dienste
systemctl status nextcloud
systemctl status immich
systemctl status jellyfin
systemctl status minio
systemctl status nfs-server

# Logs anzeigen
journalctl -u nextcloud -f
journalctl -u immich -f
```

---

## 8. Troubleshooting

### NVIDIA/CUDA funktioniert nicht

```bash
# NVIDIA-Treiber prüfen
nvidia-smi
lsmod | grep nvidia

# CUDA-Test
python3 -c "import torch; print(torch.cuda.is_available())"

# Ollama GPU-Nutzung prüfen
ollama run llama3.1:8b "test"
# In einem anderen Terminal:
watch -n1 nvidia-smi
```

### ZFS-Pool nicht importiert

```bash
# Alle verfügbaren Pools anzeigen
zpool import

# Pool manuell importieren
sudo zpool import tank
sudo zpool import backup

# Pool-Status nach Import
zpool status
```

### Nextcloud-Probleme

```bash
# Nextcloud-OCC Befehle
sudo -u nextcloud nextcloud-occ status
sudo -u nextcloud nextcloud-occ maintenance:mode --on
sudo -u nextcloud nextcloud-occ maintenance:repair
sudo -u nextcloud nextcloud-occ maintenance:mode --off
```

### NFS-Mount-Probleme

```bash
# NFS-Exports prüfen
exportfs -v

# Mount testen
showmount -e home-server
sudo mount -t nfs home-server:/mnt/tank/shared/family /mnt/family

# Firewall-Ports prüfen (auf Home-Server)
iptables -L -n | grep 2049
```

### Kirobi startet nicht

```bash
# Logs prüfen
journalctl -u kirobi -f
cat /var/log/kirobi/agent_loop.log

# Ollama-Status prüfen
systemctl status ollama
ollama ps

# Python-Umgebung prüfen
python3 --version
pip3 list | grep ollama
```

---

*Disruptive OS V6.0 Dokumentation | Stand: 2024*
