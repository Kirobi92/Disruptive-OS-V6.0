#!/usr/bin/env bash
# home-server/setup-zfs.sh
# Skript zum Anlegen aller ZFS-Pools und Datasets für den Home-Server
#
# ⚠️  WARNUNG: Dieses Skript formatiert Festplatten!
#    Nur auf einem FRISCH installierten System ohne wichtige Daten ausführen!
#
# Verwendung:
#   1. Disk-IDs anpassen (siehe Abschnitt KONFIGURATION unten)
#   2. sudo ./setup-zfs.sh
#
# Disk-IDs ermitteln:
#   ls -la /dev/disk/by-id/

set -euo pipefail

# ============================================================
# KONFIGURATION — HIER ANPASSEN!
# ============================================================

# NVMe SSDs für den ZFS Mirror "tank" (2× 1 TB)
# Beispiel: "nvme-Samsung_SSD_970_EVO_1TB_S4EWNX0M123456"
TANK_DISK1="nvme-DISK1_SERIAL_HERE"
TANK_DISK2="nvme-DISK2_SERIAL_HERE"

# HDD für Backup-Pool "backup" (2 TB)
# Beispiel: "ata-WDC_WD20EZAZ-00GGJB0_WD-WX..."
BACKUP_DISK="ata-BACKUP_DISK_SERIAL_HERE"

# Benutzer-UIDs (müssen mit configuration.nix übereinstimmen)
SVEN_UID="1000"
SAMIRA_UID="1001"
SINEO_UID="1002"

# Gruppen-GID
FAMILY_GID="1001"
KIROBI_GID="1002"

# ============================================================
# FARB-AUSGABE
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ ${1}${NC}"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  ${1}${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ❌ ${1}${NC}" >&2; exit 1; }
info()  { echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️  ${1}${NC}"; }
step()  { echo -e "\n${BOLD}═══ ${1} ═══${NC}"; }

# ============================================================
# SICHERHEITSPRÜFUNG
# ============================================================

check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "Dieses Skript muss als root ausgeführt werden: sudo ./setup-zfs.sh"
  fi
}

check_disk_ids() {
  step "Prüfe Disk-IDs"

  local errors=0

  if [[ "${TANK_DISK1}" == "nvme-DISK1_SERIAL_HERE" ]]; then
    warn "TANK_DISK1 ist noch nicht angepasst!"
    ((errors++))
  fi

  if [[ "${TANK_DISK2}" == "nvme-DISK2_SERIAL_HERE" ]]; then
    warn "TANK_DISK2 ist noch nicht angepasst!"
    ((errors++))
  fi

  if [[ "${BACKUP_DISK}" == "ata-BACKUP_DISK_SERIAL_HERE" ]]; then
    warn "BACKUP_DISK ist noch nicht angepasst!"
    ((errors++))
  fi

  if [[ "${errors}" -gt 0 ]]; then
    echo ""
    info "Verfügbare Disks (ls /dev/disk/by-id/):"
    ls -la /dev/disk/by-id/ | grep -v "part" | grep -v "^total" | awk '{print "  " $NF}'
    echo ""
    error "Bitte passe die Disk-IDs im Skript an (Abschnitt KONFIGURATION)"
  fi

  # Disk-Existenz prüfen
  for disk in "${TANK_DISK1}" "${TANK_DISK2}" "${BACKUP_DISK}"; do
    if [[ ! -e "/dev/disk/by-id/${disk}" ]]; then
      error "Disk nicht gefunden: /dev/disk/by-id/${disk}"
    fi
  done

  log "Alle Disk-IDs gefunden"
}

confirm_destructive_action() {
  step "⚠️  SICHERHEITSABFRAGE"
  echo ""
  echo -e "${RED}${BOLD}ACHTUNG: Dieses Skript wird folgende Disks FORMATIEREN:${NC}"
  echo -e "  Tank-Disk 1:  ${YELLOW}/dev/disk/by-id/${TANK_DISK1}${NC}"
  echo -e "  Tank-Disk 2:  ${YELLOW}/dev/disk/by-id/${TANK_DISK2}${NC}"
  echo -e "  Backup-Disk:  ${YELLOW}/dev/disk/by-id/${BACKUP_DISK}${NC}"
  echo ""
  echo -e "${RED}Alle Daten auf diesen Disks werden UNWIEDERBRINGLICH gelöscht!${NC}"
  echo ""
  read -r -p "Tippe 'JA ICH BIN SICHER' zum Fortfahren: " confirm
  if [[ "${confirm}" != "JA ICH BIN SICHER" ]]; then
    info "Abgebrochen."
    exit 0
  fi
  echo ""
}

