#!/usr/bin/env bash
# ================================================================
#  lib/pr_meta.sh
#  FASE 4 — Verificar diff respecto a rama target
#  FASE 5 — Inferir metadatos del PR (ticket, tipo, título)
#  FASE 6 — Estadísticas y clasificación de archivos modificados
#
#  Depende de:
#    lib/ai.sh  → ai_infer_change_type
#
#  Lee:
#    CURRENT_BRANCH, TARGET_BRANCH, FLOW_LABEL
#    PR_DIFF_STAT_LINES, PR_DIFF_NAME_STATUS_LINES (config/defaults.sh)
#
#  Exporta:
#    TICKET              identificador del ticket (ej: ABC-123 o NO-TICKET)
#    CHANGE_TYPE         tipo Conventional Commit del PR
#    PR_TITLE            título completo del PR
#    LAST_COMMIT_MSG     mensaje del último commit
#    LINES_ADDED         total de líneas agregadas
#    LINES_REMOVED       total de líneas eliminadas
#    NET                 diferencia neta de líneas
#    NET_LABEL           etiqueta legible (increase|reduction|no net change)
#    FILES_MODIFIED      cantidad de archivos modificados
#    CORE_LOGIC_FILES    archivos de lógica core (servicios, handlers, etc.)
#    DOMAIN_FILES        archivos de dominio (models, DTOs, events, etc.)
#    TEST_INFRA_FILES    archivos de tests y CI/CD
#    TERRAFORM_FILES     archivos de infraestructura Terraform
#    OTHER_FILES         archivos que no encajan en las categorías anteriores
# ================================================================

phase_verify_diff() {
  # ── FASE 4: Verificar que hay diferencias respecto al target ──
  log_step "Verificando diferencias con origin/${TARGET_BRANCH}..."

  DIFF_CHECK="$(git diff "origin/${TARGET_BRANCH}...HEAD" --name-only 2>/dev/null || true)"
  if [[ -z "${DIFF_CHECK}" ]]; then
    log_error "No hay diferencias entre '${CURRENT_BRANCH}' y 'origin/${TARGET_BRANCH}'."
    exit 0
  fi
  log_success "Cambios detectados vs origin/${TARGET_BRANCH}."
}

phase_build_pr_metadata() {
  # ── FASE 5: Metadatos del PR ───────────────────────────────
  log_step "Inferiendo metadatos del PR..."

  # Ticket: primero busca en el nombre de la rama, luego en los commits recientes
  TICKET=""
  if [[ "${CURRENT_BRANCH}" =~ ([A-Z]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
  fi
  if [[ -z "${TICKET}" ]]; then
    TICKET="$(git log -n 10 --pretty=%s | grep -oE '[A-Z]+-[0-9]+' | head -n1 || true)"
  fi
  [[ -z "${TICKET}" ]] && TICKET="${DEFAULT_TICKET}"

  # Change type — la IA analiza el diff completo del PR, no el nombre de la rama
  PR_DIFF_STAT="$(git diff --stat "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null | head -n "${PR_DIFF_STAT_LINES}" || true)"
  PR_DIFF_NAMES="$(git diff --name-status "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null | head -n "${PR_DIFF_NAME_STATUS_LINES}" || true)"
  PR_DIFF_CONTEXT="${PR_DIFF_STAT}
${PR_DIFF_NAMES}"

  log_info "Consultando IA para determinar el tipo del PR desde el diff..."
  CHANGE_TYPE="$(ai_infer_change_type "${PR_DIFF_CONTEXT}")"
  log_success "Tipo inferido por IA para el PR: ${BOLD}${CHANGE_TYPE}${RESET}"

  # Título: parte del último commit y limpia prefijos existentes
  LAST_COMMIT_MSG="$(git log -1 --pretty=%s)"
  SHORT_TITLE="$(echo "${LAST_COMMIT_MSG}" \
    | sed 's/^\[.*\] //' \
    | sed 's/^[a-zA-Z]*([^)]*): //' \
    | sed 's/^[a-zA-Z]*: //')"

  PR_TITLE="[${TICKET}] ${CHANGE_TYPE}: ${SHORT_TITLE}"
  log_success "Título del PR: ${PR_TITLE}"

  # ── FASE 6: Estadísticas y clasificación de archivos ──────
  log_step "Analizando diff..."

  NUMSTAT="$(git diff --numstat "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null || true)"
  LINES_ADDED=0
  LINES_REMOVED=0

  # Sumar líneas agregadas y eliminadas de todos los archivos
  while IFS=$'\t' read -r added removed _file; do
    [[ "${added}" =~ ^[0-9]+$ ]]   && LINES_ADDED=$(( LINES_ADDED + added ))
    [[ "${removed}" =~ ^[0-9]+$ ]] && LINES_REMOVED=$(( LINES_REMOVED + removed ))
  done <<< "${NUMSTAT}"

  NET=$(( LINES_ADDED - LINES_REMOVED ))
  if   (( NET > 0 )); then NET_LABEL="increase"
  elif (( NET < 0 )); then NET_LABEL="reduction"
  else                      NET_LABEL="no net change"
  fi

  NAME_STATUS="$(git diff --name-status "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null || true)"
  FILES_MODIFIED="$(echo "${NAME_STATUS}" | grep -c '[^[:space:]]' || true)"

  log_info "Archivos: ${FILES_MODIFIED} | +${LINES_ADDED} / -${LINES_REMOVED} | Net: ${NET}"

  # ── Clasificar archivos por categoría ─────────────────────
  # Las categorías se usan para el body del PR en pr_body.sh
  CORE_LOGIC_FILES=""
  DOMAIN_FILES=""
  TEST_INFRA_FILES=""
  TERRAFORM_FILES=""
  OTHER_FILES=""

  while IFS=$'\t' read -r _status filepath; do
    [[ -z "${filepath}" ]] && continue
    line="- \`${filepath}\`"

    if [[ "${filepath}" == terraform/* ]] || [[ "${filepath}" == *".tf" ]]; then
      TERRAFORM_FILES+="${line}\n"
    elif echo "${filepath}" | grep -qiE '(test|__tests__|spec|\.spec\.|\.test\.|iac|infra|\.github/workflows|k8s|helm|docker|Dockerfile|\.yml$|\.yaml$)'; then
      TEST_INFRA_FILES+="${line}\n"
    elif echo "${filepath}" | grep -qiE '(domain|model|entit|event|dto|schema|type)'; then
      DOMAIN_FILES+="${line}\n"
    elif echo "${filepath}" | grep -qiE '(mapper|service|usecase|handler|controller|provider|adapter|repository|lambda|function|step|workflow)'; then
      CORE_LOGIC_FILES+="${line}\n"
    else
      OTHER_FILES+="${line}\n"
    fi
  done <<< "${NAME_STATUS}"
}