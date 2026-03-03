#!/usr/bin/env bash
# ================================================================
#  pr-author.sh  v2.0
#  Flujo completo: commit inteligente → push → PR estructurado
#
#  Features:
#   ✅ Pregunta flujo CI/CD (→ main) o Legacy (→ develop)
#   ✅ Genera commit con Conventional Commits + título sugerido por IA
#   ✅ Respeta Husky si el repo lo tiene configurado
#   ✅ Hace push a la rama actual
#   ✅ Post-push: ¿más cambios o crear PR?
#   ✅ Muestra link del PR al final
#   ✅ Detecta carpeta terraform e incluye contexto IaC
# ================================================================

set -euo pipefail

# ─── Colores ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_step()    { echo -e "\n${BOLD}${MAGENTA}▶ $*${RESET}"; }
log_divider() { echo -e "${DIM}────────────────────────────────────────────${RESET}"; }

# ================================================================
# FASE 0 — VERIFICAR E INSTALAR DEPENDENCIAS
# ================================================================
log_step "Verificando dependencias..."

# Git
if ! command -v git &>/dev/null; then
  log_error "git no está instalado."
  exit 1
fi
log_success "git: $(git --version)"

# GitHub CLI (gh)
# if ! command -v gh &>/dev/null; then
#   log_warn "GitHub CLI (gh) no encontrado. Instalando..."

#   if [[ "$OSTYPE" == "linux-gnu"* ]]; then
#     if command -v apt-get &>/dev/null; then
#       curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
#         | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
#       echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
#         https://cli.github.com/packages stable main" \
#         | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
#       sudo apt-get update -qq && sudo apt-get install -y gh
#     elif command -v dnf &>/dev/null; then
#       sudo dnf install -y 'dnf-command(config-manager)'
#       sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
#       sudo dnf install -y gh
#     else
#       log_error "No se pudo instalar gh. Visita: https://cli.github.com"
#       exit 1
#     fi
#   elif [[ "$OSTYPE" == "darwin"* ]]; then
#     command -v brew &>/dev/null && brew install gh || {
#       log_error "Instala Homebrew primero: https://brew.sh"
#       exit 1
#     }
#   else
#     log_error "SO no soportado para instalación automática."
#     exit 1
#   fi
# fi
# log_success "GitHub CLI: $(gh --version | head -n1)"

# GitHub Gemini CLI extension → reemplazado por Gemini CLI
GEMINI_AVAILABLE=false
log_step "Verificando Gemini CLI..."
if command -v gemini &>/dev/null; then
  log_success "Gemini CLI encontrado: $(gemini --version 2>/dev/null | head -n1 || echo 'ok')"
  GEMINI_AVAILABLE=true
else
  log_warn "Gemini CLI no encontrado. Instalando..."
  if command -v npm &>/dev/null; then
    npm install -g @google/gemini-cli 2>/dev/null && {
      log_success "Gemini CLI instalado."
      GEMINI_AVAILABLE=true
    } || log_warn "No se pudo instalar Gemini CLI. El tipo se inferirá localmente."
  else
    log_warn "npm no disponible. El tipo se inferirá localmente."
  fi
fi

# Autenticación
# log_step "Verificando autenticación GitHub..."
# if ! gh auth status &>/dev/null; then
#   log_error "No autenticado. Ejecuta: gh auth login"
#   exit 1
# fi
# log_success "Autenticado en GitHub."

# ================================================================
# FASE 1 — DETECTAR CONTEXTO DEL REPO
# ================================================================
log_step "Detectando contexto del repositorio..."

if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  log_error "No estás dentro de un repositorio git."
  exit 1
fi
log_info "Raíz del repo : ${REPO_ROOT}"

# Rama actual
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${CURRENT_BRANCH}" == "HEAD" ]]; then
  log_error "Estás en detached HEAD. Cámbiate a una rama primero."
  exit 1
fi
log_info "Rama actual   : ${BOLD}${CURRENT_BRANCH}${RESET}"

# Carpeta terraform
HAS_TERRAFORM=false
if [[ -d "${REPO_ROOT}/terraform" ]]; then
  HAS_TERRAFORM=true
  log_success "Carpeta 'terraform' detectada."