# ============================================================
# ZFS POOL "TANK" ERSTELLEN (Mirror)
# ============================================================

create_tank_pool() {
  step "Erstelle ZFS-Pool 'tank' (Mirror)"

  # Prüfen ob Pool bereits existiert
  if zpool list tank &>/dev/null 2>&1; then
    warn "Pool 'tank' existiert bereits — überspringe Erstellung"
    return 0
  fi

  # ZFS Mirror-Pool erstellen
  zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O xattr=sa \
    -O compression=lz4 \
    -O atime=off \
    -O relatime=on \
    -O normalization=formD \
    -O canmount=off \
    -O mountpoint=none \
    tank mirror \
    "/dev/disk/by-id/${TANK_DISK1}" \
    "/dev/disk/by-id/${TANK_DISK2}"

  log "ZFS-Pool 'tank' erstellt (Mirror: ${TANK_DISK1} + ${TANK_DISK2})"

  # Pool-Status anzeigen
  zpool status tank
}

# ============================================================
# ZFS POOL "BACKUP" ERSTELLEN (Single HDD)
# ============================================================

create_backup_pool() {
  step "Erstelle ZFS-Pool 'backup' (HDD)"

  if zpool list backup &>/dev/null 2>&1; then
    warn "Pool 'backup' existiert bereits — überspringe Erstellung"
    return 0
  fi

  zpool create \
    -o ashift=12 \
    -O acltype=posixacl \
    -O xattr=sa \
    -O compression=gzip-6 \
    -O atime=off \
    -O canmount=off \
    -O mountpoint=none \
    backup \
    "/dev/disk/by-id/${BACKUP_DISK}"

  log "ZFS-Pool 'backup' erstellt (Single: ${BACKUP_DISK})"
  zpool status backup
}

# ============================================================
# TANK DATASETS ERSTELLEN
# ============================================================

create_tank_datasets() {
  step "Erstelle tank Datasets"

  # ─── Private Bereiche ────────────────────────────────────
  info "Erstelle private Datasets..."

  # tank/private (Eltern-Dataset — kein direkter Zugriff)
  zfs create \
    -o mountpoint=/mnt/tank/private \
    -o canmount=off \
    tank/private 2>/dev/null || true

  # sven's privater Bereich
  zfs create \
    -o mountpoint=/mnt/tank/private/sven \
    -o quota=200G \
    -o compression=lz4 \
    tank/private/sven
  chown "${SVEN_UID}:${SVEN_UID}" /mnt/tank/private/sven
  chmod 700 /mnt/tank/private/sven
  log "Dataset erstellt: tank/private/sven (200 GB Quota, nur sven)"

  # samira's privater Bereich
  zfs create \
    -o mountpoint=/mnt/tank/private/samira \
    -o quota=200G \
    -o compression=lz4 \
    tank/private/samira
  chown "${SAMIRA_UID}:${SAMIRA_UID}" /mnt/tank/private/samira
  chmod 700 /mnt/tank/private/samira
  log "Dataset erstellt: tank/private/samira (200 GB Quota, nur samira)"

  # sineo's privater Bereich
  zfs create \
    -o mountpoint=/mnt/tank/private/sineo \
    -o quota=200G \
    -o compression=lz4 \
    tank/private/sineo
  chown "${SINEO_UID}:${SINEO_UID}" /mnt/tank/private/sineo
  chmod 700 /mnt/tank/private/sineo
  log "Dataset erstellt: tank/private/sineo (200 GB Quota, nur sineo)"

  # ─── Gemeinsamer Familienspeicher ────────────────────────
  info "Erstelle shared Datasets..."

  zfs create \
    -o mountpoint=/mnt/tank/shared \
    -o canmount=off \
    tank/shared 2>/dev/null || true

  zfs create \
    -o mountpoint=/mnt/tank/shared/family \
    -o quota=300G \
    -o compression=lz4 \
    tank/shared/family
  chown "root:${FAMILY_GID}" /mnt/tank/shared/family
  chmod 770 /mnt/tank/shared/family
  log "Dataset erstellt: tank/shared/family (300 GB Quota, Familiengruppe)"

  # Media-Unterordner für Jellyfin
  mkdir -p /mnt/tank/shared/family/media/{filme,serien,musik,fotos}
  chown -R "root:${FAMILY_GID}" /mnt/tank/shared/family/media
  chmod -R 775 /mnt/tank/shared/family/media

  # ─── KI-Bereich ──────────────────────────────────────────
  info "Erstelle Kirobi Dataset..."

  zfs create \
    -o mountpoint=/mnt/tank/kirobi \
    -o quota=250G \
    -o compression=lz4 \
    -o recordsize=1M \
    tank/kirobi
  chown "${SVEN_UID}:${KIROBI_GID}" /mnt/tank/kirobi
  chmod 750 /mnt/tank/kirobi
  log "Dataset erstellt: tank/kirobi (250 GB Quota, sven + kirobi-Gruppe)"

  # Kirobi-Unterverzeichnisse
  local kirobi_dirs=(
    "nextcloud/data"
    "immich"
    "minio"
    "ollama/models"
    "workspace"
    "backups"
  )

  for dir in "${kirobi_dirs[@]}"; do
    mkdir -p "/mnt/tank/kirobi/${dir}"
    log "  Verzeichnis: /mnt/tank/kirobi/${dir}"
  done

  chown -R "${SVEN_UID}:${KIROBI_GID}" /mnt/tank/kirobi
  chmod -R 750 /mnt/tank/kirobi
}

