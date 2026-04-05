#!/usr/bin/env bash
# kirobi-machine/play.sh
# Autonomer Starter für das Kirobi KI-System
#
# Verwendung:
#   ./play.sh           → Normal starten
#   ./play.sh --update  → Update + Neustart
#   ./play.sh --debug   → Mit Debug-Ausgabe
#   ./play.sh --stop    → Alle Dienste stoppen
#   ./play.sh --status  → Status anzeigen

set -euo pipefail

# ============================================================
# KONFIGURATION
# ============================================================
KIROBI_HOME="${KIROBI_HOME:-/kirobi}"
KIROBI_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIROBI_CORE_DIR="${KIROBI_REPO_DIR}/kirobi-core"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
LOG_FILE="${KIROBI_HOME}/logs/kirobi.log"
PAPERCLIP_PORT="${PAPERCLIP_PORT:-3000}"

# Farb-Codes für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================
# HILFSFUNKTIONEN
# ============================================================

log() {
  local level="${1}"
  local message="${2}"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  case "${level}" in
    INFO)  echo -e "${GREEN}[${timestamp}] ✅ ${message}${NC}" ;;
    WARN)  echo -e "${YELLOW}[${timestamp}] ⚠️  ${message}${NC}" ;;
    ERROR) echo -e "${RED}[${timestamp}] ❌ ${message}${NC}" >&2 ;;
    DEBUG) [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[${timestamp}] 🔍 ${message}${NC}" || true ;;
    *)     echo -e "[${timestamp}] ${message}" ;;
  esac

  # In Log-Datei schreiben (falls Verzeichnis existiert)
  if [[ -d "$(dirname "${LOG_FILE}")" ]]; then
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
  fi
}

banner() {
  echo -e "${CYAN}${BOLD}"
  cat << 'EOF'
  ██╗  ██╗██╗██████╗  ██████╗ ██████╗ ██╗
  ██║ ██╔╝██║██╔══██╗██╔═══██╗██╔══██╗██║
  █████╔╝ ██║██████╔╝██║   ██║██████╔╝██║
  ██╔═██╗ ██║██╔══██╗██║   ██║██╔══██╗██║
  ██║  ██╗██║██║  ██║╚██████╔╝██████╔╝██║
  ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝
  Disruptive OS V6.0 — Autonomous AI Orchestrator
EOF
  echo -e "${NC}"
}

# ============================================================
# VORAUSSETZUNGEN PRÜFEN
# ============================================================

check_prerequisites() {
  log INFO "Prüfe Voraussetzungen..."

  # Python prüfen
  if ! command -v python3 &>/dev/null; then
    log ERROR "Python 3 nicht gefunden! (nixos-rebuild ausgeführt?)"
    exit 1
  fi
  log DEBUG "Python: $(python3 --version)"

  # Docker prüfen
  if ! command -v docker &>/dev/null; then
    log ERROR "Docker nicht gefunden!"
    exit 1
  fi
  if ! docker info &>/dev/null; then
    log ERROR "Docker-Daemon läuft nicht! Starte: sudo systemctl start docker"
    exit 1
  fi
  log DEBUG "Docker: $(docker --version)"

  # Ollama prüfen
  if ! command -v ollama &>/dev/null; then
    log WARN "Ollama nicht im PATH gefunden, versuche via systemctl..."
  fi

  if ! systemctl is-active --quiet ollama 2>/dev/null; then
    log WARN "Ollama-Service läuft nicht, starte ihn..."
    sudo systemctl start ollama
    sleep 3
  fi

  # Ollama API erreichbar?
  if ! curl -sf "${OLLAMA_HOST}/api/tags" &>/dev/null; then
    log ERROR "Ollama API nicht erreichbar unter ${OLLAMA_HOST}"
    log ERROR "Prüfe: systemctl status ollama"
    exit 1
  fi
  log INFO "Ollama API erreichbar"

  # NVIDIA GPU prüfen
  if command -v nvidia-smi &>/dev/null; then
    local gpu_name
    gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
    log INFO "GPU gefunden: ${gpu_name}"
    local vram
    vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)"
    log DEBUG "VRAM: ${vram}"
  else
    log WARN "nvidia-smi nicht verfügbar — keine GPU-Beschleunigung?"
  fi

  # Kirobi-Verzeichnis prüfen
  if [[ ! -d "${KIROBI_HOME}" ]]; then
    log INFO "Erstelle Kirobi-Verzeichnis: ${KIROBI_HOME}"
    mkdir -p "${KIROBI_HOME}/logs"
    mkdir -p "${KIROBI_HOME}/data"
    mkdir -p "${KIROBI_HOME}/models"
    mkdir -p "${KIROBI_HOME}/workspace"
  fi

  log INFO "Alle Voraussetzungen erfüllt ✓"
}

# ============================================================
# OLLAMA-MODELLE LADEN
# ============================================================

