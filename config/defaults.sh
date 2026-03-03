#!/usr/bin/env bash
# ================================================================
#  config/defaults.sh
#  Constantes globales del tool: versión, límites, valores por defecto
#  Cargado después de colors.sh, antes de cualquier módulo lib/
# ================================================================

# ─── Versión del tool ────────────────────────────────────────
PR_AUTHOR_VERSION="1.0"

# ─── Límites de líneas capturadas del diff para la IA ────────
DIFF_STAT_LINES=30          # git diff --stat en el commit
DIFF_NAME_STATUS_LINES=40   # git diff --name-status en el commit
PR_DIFF_STAT_LINES=40       # git diff --stat del PR completo
PR_DIFF_NAME_STATUS_LINES=50 # git diff --name-status del PR completo
PR_LOG_LINES=10             # commits incluidos en Key Changes Summary

# ─── Límites del título generado por IA ─────────────────────
AI_TITLE_MIN_LEN=5
AI_TITLE_MAX_LEN=100

# ─── Ticket por defecto si no se encuentra en la rama ────────
DEFAULT_TICKET="MTX8-DEFAULT"

# ─── Directorio temporal para el body del PR ─────────────────
PR_BODY_TMP_PREFIX="/tmp/pr-body-tempo.md"