#!/usr/bin/env bash
# ================================================================
#  lib/context.sh
#  FASE 1 — Detectar contexto del repositorio
#  FASE 2 — Selección de flujo CI/CD o Legacy
#
#  Exporta:
#    REPO_ROOT        ruta absoluta a la raíz del repo
#    CURRENT_BRANCH   rama en la que se está trabajando
#    HAS_TERRAFORM    true si existe carpeta /terraform
#    HUSKY_DETECTED   true si el repo tiene Husky configurado
#    TARGET_BRANCH    rama destino del PR (main o develop)
#    FLOW_LABEL       etiqueta del flujo elegido (CI/CD o Legacy)
# ================================================================

phase_detect_context() {
  log_step "Detectando contexto del repositorio..."

  # ── Raíz del repo ─────────────────────────────────────────
  # git rev-parse --show-toplevel falla si no estamos en un repo git
  if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    log_error "No estás dentro de un repositorio git."
    exit 1
  fi
  log_info "Raíz del repo : ${REPO_ROOT}"

  # ── Rama actual ───────────────────────────────────────────
  # Detectar detached HEAD: en ese estado no se puede hacer push ni PR
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "${CURRENT_BRANCH}" == "HEAD" ]]; then
    log_error "Estás en detached HEAD. Cámbiate a una rama primero."
    exit 1
  fi
  log_info "Rama actual   : ${BOLD}${CURRENT_BRANCH}${RESET}"

  # ── Carpeta terraform ─────────────────────────────────────
  # Si existe /terraform, se incluye contexto IaC en el body del PR
  HAS_TERRAFORM=false
  if [[ -d "${REPO_ROOT}/terraform" ]]; then
    HAS_TERRAFORM=true
    log_success "Carpeta 'terraform' detectada."
  fi

  # ── Husky ─────────────────────────────────────────────────
  # Detecta si el repo usa Husky para git hooks (pre-commit, commit-msg)
  # Si está activo, los hooks se ejecutarán al hacer git commit
  HUSKY_DETECTED=false
  if [[ -f "${REPO_ROOT}/.husky/pre-commit" ]] || \
     [[ -f "${REPO_ROOT}/.husky/commit-msg" ]] || \
     (command -v node &>/dev/null && \
      [[ -f "${REPO_ROOT}/package.json" ]] && \
      grep -q '"husky"' "${REPO_ROOT}/package.json" 2>/dev/null); then
    HUSKY_DETECTED=true
    log_info "Husky detectado → los git hooks se ejecutarán en el commit."
  fi
}

phase_select_flow() {
  # ── Selección de flujo: CI/CD → main | Legacy → develop ──
  echo ""
  log_step "Selecciona el flujo de trabajo del repositorio:"
  log_divider
  echo -e "  ${BOLD}[1]${RESET} 🚀 ${GREEN}CI/CD${RESET}   → PR hacia ${BOLD}main${RESET}"
  echo -e "  ${BOLD}[2]${RESET} 🏛️  ${YELLOW}Legacy${RESET}  → PR hacia ${BOLD}develop${RESET}"
  log_divider
  echo ""

  FLOW_CHOICE=""
  while [[ ! "${FLOW_CHOICE}" =~ ^[12]$ ]]; do
    read -r -p "$(echo -e "${BOLD}Elige una opción [1/2]: ${RESET}")" FLOW_CHOICE
  done

  if [[ "${FLOW_CHOICE}" == "1" ]]; then
    TARGET_BRANCH="main"
    FLOW_LABEL="CI/CD"
  else
    TARGET_BRANCH="develop"
    FLOW_LABEL="Legacy"
  fi
  log_success "Flujo ${FLOW_LABEL} → PR hacia '${TARGET_BRANCH}'"

  # ── Fetch y validar rama destino ──────────────────────────
  # Trae información nueva del remoto sin mostrar output
  log_info "Ejecutando git fetch origin..."
  git fetch origin --prune --quiet

  # Verifica si existe la rama destino en el remoto antes de continuar
  if ! git rev-parse --verify "origin/${TARGET_BRANCH}" &>/dev/null; then
    log_error "No se encontró 'origin/${TARGET_BRANCH}'. Verifica el remoto."
    exit 1
  fi
  log_success "origin/${TARGET_BRANCH} verificado."
}