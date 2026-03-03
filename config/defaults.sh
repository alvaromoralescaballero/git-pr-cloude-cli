#version del tool
PR_AUTHOR_VERSION="1.0"

#limites del diff para la IA
DIFF_STAT_LINES=30
DISS_NAME_STATUS_LINES=40
PR_DIFF_STAT_LINES=40
PR_DIFF_NAME_STATUS_LINES=50


#Limites del titulo generado por la IA en este caso cloude
AI_TITLE_MIN_LEN=5
AI_TITLE_MAX_LN=100

# ─── Ticket por defecto si no se encuentra en la rama ────────
DEFAULT_TICKET="MTX8-DEFAULT"

# ─── Directorio temporal para el body del PR ─────────────────
PR_BODY_TMP_PREFIX="/tmp/pr-body-tempo.md"