#!/usr/bin/env bash
# ================================================================
#  lib/commit.sh
#  FASE 3 — Commit inteligente con Conventional Commits + push
#
#  Detecta cambios pendientes, los stagea, consulta a la IA para
#  inferir tipo y título, ejecuta el commit respetando Husky,
#  hace push y pregunta si continuar al PR o seguir trabajando.
#
#  Depende de:
#    lib/ai.sh  → ai_infer_change_type, generate_commit_title
#
#  Lee:
#    CURRENT_BRANCH, HUSKY_DETECTED, GEMINI_AVAILABLE
#    DIFF_STAT_LINES, DIFF_NAME_STATUS_LINES (config/defaults.sh)
#
#  Exporta:
#    NEEDS_COMMIT (true|false) — usado por el orquestador para
#    decidir si continuar al flujo del PR
# ================================================================

phase_commit() {
  # ── Estado del working tree ───────────────────────────────
  HAS_STAGED=false   ##no hay cambios en staging
  HAS_UNSTAGED=false ##no hay cambios sin stagear
  UNTRACKED=""       ##No hay archivos sin trackear

  git diff --cached --quiet 2>/dev/null || HAS_STAGED=true
  git diff --quiet 2>/dev/null          || HAS_UNSTAGED=true
  UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null || true)"

  NEEDS_COMMIT=false
  if [[ "${HAS_STAGED}" == "true" ]] || \
     [[ "${HAS_UNSTAGED}" == "true" ]] || \
     [[ -n "${UNTRACKED}" ]]; then
    NEEDS_COMMIT=true   ##si hay cambios que para hacer commit
  fi

  if [[ "${NEEDS_COMMIT}" == "true" ]]; then
    log_step "Cambios detectados → iniciando flujo de commit..."

    # Agregar al staging si no hay nada staged
    if [[ "${HAS_STAGED}" == "false" ]]; then
      log_info "Nada en staging. Ejecutando 'git add -A'..."
      git add -A
    fi

    log_info "Cambios que entrarán en el commit:"
    git diff --cached --stat
    echo ""

    # Extraer ticket de la rama (contexto, no tipo)
    COMMIT_TICKET=""
    if [[ "${CURRENT_BRANCH}" =~ ([A-Z]+-[0-9]+) ]]; then
      COMMIT_TICKET="${BASH_REMATCH[1]}"  ##captura el primer patrón tipo ABC-123 del nombre de la rama
    fi

    # Capturar diff real (una sola vez, reutilizable)
    DIFF_SUMMARY="$(git diff --cached --stat 2>/dev/null | head -n "${DIFF_STAT_LINES}")"       ##resumen de los cambios en staging
    DIFF_NAME_STATUS="$(git diff --cached --name-status 2>/dev/null | head -n "${DIFF_NAME_STATUS_LINES}")"  ##lista de archivos modificados con su estado (A/M/D)
    DIFF_CONTEXT="${DIFF_SUMMARY}