# ============================================================
# BACKUP DATASETS ERSTELLEN
# ============================================================

create_backup_datasets() {
  step "Erstelle backup Datasets"

  # Snapshots-Dataset für automatische ZFS-Snapshots
  zfs create \
    -o mountpoint=/mnt/backup \
    -o compression=gzip-9 \
    backup/snapshots 2>/dev/null || true

  zfs create \
    -o mountpoint=/mnt/backup/tank \
    backup/snapshots/tank 2>/dev/null || true

  log "Backup-Datasets erstellt"
}

# ============================================================
# AUTOMATISCHE SNAPSHOTS KONFIGURIEREN
# ============================================================

configure_snapshots() {
  step "Konfiguriere automatische ZFS-Snapshots"

  # Snapshots für alle wichtigen Datasets aktivieren
  local datasets=(
    "tank/private/sven"
    "tank/private/samira"
    "tank/private/sineo"
    "tank/shared/family"
    "tank/kirobi"
  )

  for dataset in "${datasets[@]}"; do
    zfs set com.sun:auto-snapshot=true "${dataset}"
    log "Auto-Snapshot aktiviert: ${dataset}"
  done

  # Backup-Pool von Auto-Snapshots ausnehmen
  zfs set com.sun:auto-snapshot=false backup

  info "Snapshot-Zeitplan (via NixOS services.zfs.autoSnapshot):"
  info "  Alle 15 Min: 4 behalten"
  info "  Stündlich:   24 behalten"
  info "  Täglich:     7 behalten"
  info "  Wöchentlich: 4 behalten"
  info "  Monatlich:   12 behalten"
}

# ============================================================
# STATUS ZUSAMMENFASSUNG
# ============================================================

show_summary() {
  step "📊 ZFS Setup Zusammenfassung"

  echo ""
  echo -e "${BOLD}Pool-Status:${NC}"
  zpool list
  echo ""

  echo -e "${BOLD}Dataset-Übersicht:${NC}"
  zfs list -o name,used,avail,quota,mountpoint -r tank
  echo ""
  zfs list -o name,used,avail,quota,mountpoint -r backup
  echo ""

  echo -e "${BOLD}Berechtigungen:${NC}"
  ls -la /mnt/tank/private/
  ls -la /mnt/tank/shared/
  ls -la /mnt/tank/ | grep kirobi
  echo ""

  echo -e "${GREEN}${BOLD}✅ ZFS Setup erfolgreich abgeschlossen!${NC}"
  echo ""
  echo -e "Nächste Schritte:"
  echo -e "  1. Führe 'nixos-rebuild switch --flake .#home-server' aus"
  echo -e "  2. Überprüfe Dienste: systemctl status nextcloud immich jellyfin"
  echo -e "  3. Aktiviere Tailscale: sudo tailscale up"
  echo ""
}

# ============================================================
# HAUPTPROGRAMM
# ============================================================

main() {
  echo -e "${BOLD}"
  echo "╔══════════════════════════════════════════╗"
  echo "║   ZFS Setup — Disruptive OS V6.0         ║"
  echo "║   Home-Server Storage Initialisierung    ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${NC}"

  check_root
  check_disk_ids
  confirm_destructive_action

  create_tank_pool
  create_backup_pool
  create_tank_datasets
  create_backup_datasets
  configure_snapshots

  show_summary
}

main "$@"