fi

# Husky
HUSKY_DETECTED=false
if [[ -f "${REPO_ROOT}/.husky/pre-commit" ]] || \
   [[ -f "${REPO_ROOT}/.husky/commit-msg" ]] || \
   (command -v node &>/dev/null && \
    [[ -f "${REPO_ROOT}/package.json" ]] && \
    grep -q '"husky"' "${REPO_ROOT}/package.json" 2>/dev/null); then
  HUSKY_DETECTED=true
  log_info "Husky detectado → los git hooks se ejecutarán en el commit."
fi

# ================================================================
# FASE 2 — SELECCIÓN DE FLUJO: CI/CD o LEGACY
# ================================================================
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

# Fetch y validar rama destino
log_info "Ejecutando git fetch origin..."
git fetch origin --prune --quiet   # trae informacion nueva del remoto sin mostrar output

if ! git rev-parse --verify "origin/${TARGET_BRANCH}" &>/dev/null; then    #verifca si existe la rama destino en el remoto 
  log_error "No se encontró 'origin/${TARGET_BRANCH}'. Verifica el remoto."
  exit 1
fi
log_success "origin/${TARGET_BRANCH} verificado."

# ================================================================
# FASE 3 — COMMIT INTELIGENTE (si hay cambios sin commitear)
# ================================================================

# Estado del working tree
HAS_STAGED=false   ##no hay cambios en staging  
HAS_UNSTAGED=false  ##no hay cambios sin stagear
UNTRACKED=""  ##No hay archivos sin trackear

git diff --cached --quiet 2>/dev/null || HAS_STAGED=true
git diff --quiet 2>/dev/null          || HAS_UNSTAGED=true
UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null || true)"

NEEDS_COMMIT=false
if [[ "${HAS_STAGED}" == "true" ]] || \
   [[ "${HAS_UNSTAGED}" == "true" ]] || \
   [[ -n "${UNTRACKED}" ]]; then
  NEEDS_COMMIT=true   ##si hay cambios que para hacer commit
fi

# ----------------------------------------------------------------
# Función: determinar el tipo de Conventional Commit usando la IA
#
# La IA analiza el diff real (archivos, líneas +/-, nombres)
# y decide cuál de los tipos estándar aplica mejor.
# Solo si Copilot no está disponible se cae al fallback heurístico.
# ----------------------------------------------------------------
ai_infer_change_type() {
  local diff_context="$1"   # git diff --stat o --name-status

  if [[ "${GEMINI_AVAILABLE}" == "true" ]]; then
    local prompt
    prompt="You are a Conventional Commits expert. \
Analyze the following git diff summary and respond with ONLY one word \
from this list (no explanation, no punctuation, just the word): \
feat, fix, docs, refactor, test, perf, chore, ci, build, style, revert. \
\
Rules: \
- feat: new feature or capability added \
- fix: bug fix, error correction, wrong behavior corrected \
- refactor: code restructure without changing behavior \
- test: adding or updating tests \
- docs: documentation only changes \
- perf: performance improvement \
- ci: CI/CD pipeline, GitHub Actions, workflows \
- build: build system, dependencies, package.json, Dockerfile \
- chore: maintenance, config, scripts \
\
Git diff summary:
${diff_context}"

    local ai_type
    # Gemini CLI acepta el prompt directamente como argumento -p
    ai_type="$(gemini -p "${prompt}" 2>/dev/null \
      | grep -v '^$' \
      | grep -oE '\b(feat|fix|docs|refactor|test|perf|chore|ci|build|style|revert)\b' \
      | head -n 1 || true)"

    if [[ -n "${ai_type}" ]]; then
      echo "${ai_type}"
      return
    fi
  fi

  # ── Fallback heurístico basado en el contenido del diff ──────
  # Se analiza el diff_context directamente, NO el nombre de la rama
  if echo "${diff_context}" | grep -qiE '(test|spec|__tests__)'; then
    echo "test"
  elif echo "${diff_context}" | grep -qiE '(\.md$|README|CHANGELOG|docs/)'; then
    echo "docs"
  elif echo "${diff_context}" | grep -qiE '(\.github/|workflow|pipeline|Jenkinsfile|\.circleci)'; then
    echo "ci"
  elif echo "${diff_context}" | grep -qiE '(Dockerfile|docker-compose|package\.json|package-lock|yarn\.lock|\.nvmrc|tsconfig|webpack|rollup|vite\.config)'; then
    echo "build"
  elif echo "${diff_context}" | grep -qiE '(terraform|\.tf$|\.tfvars)'; then
    echo "chore"
  elif echo "${diff_context}" | grep -qiE '(eslint|prettier|\.editorconfig|lint|format)'; then
    echo "style"
  elif echo "${diff_context}" | grep -qiE '(fix|bug|error|issue|crash|patch|hotfix|revert)'; then
    echo "fix"
  elif echo "${diff_context}" | grep -qiE '(perf|performance|optim|cache|speed|latency)'; then
    echo "perf"
  elif echo "${diff_context}" | grep -qiE '(refactor|restructur|reorgani|clean|extract|rename)'; then
    echo "refactor"
  else
    echo "feat"   # default: si agrega archivos nuevos sin señales claras → feat
  fi
}

