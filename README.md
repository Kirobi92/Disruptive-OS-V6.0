# 🤖 Disruptive OS V6.0 — Kirobi

> **Ein vollständig autonomes, lokal-first KI-Betriebssystem auf NixOS-Basis**

[![NixOS](https://img.shields.io/badge/NixOS-24.11-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![ZFS](https://img.shields.io/badge/Storage-ZFS-003366?logo=openzfs&logoColor=white)](https://openzfs.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📋 Inhaltsverzeichnis

1. [Projektübersicht](#projektübersicht)
2. [Hardware-Architektur](#hardware-architektur)
3. [Repository-Struktur](#repository-struktur)
4. [Getting Started — KI-Maschine](#getting-started--ki-maschine)
5. [Getting Started — Home-Server](#getting-started--home-server)
6. [ZFS-Speicherlayout](#zfs-speicherlayout)
7. [Dienste & Zugriff](#dienste--zugriff)
8. [Kirobi KI-System](#kirobi-ki-system)
9. [Netzwerk & Tailscale](#netzwerk--tailscale)
10. [Wartung & Updates](#wartung--updates)

---

## 🚀 Projektübersicht

**Disruptive OS V6.0** ist ein vollständig deklarativ konfiguriertes, reproduzierbares Betriebssystem auf Basis von NixOS. Es betreibt **Kirobi** — einen autonomen, lokal-first KI-Super-Orchestrator, der vollständig ohne Cloud-Abhängigkeit läuft.

### Kernprinzipien

| Prinzip | Beschreibung |
|---|---|
| **Lokal-First** | Alle KI-Berechnungen laufen on-premise auf der RTX 3090 |
| **Deklarativ** | Gesamte Infrastruktur als Nix-Code — reproduzierbar, versionierbar |
| **Privat** | Keine Daten verlassen das Heimnetzwerk (außer über Tailscale VPN) |
| **Autonom** | Kirobi kann eigenständig Aufgaben planen und ausführen |
| **Familien-tauglich** | Private Bereiche pro Person + gemeinsamer Familienspeicher |

---

## 🖥️ Hardware-Architektur

### Maschine 1: KI-Maschine (`kirobi-machine`)

```
┌─────────────────────────────────────────────────────┐
│                   KI-MASCHINE                       │
│                                                     │
│  CPU:  AMD Ryzen 9 5900X (12C/24T, 3.7–4.8 GHz)   │
│  GPU:  NVIDIA RTX 3090 (24 GB GDDR6X, 10496 CUDA)  │
│  RAM:  (empfohlen: 64 GB DDR4)                     │
│  OS:   NixOS 24.11                                  │
│                                                     │
│  Dienste:                                           │
│  ├── Kirobi Super-Orchestrator                      │
│  ├── Ollama (CUDA-beschleunigt)                     │
│  ├── Docker / Podman                                │
│  └── AgentLoop + 4-Quadranten-Engine               │
└─────────────────────────────────────────────────────┘
```

### Maschine 2: Home-Server (`home-server`)

```
┌─────────────────────────────────────────────────────┐
│                  HOME-SERVER                        │
│                                                     │
│  Storage:  2× 1 TB NVMe SSD (ZFS Mirror = "tank")  │
│            1× 2 TB HDD (ZFS = "backup")             │
│  OS:       NixOS 24.11                              │
│                                                     │
│  Dienste:                                           │
│  ├── Nextcloud  (Dateisync & Kalender)              │
│  ├── Immich     (Fotos & Videos)                    │
│  ├── Jellyfin   (Medienserver)                      │
│  ├── MinIO      (S3-kompatibler Objektspeicher)     │
│  ├── NFS        (Netzwerkdateisystem)               │
│  └── Homarr     (Dashboard)                         │
└─────────────────────────────────────────────────────┘
```

---

## 📁 Repository-Struktur

```
Disruptive-OS-V6.0/
│
├── README.md                          ← Diese Datei
├── LICENSE                            ← MIT-Lizenz
├── .gitignore                         ← Optimiert für NixOS + KI
├── .copilot-instructions.md           ← GitHub Copilot Anweisungen
├── copilot-rules.yaml                 ← Copilot Regelwerk
├── Disruptive_OS_V6_Dokumentation.md  ← Zentrale Dokumentation
│
├── kirobi-machine/                    ← KI-Maschine (Ryzen 9 + RTX 3090)
│   ├── flake.nix                      ← Nix Flake (Einstiegspunkt)
│   ├── configuration.nix              ← Vollständige NixOS-Konfiguration
│   └── play.sh                        ← Autonomer Kirobi-Starter
│
├── home-server/                       ← Home-Server (ZFS + Dienste)
│   ├── flake.nix                      ← Nix Flake (Einstiegspunkt)
│   ├── configuration.nix              ← Vollständige NixOS-Konfiguration
│   └── setup-zfs.sh                   ← ZFS Datasets anlegen
│
└── kirobi-core/                       ← Kirobi KI-Kern
    ├── config.yaml                    ← Hardware-Optimierung RTX 3090
    └── engine/
        └── agent_loop.py              ← AgentLoop + 4-Quadranten-Engine
```

---

## 🛠️ Getting Started — KI-Maschine

### Voraussetzungen

- Frisch installiertes NixOS 24.11 (minimales ISO)
- NVIDIA RTX 3090 eingebaut
- Internetverbindung für den ersten Setup

### Schritt 1: Repository klonen

```bash
# Als root oder mit sudo
nix-shell -p git

git clone https://github.com/Kirobi92/Disruptive-OS-V6.0.git /etc/nixos/disruptive-os
cd /etc/nixos/disruptive-os
```

### Schritt 2: Hardware-Konfiguration anpassen

```bash
# Deine Hardware-IDs ermitteln
lsblk -f          # Disk-UUIDs
ip a              # Netzwerk-Interfaces

# Passe kirobi-machine/configuration.nix an:
# - networking.hostName
# - boot.loader.grub.device
# - networking.interfaces
```

### Schritt 3: NixOS rebuilden

```bash
cd /etc/nixos/disruptive-os/kirobi-machine

# Symlink setzen
ln -sf $(pwd)/configuration.nix /etc/nixos/configuration.nix

# System bauen und aktivieren
nixos-rebuild switch --flake .#kirobi-machine
```

### Schritt 4: Kirobi starten

```bash
# Als User 'sven' einloggen, dann:
cd /etc/nixos/disruptive-os/kirobi-machine
chmod +x play.sh
./play.sh
```

---

## 🏠 Getting Started — Home-Server

### Voraussetzungen

- Frisch installiertes NixOS 24.11
- 2× 1 TB NVMe SSDs (für ZFS Mirror)
- 1× 2 TB HDD (für ZFS Backup)
- Internetverbindung

### Schritt 1: Repository klonen

```bash
nix-shell -p git
git clone https://github.com/Kirobi92/Disruptive-OS-V6.0.git /etc/nixos/disruptive-os
cd /etc/nixos/disruptive-os
```

### Schritt 2: ZFS Pools anlegen

```bash
cd /etc/nixos/disruptive-os/home-server

# Disk-IDs ermitteln
ls -la /dev/disk/by-id/

# setup-zfs.sh anpassen (Disk-IDs eintragen), dann:
chmod +x setup-zfs.sh
sudo ./setup-zfs.sh
```

### Schritt 3: NixOS konfigurieren und rebuilden

```bash
# Hardware-Konfiguration anpassen
# - boot.loader.grub.device
# - networking.hostName
# - services.nextcloud.hostName

nixos-rebuild switch --flake .#home-server
```

### Schritt 4: Services überprüfen

```bash
systemctl status nextcloud
systemctl status immich
systemctl status jellyfin
systemctl status minio
```

---

## 💾 ZFS-Speicherlayout

```
tank (ZFS Mirror: 2× 1 TB NVMe)
├── tank/private/
│   ├── tank/private/sven      → Nur Sven hat Zugriff (700)
│   ├── tank/private/samira    → Nur Samira hat Zugriff (700)
│   └── tank/private/sineo     → Nur Sineo hat Zugriff (700)
├── tank/shared/
│   └── tank/shared/family     → Alle Familienmitglieder (770)
└── tank/kirobi                → KI-dedizierter Bereich (750)

backup (ZFS: 2 TB HDD)
└── backup/snapshots           → Automatische ZFS-Snapshots
```

### Zugriffsrechte

| Bereich | Benutzer | Berechtigungen |
|---|---|---|
| `tank/private/sven` | sven | rwx------ (700) |
| `tank/private/samira` | samira | rwx------ (700) |
| `tank/private/sineo` | sineo | rwx------ (700) |
| `tank/shared/family` | sven, samira, sineo | rwxrwx--- (770) |
| `tank/kirobi` | sven, kirobi-service | rwxr-x--- (750) |

---

## 🌐 Dienste & Zugriff

| Dienst | Port | URL | Beschreibung |
|---|---|---|---|
| **Homarr** | 7575 | http://home-server:7575 | Dashboard |
| **Nextcloud** | 443 | https://cloud.home | Dateisync |
| **Immich** | 2283 | http://home-server:2283 | Fotos/Videos |
| **Jellyfin** | 8096 | http://home-server:8096 | Medienserver |
| **MinIO** | 9000/9001 | http://home-server:9000 | S3-Speicher |
| **NFS** | 2049 | — | Netzwerkdateisystem |

---

## 🧠 Kirobi KI-System

Kirobi ist ein autonomer Super-Orchestrator mit folgenden Komponenten:

### AgentLoop

Der AgentLoop ist das Herzstück — er verarbeitet Aufgaben in einem kontinuierlichen Zyklus:

```
Eingabe → Analyse → Planung → Ausführung → Reflexion → Loop
```

### 4-Quadranten-Engine

Aufgaben werden nach Priorität und Aufwand klassifiziert:

```
         WICHTIG
            │
   Q2       │    Q1
 Wichtig,   │  Wichtig,
 nicht      │  dringend
 dringend   │
────────────┼──────────── DRINGEND
   Q4       │    Q3
 Nicht      │  Dringend,
 wichtig,   │  nicht
 nicht      │  wichtig
 dringend   │
            │
      NICHT WICHTIG
```

### Self-Improvement-Loop

Kirobi analysiert seine eigene Performance und optimiert Prompts, Modellauswahl und Ressourcennutzung automatisch.

### Hermes Agent

Zuständig für Kommunikation und Benachrichtigungen (E-Mail, Webhooks, lokale Notifications).

---

## 🔒 Netzwerk & Tailscale

Tailscale ermöglicht sicheren Remote-Zugriff auf alle Dienste:

```bash
# Tailscale aktivieren (nach nixos-rebuild)
sudo tailscale up

# Status prüfen
tailscale status
```

Alle Dienste sind nur im lokalen Netzwerk und über Tailscale erreichbar — kein direktes Port-Forwarding ins Internet.

---

## 🔄 Wartung & Updates

### NixOS Updates

```bash
# Flake-Inputs aktualisieren
nix flake update

# System neu bauen
nixos-rebuild switch --flake .#kirobi-machine
# oder
nixos-rebuild switch --flake .#home-server
```

### ZFS Snapshots

```bash
# Manueller Snapshot
zfs snapshot tank@manual-$(date +%Y%m%d)

# Snapshots anzeigen
zfs list -t snapshot

# Rollback (mit Vorsicht!)
zfs rollback tank@snapshot-name
```

### Kirobi Update

```bash
cd /kirobi
git pull
./play.sh --update
```

---

## 👥 Benutzer

| Benutzer | Gruppe | Beschreibung |
|---|---|---|
| `sven` | wheel, docker, kirobi | Hauptadministrator + KI-Zugriff |
| `samira` | family | Familienmitglied |
| `sineo` | family | Familienmitglied |

---

## 📄 Lizenz

MIT License — siehe [LICENSE](LICENSE)

---

*Disruptive OS V6.0 — Kirobi | Erstellt mit ❤️ und NixOS*
