#!/usr/bin/env bash
# ================================================================
#  lib/pr_create.sh
#  FASE 8 — Preview y confirmación del PR
#  FASE 9 — Crear el PR en GitHub via gh CLI
#
#  Lee:
#    PR_TITLE, TARGET_BRANCH, CURRENT_BRANCH, FLOW_LABEL
#    FILES_MODIFIED, LINES_ADDED, LINES_REMOVED
#    BODY_FILE   (generado por lib/pr_body.sh)
# ================================================================

phase_create_pr() {
  # ── FASE 8: Preview y confirmación ────────────────────────
  echo ""
  log_divider
  echo -e "${BOLD}📋 RESUMEN DEL PULL REQUEST${RESET}"
  log_divider
  echo -e "  ${CYAN}Título  :${RESET} ${PR_TITLE}"
  echo -e "  ${CYAN}Base    :${RESET} ${TARGET_BRANCH}"
  echo -e "  ${CYAN}Head    :${RESET} ${CURRENT_BRANCH}"
  echo -e "  ${CYAN}Flujo   :${RESET} ${FLOW_LABEL}"
  echo -e "  ${CYAN}Stats   :${RESET} ${FILES_MODIFIED} archivos · +${LINES_ADDED} / -${LINES_REMOVED}"
  log_divider
  echo ""

  # Opción de ver el body completo antes de confirmar
  read -r -p "$(echo -e "${DIM}¿Ver el body completo antes de crear el PR? [y/N]: ${RESET}")" PREVIEW_CHOICE
  if [[ "${PREVIEW_CHOICE}" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}──── BODY ────${RESET}"
    cat "${BODY_FILE}"
    echo -e "${YELLOW}──────────────${RESET}"
    echo ""
  fi

  # Confirmación final antes de crear el PR
  read -r -p "$(echo -e "${BOLD}¿Crear el PR? [y/N]: ${RESET}")" CONFIRM
  if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    log_warn "PR cancelado. El commit y push ya fueron realizados en origin/${CURRENT_BRANCH}."
    rm -f "${BODY_FILE}"
    exit 0
  fi

  # ── FASE 9: Crear el PR en GitHub ─────────────────────────
  log_step "Creando Pull Request en GitHub..."

  PR_CREATE_OUTPUT=""
  PR_CREATE_RESULT=0
  PR_CREATE_OUTPUT="$(gh pr create \
    --base "${TARGET_BRANCH}" \
    --head "${CURRENT_BRANCH}" \
    --title "${PR_TITLE}" \
    --body-file "${BODY_FILE}" \
    --draft=false 2>&1)" || PR_CREATE_RESULT=$?

  # Limpiar archivo temporal independientemente del resultado
  rm -f "${BODY_FILE}"

  if [[ ${PR_CREATE_RESULT} -ne 0 ]]; then
    log_error "Falló la creación del PR:"
    echo "${PR_CREATE_OUTPUT}"
    exit 1
  fi

  PR_URL="${PR_CREATE_OUTPUT}"

  # ── Mostrar link del PR ───────────────────────────────────
  echo ""
  log_divider
  echo -e "${GREEN}${BOLD}  ✅ ¡PULL REQUEST CREADO EXITOSAMENTE! 🎉${RESET}"
  log_divider
  echo ""
  echo -e "  ${BOLD}🔗 Link del PR:${RESET}"
  echo -e "  ${CYAN}${BOLD}  ${PR_URL}${RESET}"
  echo ""
  echo -e "  ${DIM}  ${CURRENT_BRANCH} → ${TARGET_BRANCH} (${FLOW_LABEL})${RESET}"
  log_divider
  echo ""
}