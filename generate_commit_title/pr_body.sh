#!/usr/bin/env bash
# ================================================================
#  lib/pr_body.sh
#  FASE 7 — Construir el body markdown del Pull Request
#
#  Genera el archivo temporal con el contenido completo del PR
#  usando todas las variables calculadas en las fases anteriores.
#
#  Lee:
#    CURRENT_BRANCH, TARGET_BRANCH, FLOW_LABEL, HAS_TERRAFORM
#    TICKET, CHANGE_TYPE, LAST_COMMIT_MSG, PR_TITLE
#    LINES_ADDED, LINES_REMOVED, NET, NET_LABEL, FILES_MODIFIED
#    CORE_LOGIC_FILES, DOMAIN_FILES, TEST_INFRA_FILES
#    TERRAFORM_FILES, OTHER_FILES
#    PR_BODY_TMP_PREFIX (config/defaults.sh)
#    PR_LOG_LINES       (config/defaults.sh)
#
#  Exporta:
#    BODY_FILE   ruta al archivo temporal con el markdown del PR
# ================================================================

phase_build_pr_body() {
  log_step "Construyendo cuerpo del PR..."

  # ── Contexto IaC (solo si existe carpeta terraform) ───────
  TERRAFORM_CONTEXT=""
  if [[ "${HAS_TERRAFORM}" == "true" ]]; then
    TERRAFORM_CONTEXT="
> ⚠️ **IaC Notice:** Repositorio con infraestructura Terraform en \`/terraform\`. Revisa los cambios de IaC antes de mergear."
  fi

  # ── Sección de archivos agrupados por categoría ───────────
  # Cada categoría solo aparece si tiene archivos clasificados
  FILES_SECTION=""
  [[ -n "${TERRAFORM_FILES}" ]]  && FILES_SECTION+="### 🏗️ Terraform / Infrastructure\n${TERRAFORM_FILES}\n"
  [[ -n "${CORE_LOGIC_FILES}" ]] && FILES_SECTION+="### ⚙️ Core Logic\n${CORE_LOGIC_FILES}\n"
  [[ -n "${DOMAIN_FILES}" ]]     && FILES_SECTION+="### 📦 Domain Models\n${DOMAIN_FILES}\n"
  [[ -n "${TEST_INFRA_FILES}" ]] && FILES_SECTION+="### 🧪 Tests & CI/CD\n${TEST_INFRA_FILES}\n"
  [[ -n "${OTHER_FILES}" ]]      && FILES_SECTION+="### 📁 Other Files\n${OTHER_FILES}\n"

  # ── Badge de flujo ────────────────────────────────────────
  FLOW_BADGE=""
  if [[ "${FLOW_LABEL}" == "CI/CD" ]]; then
    FLOW_BADGE="![CI/CD](https://img.shields.io/badge/Flow-CI%2FCD-blue)"
  else
    FLOW_BADGE="![Legacy](https://img.shields.io/badge/Flow-Legacy-yellow)"
  fi

  # ── Crear archivo temporal con el body ───────────────────
  BODY_FILE="$(mktemp ${PR_BODY_TMP_PREFIX})"

  cat > "${BODY_FILE}" <<EOF
${FLOW_BADGE}

## 📋 Description
${TERRAFORM_CONTEXT}
PR generado automáticamente desde \`${CURRENT_BRANCH}\` → \`${TARGET_BRANCH}\` · Flujo: **${FLOW_LABEL}**

## 🎯 Key Changes Summary
$(git log --pretty="- %s" "origin/${TARGET_BRANCH}...HEAD" 2>/dev/null | head -n "${PR_LOG_LINES}" || echo "- Ver diff adjunto")

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
**Tool**   : pr-author.sh v${PR_AUTHOR_VERSION}
EOF

  log_success "Body del PR construido."
}