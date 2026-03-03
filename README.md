# pr-author.sh v1.0

Flujo completo: commit inteligente → push → PR estructurado en GitHub.

## Estructura

```
pr-author/
├── pr-author.sh           # Entry point (orquestador)
├── config/
│   └── defaults.sh        # Constantes globales
├── generate_commit_title/
│   ├── commit.sh          # FASE 3: commit inteligente y push
│   ├── pr_meta.sh         # FASE 4-6: diff, metadatos, estadísticas
│   ├── pr_body.sh         # FASE 7: body markdown del PR
│   └── pr_create.sh       # FASE 8-9: preview y creación del PR
├── lib/
│   ├── colors.sh          # Colores y funciones log_*
│   ├── deps.sh            # FASE 0: dependencias (git, gh, gemini)
│   ├── context.sh         # FASE 1-2: contexto del repo y flujo
│   └──ai.sh              # IA con Gemini CLI + fallback heurístico
```


## Uso

```bash
cd mi-repo
pr-author
```

## Dependencias

| Herramienta | Obligatorio | Propósito |
|---|---|---|
| `git` | ✅ | Control de versiones |
| `gh` | ✅ | Crear PRs en GitHub |
| `gemini` | ⚡ Opcional | Inferencia de tipo y título con IA |

Si Gemini CLI no está disponible, el tipo de commit se infiere automáticamente mediante análisis heurístico del diff.

## Primera vez con Gemini CLI

```bash
npm install -g @google/gemini-cli
gemini  # autenticarse con cuenta Google (gratuito)
```

## Tests

```bash
npm install -g bats
```