# Función: generar título con IA o fallback local
generate_commit_title() {
  local diff_summary="$1"
  local change_type="$2"

  if [[ "${GEMINI_AVAILABLE}" == "true" ]]; then
    local prompt="Suggest only a short commit message title (max 60 chars, no type prefix like feat:, just the description). Git diff summary: ${diff_summary}"
    local ai_title
    # Gemini CLI acepta el prompt directamente como argumento -p
    ai_title="$(gemini -p "${prompt}" 2>/dev/null \
      | grep -v '^$' | head -n 1 | sed 's/^[[:space:]]*//' | tr -d '"' || true)"

    if [[ -n "${ai_title}" && ${#ai_title} -gt 5 && ${#ai_title} -le 100 ]]; then
      echo "${ai_title}"
      return
    fi
  fi

  # Fallback local
  local files
  files="$(git diff --cached --name-only 2>/dev/null | head -n 3 | tr '\n' ', ' | sed 's/,$//' || true)"
  [[ -z "${files}" ]] && files="$(git diff --name-only 2>/dev/null | head -n 3 | tr '\n' ', ' | sed 's/,$//' || true)"

  case "${change_type}" in
    feat)      echo "add functionality in ${files}" ;;
    fix)       echo "resolve issue in ${files}" ;;
    refactor)  echo "refactor code in ${files}" ;;
    docs)      echo "update documentation in ${files}" ;;
    test)      echo "add tests for ${files}" ;;
    ci)        echo "update CI/CD pipeline in ${files}" ;;
    perf)      echo "improve performance in ${files}" ;;
    *)         echo "update ${files}" ;;
  esac
}

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
  DIFF_SUMMARY="$(git diff --cached --stat 2>/dev/null | head -n 30)" ##resumen de los cambios en staging por las ultimas 30 líneas
  DIFF_NAME_STATUS="$(git diff --cached --name-status 2>/dev/null | head -n 40)"  ##lista de archivos modificados con su estado (A/M/D) por las ultimas 40 líneas
  DIFF_CONTEXT="${DIFF_SUMMARY}
${DIFF_NAME_STATUS}"  ##une ambos por salto de linea para dar contexto completo a la IA

  # La IA analiza el DIFF REAL para determinar el tipo — no el nombre de la rama
  log_step "Consultando IA para inferir tipo de commit y título..."
  log_info "Analizando el diff real (archivos modificados, líneas +/-) ..."
  COMMIT_TYPE="$(ai_infer_change_type "${DIFF_CONTEXT}")"
  log_success "Tipo de commit inferido por IA: ${BOLD}${COMMIT_TYPE}${RESET}"

  AI_TITLE="$(generate_commit_title "${DIFF_SUMMARY}" "${COMMIT_TYPE}")"

  # Mostrar propuesta
  echo ""
  log_divider
  echo -e "${BOLD}Título sugerido por IA:${RESET}"
  if [[ -n "${COMMIT_TICKET}" ]]; then  ##si no esta vacio el ticket, lo muestra en el titulo sugerido, sino solo muestra el tipo y el titulo
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

  # Construir mensaje final
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

