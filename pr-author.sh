#!/usr/bin/env bash

set -euo pipefail

#obtiene el directorio del script para usarlo como referencia
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#carga de modulos de dependencias
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/config/defaults.sh"
source "${SCRIPT_DIR}/lib/deps.sh"
source "${SCRIPT_DIR}/lib/context.sh"
source "${SCRIPT_DIR}/lib/ai.sh"
source "${SCRIPT_DIR}/lib/commit.sh"
source "${SCRIPT_DIR}/lib/pr-meta.sh"
source "${SCRIPT_DIR}/lib/pr_body.sh"
source "${SCRIPT_DIR}/lib/pr_create.sh"


# --------- Ejecutar Fases en orden -------

phase_verify_deps    # Verificar dependencias
phase_detect_context # Detectar contexto del repositorio
phase_select_flow    # Seleccionar el flujo de trabajo adecuado
phase_commit        # Crear commit con mensaje generado por IA
phase_verify_diff          # Verificar cambios con IA
phase_build_pr_metadata   # Construir metadata para el PR
phase_build_pr_metadata   # Construir el cuerpo del PR
phase_build_pr_body       # Construir el cuerpo del PR
phase_create_pr           # Crear el PR en GitHub