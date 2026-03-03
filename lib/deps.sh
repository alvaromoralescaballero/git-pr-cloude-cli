#!/usr/bin/env bash
# ================================================================
#  lib/deps.sh
#  FASE 0 — Verificar e instalar dependencias requeridas:
#    - git         (obligatorio)
#    - gh          (GitHub CLI, obligatorio para crear PRs)
#    - gemini CLI  (opcional, mejora la inferencia de tipo de commit)
#
#  Exporta:
#    GEMINI_AVAILABLE (true|false)
# ================================================================

phase_verify_deps() {
  log_step "Verificando dependencias..."

  # ── Git ───────────────────────────────────────────────────
  # Git es obligatorio: sin él no hay nada que hacer
  if ! command -v git &>/dev/null; then
    log_error "git no está instalado."
    exit 1
  fi
  log_success "git: $(git --version)"

  # ── GitHub CLI (gh) ───────────────────────────────────────
  # gh es obligatorio para crear PRs en GitHub
  if ! command -v gh &>/dev/null; then
    log_error "GitHub CLI (gh) no encontrado. Instálalo en: https://cli.github.com"
    exit 1
  fi
  log_success "GitHub CLI: $(gh --version | head -n1)"

  # ── Autenticación GitHub ──────────────────────────────────
  # Verificar que el usuario esté autenticado antes de continuar
  log_step "Verificando autenticación GitHub..."
  if ! gh auth status &>/dev/null; then
    log_error "No autenticado. Ejecuta: gh auth login"
    exit 1
  fi
  log_success "Autenticado en GitHub."

  # ── Gemini CLI ────────────────────────────────────────────
  # Gemini CLI es opcional: si no está disponible se usa el fallback heurístico
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
}