load_ollama_models() {
  log INFO "Prüfe und lade Ollama-Modelle..."

  local models=(
    "llama3.1:8b"          # Schnelles Standard-Modell
    "llama3.1:70b"         # Großes Modell (benötigt ~40GB VRAM)
    "nomic-embed-text"     # Embedding-Modell
    "codellama:13b"        # Code-Modell
  )

  local installed_models
  installed_models="$(curl -sf "${OLLAMA_HOST}/api/tags" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(' '.join(m['name'] for m in data.get('models', [])))
" 2>/dev/null || echo "")"

  for model in "${models[@]}"; do
    if echo "${installed_models}" | grep -q "${model}"; then
      log INFO "Modell bereits vorhanden: ${model}"
    else
      log INFO "Lade Modell: ${model} (kann einige Minuten dauern)..."
      if ollama pull "${model}" 2>&1 | tail -1; then
        log INFO "Modell geladen: ${model}"
      else
        log WARN "Konnte Modell nicht laden: ${model} — überspringe"
      fi
    fi
  done
}

# ============================================================
# PAPERCLIP STARTEN
# ============================================================

start_paperclip() {
  log INFO "Starte Paperclip (Aufgaben-Queue)..."

  # Prüfen ob Paperclip bereits läuft
  if docker ps --format '{{.Names}}' | grep -q "kirobi-paperclip"; then
    log INFO "Paperclip läuft bereits"
    return 0
  fi

  # Paperclip als Docker-Container starten
  docker run -d \
    --name "kirobi-paperclip" \
    --restart unless-stopped \
    -p "${PAPERCLIP_PORT}:3000" \
    -v "${KIROBI_HOME}/data/paperclip:/data" \
    -e "PAPERCLIP_SECRET=$(openssl rand -hex 32)" \
    --network host \
    node:20-alpine \
    sh -c "
      npm install -g paperclip-server 2>/dev/null || true
      paperclip-server --port 3000 --data /data
    " 2>/dev/null || {
      log WARN "Paperclip-Container konnte nicht gestartet werden (optional)"
    }

  log INFO "Paperclip gestartet auf Port ${PAPERCLIP_PORT}"
}

# ============================================================
# PYTHON-ABHÄNGIGKEITEN INSTALLIEREN
# ============================================================

setup_python_env() {
  log INFO "Prüfe Python-Abhängigkeiten..."

  local venv_dir="${KIROBI_HOME}/.venv"

  if [[ ! -d "${venv_dir}" ]]; then
    log INFO "Erstelle Python-Virtualenv..."
    python3 -m venv "${venv_dir}"
  fi

  # Aktiviere venv
  # shellcheck disable=SC1091
  source "${venv_dir}/bin/activate"

  # Abhängigkeiten installieren
  pip install --quiet --upgrade pip
  pip install --quiet \
    ollama \
    httpx \
    pydantic \
    structlog \
    asyncio-mqtt \
    aiofiles \
    typer \
    rich \
    pyyaml

  log INFO "Python-Umgebung bereit"
}

# ============================================================
# KIROBI AGENTLOOP STARTEN
# ============================================================

start_kirobi() {
  log INFO "Starte Kirobi AgentLoop..."

  local venv_dir="${KIROBI_HOME}/.venv"
  local agent_script="${KIROBI_CORE_DIR}/engine/agent_loop.py"

  if [[ ! -f "${agent_script}" ]]; then
    log ERROR "agent_loop.py nicht gefunden: ${agent_script}"
    exit 1
  fi

  # PID-Datei prüfen (läuft Kirobi bereits?)
  local pid_file="${KIROBI_HOME}/kirobi.pid"
  if [[ -f "${pid_file}" ]]; then
    local old_pid
    old_pid="$(cat "${pid_file}")"
    if kill -0 "${old_pid}" 2>/dev/null; then
      log WARN "Kirobi läuft bereits (PID: ${old_pid})"
      return 0
    else
      rm -f "${pid_file}"
    fi
  fi

  # Umgebungsvariablen setzen
  export OLLAMA_HOST="${OLLAMA_HOST}"
  export KIROBI_HOME="${KIROBI_HOME}"
  export KIROBI_CONFIG="${KIROBI_REPO_DIR}/kirobi-core/config.yaml"
  export PYTHONPATH="${KIROBI_CORE_DIR}"

  # Kirobi im Hintergrund starten
  "${venv_dir}/bin/python3" "${agent_script}" \
    >> "${LOG_FILE}" 2>&1 &

  local kirobi_pid=$!
  echo "${kirobi_pid}" > "${pid_file}"

  log INFO "Kirobi gestartet (PID: ${kirobi_pid})"

  # Kurz warten und prüfen ob er noch läuft
  sleep 2
  if kill -0 "${kirobi_pid}" 2>/dev/null; then
    log INFO "Kirobi läuft stabil ✓"
  else
    log ERROR "Kirobi ist sofort beendet — prüfe Logs: ${LOG_FILE}"
    exit 1
  fi
}

# ============================================================
# HERMES AGENT STARTEN
# ============================================================