${DIFF_NAME_STATUS}"  ##une ambos por salto de linea para dar contexto completo a la IA

    # La IA analiza el DIFF REAL para determinar el tipo — no el nombre de la rama
    log_step "Consultando IA para inferir tipo de commit y título..."
    log_info "Analizando el diff real (archivos modificados, líneas +/-) ..."
    COMMIT_TYPE="$(ai_infer_change_type "${DIFF_CONTEXT}")"
    log_success "Tipo de commit inferido por IA: ${BOLD}${COMMIT_TYPE}${RESET}"

    AI_TITLE="$(generate_commit_title "${DIFF_SUMMARY}" "${COMMIT_TYPE}")"

    # Mostrar propuesta al usuario para aceptar o personalizar
    echo ""
    log_divider
    echo -e "${BOLD}Título sugerido por IA:${RESET}"
    if [[ -n "${COMMIT_TICKET}" ]]; then  ##si no esta vacio el ticket, lo muestra en el titulo sugerido
      echo -e "  ${GREEN}${BOLD}${COMMIT_TYPE}(${COMMIT_TICKET}): ${AI_TITLE}${RESET}"
    else
      echo -e "  ${GREEN}${BOLD}${COMMIT_TYPE}: ${AI_TITLE}${RESET}"
    fi
    log_divider
    echo ""
    echo -e "  ${BOLD}[1]${RESET} ✅ Aceptar este título"
    echo -e "  ${BOLD}[2]${RESET} ✏️  Escribir mi propio título"
    echo ""

    TITLE_CHOICE=""
    while [[ ! "${TITLE_CHOICE}" =~ ^[12]$ ]]; do
      read -r -p "$(echo -e "${BOLD}Opción [1/2]: ${RESET}")" TITLE_CHOICE
    done

    FINAL_COMMIT_TITLE="${AI_TITLE}"
    if [[ "${TITLE_CHOICE}" == "2" ]]; then
      echo ""
      read -r -p "$(echo -e "${BOLD}Escribe el título (sin prefijo como 'feat:'): ${RESET}")" CUSTOM_TITLE
      FINAL_COMMIT_TITLE="${CUSTOM_TITLE}"
    fi

    # Construir mensaje final con formato Conventional Commits
    if [[ -n "${COMMIT_TICKET}" ]]; then
      COMMIT_MSG="${COMMIT_TYPE}(${COMMIT_TICKET}): ${FINAL_COMMIT_TITLE}"
    else
      COMMIT_MSG="${COMMIT_TYPE}: ${FINAL_COMMIT_TITLE}"
    fi

    log_info "Mensaje final: ${BOLD}${COMMIT_MSG}${RESET}"
    echo ""

    # ─── Ejecutar commit (respetando Husky) ───────────────────
    log_step "Ejecutando commit..."
    [[ "${HUSKY_DETECTED}" == "true" ]] && log_info "Husky activo → hooks pre-commit y commit-msg se ejecutarán."

    COMMIT_OK=true
    git commit -m "${COMMIT_MSG}" 2>&1 || COMMIT_OK=false

    # ── Manejo de fallo de commit (Husky/lint) ────────────────
    if [[ "${COMMIT_OK}" == "false" ]]; then
      echo ""
      log_warn "El commit fue rechazado (Husky/lint/hooks fallaron)."
      log_divider
      echo -e "  ${BOLD}[1]${RESET} 🔧 Corregir errores y reintentar"
      # echo -e "  ${BOLD}[2]${RESET} ⚠️  Forzar commit (--no-verify, saltando hooks)"
      echo -e "  ${BOLD}[3]${RESET} ❌ Cancelar"
      log_divider
      echo ""

      HOOK_CHOICE=""
      while [[ ! "${HOOK_CHOICE}" =~ ^[123]$ ]]; do
        read -r -p "$(echo -e "${BOLD}¿Qué deseas hacer? [1/2/3]: ${RESET}")" HOOK_CHOICE
      done

      case "${HOOK_CHOICE}" in
        1)
          log_info "Corrige los errores en otra terminal, haz 'git add' y presiona ENTER aquí."
          read -r -p "$(echo -e "${BOLD}Presiona ENTER para reintentar... ${RESET}")"
          git commit -m "${COMMIT_MSG}" || {
            log_error "Commit rechazado nuevamente. Abortando."
            exit 1
          }
          ;;
        # 2)
        #   log_warn "Saltando hooks con --no-verify..."
        #   git commit --no-verify -m "${COMMIT_MSG}" || {
        #     log_error "Commit falló incluso con --no-verify."
        #     exit 1
        #   }
        #   ;;
        3)
          log_warn "Operación cancelada."
          exit 0
          ;;
      esac
    fi

    log_success "Commit creado: ${BOLD}${COMMIT_MSG}${RESET}"

    # ─── Push a la rama actual ────────────────────────────────
    log_step "Haciendo push a origin/${CURRENT_BRANCH}..."

    PUSH_OK=true
    git push origin "${CURRENT_BRANCH}" 2>&1 || PUSH_OK=false

    if [[ "${PUSH_OK}" == "false" ]]; then
      log_warn "Push directo falló. Intentando con --set-upstream..."
      git push --set-upstream origin "${CURRENT_BRANCH}" || {
        log_error "No se pudo hacer push. Verifica permisos y conexión."
        exit 1
      }
    fi

    log_success "Push exitoso a origin/${CURRENT_BRANCH} ✓"

    # ─── Post-push: ¿más cambios o crear PR? ─────────────────
    echo ""
    log_divider
    echo -e "${GREEN}${BOLD}  ✅ Commit y push realizados correctamente${RESET}"
    log_divider
    echo ""
    echo -e "  ${BOLD}[1]${RESET} 🔨 Quiero hacer más cambios antes de crear el PR"
    echo -e "  ${BOLD}[2]${RESET} 🚀 Crear el Pull Request ahora"
    echo ""

    NEXT_CHOICE=""
    while [[ ! "${NEXT_CHOICE}" =~ ^[12]$ ]]; do
      read -r -p "$(echo -e "${BOLD}¿Qué sigue? [1/2]: ${RESET}")" NEXT_CHOICE
    done

    if [[ "${NEXT_CHOICE}" == "1" ]]; then
      echo ""
      log_success "Perfecto. Cuando termines, vuelve a ejecutar este script."
      log_info "La rama '${CURRENT_BRANCH}' ya tiene el push previo."
      exit 0
    fi

    log_info "Continuando para crear el Pull Request..."
  else
    log_info "No hay cambios locales pendientes. Procediendo al PR directamente."
  fi
}