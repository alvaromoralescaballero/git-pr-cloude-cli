#!/usr/bin/env bash
# ================================================================
#  lib/ai.sh
#  Funciones de inferencia con IA para Conventional Commits
#
#  Usa Gemini CLI si está disponible (GEMINI_AVAILABLE=true).
#  Si Gemini falla o no está, cae al fallback heurístico que
#  analiza el contenido del diff directamente.
#
#  Funciones públicas:
#    ai_infer_change_type  <diff_context>  → imprime el tipo de commit
#    generate_commit_title <diff_summary> <change_type> → imprime el título
# ================================================================

# ----------------------------------------------------------------
# Función: determinar el tipo de Conventional Commit usando la IA
#
# La IA analiza el diff real (archivos, líneas +/-, nombres)
# y decide cuál de los tipos estándar aplica mejor.
# Solo si Gemini no está disponible se cae al fallback heurístico.
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
- style: formatting, linting, whitespace (no logic change) \
- chore: maintenance, config, scripts \
- revert: reverting a previous commit \
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

# ----------------------------------------------------------------
# Función: generar título corto del commit con IA o fallback local
#
# Intenta que Gemini sugiera un título descriptivo (max 60 chars).
# Si falla, construye un título genérico basado en los archivos modificados.
# ----------------------------------------------------------------
generate_commit_title() {
  local diff_summary="$1"
  local change_type="$2"

  if [[ "${GEMINI_AVAILABLE}" == "true" ]]; then
    local prompt="Suggest only a short commit message title (max 60 chars, no type prefix like feat:, just the description). Git diff summary: ${diff_summary}"
    local ai_title
    # Gemini CLI acepta el prompt directamente como argumento -p
    ai_title="$(gemini -p "${prompt}" 2>/dev/null \
      | grep -v '^$' | head -n 1 | sed 's/^[[:space:]]*//' | tr -d '"' || true)"

    if [[ -n "${ai_title}" && ${#ai_title} -gt ${AI_TITLE_MIN_LEN} && ${#ai_title} -le ${AI_TITLE_MAX_LEN} ]]; then
      echo "${ai_title}"
      return
    fi
  fi

  # Fallback local: usa los primeros 3 archivos modificados como contexto
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