start_hermes() {
  log INFO "Starte Hermes Kommunikationsagent..."

  local hermes_script="${KIROBI_CORE_DIR}/engine/hermes_agent.py"

  # Falls Hermes-Script nicht existiert, überspringen
  if [[ ! -f "${hermes_script}" ]]; then
    log WARN "Hermes-Script nicht gefunden — überspringe"
    return 0
  fi

  local venv_dir="${KIROBI_HOME}/.venv"
  export KIROBI_HOME="${KIROBI_HOME}"
  export PYTHONPATH="${KIROBI_CORE_DIR}"

  "${venv_dir}/bin/python3" "${hermes_script}" \
    >> "${KIROBI_HOME}/logs/hermes.log" 2>&1 &

  log INFO "Hermes gestartet (PID: $!)"
}

# ============================================================
# STATUS ANZEIGEN
# ============================================================

show_status() {
  echo -e "\n${BOLD}═══════════════════════════════════════${NC}"
  echo -e "${BOLD}   🤖 KIROBI STATUS DASHBOARD${NC}"
  echo -e "${BOLD}═══════════════════════════════════════${NC}\n"

  # Ollama Status
  if systemctl is-active --quiet ollama 2>/dev/null; then
    echo -e "  Ollama:     ${GREEN}● Läuft${NC}"
    local model_count
    model_count="$(curl -sf "${OLLAMA_HOST}/api/tags" | python3 -c "
import json, sys; d=json.load(sys.stdin); print(len(d.get('models',[])))
" 2>/dev/null || echo "?")"
    echo -e "  Modelle:    ${CYAN}${model_count} geladen${NC}"
  else
    echo -e "  Ollama:     ${RED}● Gestoppt${NC}"
  fi

  # Kirobi Status
  local pid_file="${KIROBI_HOME}/kirobi.pid"
  if [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
    echo -e "  Kirobi:     ${GREEN}● Läuft (PID: $(cat "${pid_file}"))${NC}"
  else
    echo -e "  Kirobi:     ${RED}● Gestoppt${NC}"
  fi

  # Docker Status
  if docker info &>/dev/null; then
    local container_count
    container_count="$(docker ps -q | wc -l)"
    echo -e "  Docker:     ${GREEN}● Läuft${NC} (${container_count} Container)"
  else
    echo -e "  Docker:     ${RED}● Gestoppt${NC}"
  fi

  # GPU Status
  if command -v nvidia-smi &>/dev/null; then
    local gpu_util
    gpu_util="$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | head -1 | tr -d ' %')"
    local vram_used
    vram_used="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null | head -1)"
    echo -e "  GPU:        ${GREEN}● ${gpu_util}% Auslastung${NC} | VRAM: ${vram_used}"
  fi

  echo ""
  echo -e "  Logs:       ${KIROBI_HOME}/logs/kirobi.log"
  echo -e "  Config:     ${KIROBI_REPO_DIR}/kirobi-core/config.yaml"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════${NC}\n"
}

# ============================================================
# ALLE DIENSTE STOPPEN
# ============================================================

stop_all() {
  log INFO "Stoppe alle Kirobi-Dienste..."

  # Kirobi stoppen
  local pid_file="${KIROBI_HOME}/kirobi.pid"
  if [[ -f "${pid_file}" ]]; then
    local pid
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" 2>/dev/null; then
      kill -SIGTERM "${pid}"
      log INFO "Kirobi gestoppt (PID: ${pid})"
    fi
    rm -f "${pid_file}"
  fi

  # Paperclip stoppen
  if docker ps --format '{{.Names}}' | grep -q "kirobi-paperclip"; then
    docker stop kirobi-paperclip
    docker rm kirobi-paperclip
    log INFO "Paperclip gestoppt"
  fi

  log INFO "Alle Dienste gestoppt"
}

# ============================================================
# UPDATE
# ============================================================

do_update() {
  log INFO "Starte Update..."

  # Dienste stoppen
  stop_all

  # Git-Repository aktualisieren
  if [[ -d "${KIROBI_REPO_DIR}/.git" ]]; then
    log INFO "Aktualisiere Repository..."
    git -C "${KIROBI_REPO_DIR}" pull --ff-only
  fi

  # NixOS-System aktualisieren
  log INFO "Aktualisiere NixOS-System (flake update)..."
  cd "${KIROBI_REPO_DIR}/kirobi-machine"
  nix flake update
  sudo nixos-rebuild switch --flake .#kirobi-machine

  # Neu starten
  log INFO "Starte Kirobi neu..."
  main_start
}

# ============================================================
# HAUPTFUNKTION
# ============================================================

main_start() {
  banner
  check_prerequisites
  load_ollama_models
  start_paperclip
  setup_python_env
  start_kirobi
  start_hermes
  show_status
  log INFO "Kirobi ist bereit! 🚀"
}

# ============================================================
# ARGUMENT-VERARBEITUNG
# ============================================================

case "${1:-}" in
  --stop)
    stop_all
    ;;
  --status)
    show_status
    ;;
  --update)
    do_update
    ;;
  --debug)
    export DEBUG=true
    main_start
    ;;
  ""|--start)
    main_start
    ;;
  *)
    echo "Verwendung: $0 [--start|--stop|--status|--update|--debug]"
    exit 1
    ;;
esac