# ================================================================
# FASE 4 — VERIFICAR DIFF RESPECTO A TARGET
# ================================================================
log_step "Verificando diferencias con origin/${TARGET_BRANCH}..."

DIFF_CHECK="$(git diff "origin/${TARGET_BRANCH}...HEAD" --name-only 2>/dev/null || true)"
if [[ -z "${DIFF_CHECK}" ]]; then
  log_error "No hay diferencias entre '${CURRENT_BRANCH}' y 'origin/${TARGET_BRANCH}'."
  exit 0
fi
log_success "Cambios detectados vs origin/${TARGET_BRANCH}."

# ================================================================
# FASE 5 — METADATOS DEL PR
# ================================================================
log_step "Inferiendo metadatos del PR..."

# Ticket
TICKET=""
if [[ "${CURRENT_BRANCH}" =~ ([A-Z]+-[0-9]+) ]]; then
  TICKET="${BASH_REMATCH[1]}"
fi
if [[ -z "${TICKET}" ]]; then
  TICKET="$(git log -n 10 --pretty=%s | grep -oE '[A-Z]+-[0-9]+' | head -n1 || true)"
fi
[[ -z "${TICKET}" ]] && TICKET="NO-TICKET"

# Change type — la IA analiza el diff completo del PR, no el nombre de la rama
PR_DIFF_STAT="$(git diff --stat "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null | head -n 40 || true)"
PR_DIFF_NAMES="$(git diff --name-status "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null | head -n 50 || true)"
PR_DIFF_CONTEXT="${PR_DIFF_STAT}
${PR_DIFF_NAMES}"

log_info "Consultando IA para determinar el tipo del PR desde el diff..."
CHANGE_TYPE="$(ai_infer_change_type "${PR_DIFF_CONTEXT}")"
log_success "Tipo inferido por IA para el PR: ${BOLD}${CHANGE_TYPE}${RESET}"

# Título
LAST_COMMIT_MSG="$(git log -1 --pretty=%s)"
SHORT_TITLE="$(echo "${LAST_COMMIT_MSG}" \
  | sed 's/^\[.*\] //' \
  | sed 's/^[a-zA-Z]*([^)]*): //' \
  | sed 's/^[a-zA-Z]*: //')"

PR_TITLE="[${TICKET}] ${CHANGE_TYPE}: ${SHORT_TITLE}"
log_success "Título del PR: ${PR_TITLE}"

# ================================================================
# FASE 6 — ESTADÍSTICAS Y CLASIFICACIÓN
# ================================================================
log_step "Analizando diff..."

NUMSTAT="$(git diff --numstat "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null || true)"
LINES_ADDED=0
LINES_REMOVED=0
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

# Clasificar archivos
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

# ================================================================
# FASE 7 — CONSTRUIR BODY DEL PR
# ================================================================
log_step "Construyendo cuerpo del PR..."

TERRAFORM_CONTEXT=""
if [[ "${HAS_TERRAFORM}" == "true" ]]; then
  TERRAFORM_CONTEXT="
