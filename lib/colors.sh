#!/usr/bin/env bash
# ================================================================
#  lib/colors.sh
#  Variables de colores ANSI y funciones de logging reutilizables
#  Debe ser el primer módulo en cargarse (todos los demás dependen de él)
# ================================================================

# ─── Colores ANSI ────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Funciones de logging ─────────────────────────────────────
log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_step()    { echo -e "\n${BOLD}${MAGENTA}▶ $*${RESET}"; }
log_divider() { echo -e "${DIM}────────────────────────────────────────────${RESET}"; }