---
model: claude-haiku-4-5-20251001
---

Analiza todos los cambios pendientes en el repositorio (staged + unstaged + untracked) y ejecuta commit + push con un mensaje descriptivo.

## Instrucciones

1. Ejecuta `git status` y `git diff` para entender qué cambió.
2. Analiza los cambios y genera un mensaje de commit siguiendo conventional commits: `type(scope): descripción imperativa en inglés`
   - Tipos: `feat`, `fix`, `refactor`, `docs`, `style`, `test`, `chore`, `perf`, `ci`
   - Primera línea máximo 72 caracteres, imperativo ("add", "fix", "update")
   - Si hay múltiples tipos de cambio, usa el más relevante y detalla en el body
3. Incluye un body con bullet points resumiendo los cambios principales (en inglés).
4. **Reporte de uso de Claude**: Si se completó una tarea en esta sesión y aún no existe el reporte de cierre, generarlo en `docs/claude-reports/YYYY-MM-DD_<slug>.md` siguiendo la plantilla de `rules/TASK-COMPLETION-REPORT.md`.
5. Haz `git add` selectivo (solo archivos relevantes, nunca `.env`, `node_modules`, `*.sqlite`, etc.). **Incluir los reportes de `docs/claude-reports/`** si hay nuevos o modificados.
6. Crea el commit con el mensaje generado.
7. Haz `git push` al remote actual.
8. Muestra un resumen al usuario de lo que se commiteó y pusheó.

## Notas

- Si no hay cambios, informa y no hagas nada.
- Si hay archivos sensibles (`.env`, credenciales, tokens), advierte y exclúyelos.
- Nunca uses `--force` en el push.
- Si el push falla por estar detrás del remote, haz `git pull --rebase` primero y reintenta.
- **NUNCA** incluir `Co-Authored-By` de Claude ni de ningún bot. El commit debe quedar únicamente con el usuario de git configurado en el sistema.

$ARGUMENTS