> ⚠️ **IaC Notice:** Repositorio con infraestructura Terraform en \`/terraform\`. Revisa los cambios de IaC antes de mergear."
fi

FILES_SECTION=""
[[ -n "${TERRAFORM_FILES}" ]]  && FILES_SECTION+="### 🏗️ Terraform / Infrastructure\n${TERRAFORM_FILES}\n"
[[ -n "${CORE_LOGIC_FILES}" ]] && FILES_SECTION+="### ⚙️ Core Logic\n${CORE_LOGIC_FILES}\n"
[[ -n "${DOMAIN_FILES}" ]]     && FILES_SECTION+="### 📦 Domain Models\n${DOMAIN_FILES}\n"
[[ -n "${TEST_INFRA_FILES}" ]] && FILES_SECTION+="### 🧪 Tests & CI/CD\n${TEST_INFRA_FILES}\n"
[[ -n "${OTHER_FILES}" ]]      && FILES_SECTION+="### 📁 Other Files\n${OTHER_FILES}\n"

FLOW_BADGE=""
if [[ "${FLOW_LABEL}" == "CI/CD" ]]; then
  FLOW_BADGE="![CI/CD](https://img.shields.io/badge/Flow-CI%2FCD-blue)"
else
  FLOW_BADGE="![Legacy](https://img.shields.io/badge/Flow-Legacy-yellow)"
fi

BODY_FILE="$(mktemp /tmp/pr-body-XXXXXX.md)"

cat > "${BODY_FILE}" <<EOF
${FLOW_BADGE}

## 📋 Description
${TERRAFORM_CONTEXT}
PR generado automáticamente desde \`${CURRENT_BRANCH}\` → \`${TARGET_BRANCH}\` · Flujo: **${FLOW_LABEL}**

## 🎯 Key Changes Summary
$(git log --pretty="- %s" "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null | head -n 10 || echo "- Ver diff adjunto")

## 📊 Change Statistics
| Métrica | Valor |
|---|---|
| 📁 Files modified | ${FILES_MODIFIED} |
| ➕ Lines added | ${LINES_ADDED} |
| ➖ Lines removed | ${LINES_REMOVED} |
| 📈 Net ${NET_LABEL} | ${NET} lines |

## 🔍 Main Changes by File
$(echo -e "${FILES_SECTION}")
## ✅ Technical Benefits
- PR con estructura estandarizada y trazabilidad automática ticket → rama → PR.
$(if [[ "${HAS_TERRAFORM}" == "true" ]]; then echo "- Cambios de infraestructura Terraform incluidos en el diff."; fi)
$(if [[ "${FLOW_LABEL}" == "CI/CD" ]]; then echo "- Flujo CI/CD: el merge a \`main\` activa el pipeline de producción."; fi)
$(if [[ "${FLOW_LABEL}" == "Legacy" ]]; then echo "- Flujo Legacy: el merge pasa por \`develop\` antes de llegar a producción."; fi)

## 🎯 Business Impact
- Reducción del tiempo de revisión con descripciones estructuradas.
- Trazabilidad completa desde ticket hasta producción.

---
**Branch** : \`${CURRENT_BRANCH}\` → \`${TARGET_BRANCH}\`
**Commit** : ${LAST_COMMIT_MSG}
**Tool**   : pr-author.sh v2.0
EOF

log_success "Body del PR construido."

# ================================================================
# FASE 8 — PREVIEW Y CONFIRMACIÓN
# ================================================================
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

read -r -p "$(echo -e "${DIM}¿Ver el body completo antes de crear el PR? [y/N]: ${RESET}")" PREVIEW_CHOICE
if [[ "${PREVIEW_CHOICE}" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}──── BODY ────${RESET}"
  cat "${BODY_FILE}"
  echo -e "${YELLOW}──────────────${RESET}"
  echo ""
fi

read -r -p "$(echo -e "${BOLD}¿Crear el PR? [y/N]: ${RESET}")" CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  log_warn "PR cancelado. El commit y push ya fueron realizados en origin/${CURRENT_BRANCH}."
  rm -f "${BODY_FILE}"
  exit 0
fi

# ================================================================
# FASE 9 — CREAR EL PR
# ================================================================
log_step "Creando Pull Request en GitHub..."

PR_CREATE_OUTPUT=""
PR_CREATE_RESULT=0
PR_CREATE_OUTPUT="$(gh pr create \
  --base "${TARGET_BRANCH}" \
  --head "${CURRENT_BRANCH}" \
  --title "${PR_TITLE}" \
  --body-file "${BODY_FILE}" \
  --draft=false 2>&1)" || PR_CREATE_RESULT=$?

rm -f "${BODY_FILE}"

if [[ ${PR_CREATE_RESULT} -ne 0 ]]; then
  log_error "Falló la creación del PR:"
  echo "${PR_CREATE_OUTPUT}"
  exit 1
fi

PR_URL="${PR_CREATE_OUTPUT}"

# ================================================================
# FIN — MOSTRAR LINK DEL PR
# ================================================================
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