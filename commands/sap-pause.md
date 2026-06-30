---
model: claude-haiku-4-5-20251001
---

# /sap-pause — Guardar Estado de Sesión (Checkpoint)

Guarda el estado actual de la sesión en `.planning/HANDOFF.json` para poder retomar el trabajo exactamente desde donde quedó, incluso en una nueva conversación.

> Argumentos opcionales: `$ARGUMENTS` — nota adicional para el próximo agente

---

## Instrucciones

### Paso 1 — Snapshot del estado actual

Recopila toda la información de estado:

```bash
# Archivos con cambios pendientes (sin commit)
git diff --name-only HEAD
git diff --stat HEAD

# Último commit (para contexto)
git log --oneline -5

# Branch actual
git branch --show-current
```

### Paso 2 — Inventario de trabajo

Identifica y resume:

- **Completado**: qué tareas/cambios están terminados y listos para commit
- **En progreso**: qué estaba haciendo el agente cuando se pausó
- **Pendiente**: qué falta hacer para completar la tarea original
- **Bloqueantes**: si hay algo que impide continuar

### Paso 3 — Leer CONTEXT.md si existe

```bash
cat .planning/CONTEXT.md 2>/dev/null || echo "No existe"
```

Incluir en el HANDOFF las decisiones técnicas clave del CONTEXT.md (solo los IDs y una línea por cada una — no duplicar el documento completo).

### Paso 4 — Escribir HANDOFF.json

Crear o sobrescribir `.planning/HANDOFF.json` con el siguiente formato:

```json
{
  "timestamp": "YYYY-MM-DDTHH:MM:SSZ",
  "branch": "nombre-del-branch",
  "session_summary": "Una oración resumiendo qué se estaba haciendo",
  "original_request": "El requerimiento original del usuario (copia textual si se recuerda)",
  "arguments": "$ARGUMENTS",
  "completed": [
    "Descripción de tarea completada 1",
    "Descripción de tarea completada 2"
  ],
  "in_progress": {
    "task": "Descripción de lo que estaba en curso",
    "agent": "nombre-del-agente-si-aplica",
    "last_action": "Último archivo modificado o acción realizada"
  },
  "pending": [
    "Próxima tarea 1 — descripción específica",
    "Próxima tarea 2 — descripción específica"
  ],
  "blockers": [],
  "key_decisions": [
    "D-01: decisión resumida",
    "D-02: decisión resumida"
  ],
  "files_modified": ["lista", "de", "archivos"],
  "files_uncommitted": ["archivos", "sin", "commit"],
  "next_command": "/sap-techlead [descripción de la siguiente tarea] o /sap-fiori [si es UI5]",
  "context_files": [
    ".planning/CONTEXT.md"
  ]
}
```

### Paso 5 — Confirmar al usuario

Mostrar un resumen del HANDOFF guardado:

```
✅ Checkpoint guardado en .planning/HANDOFF.json

Estado de la sesión:
  ✓ Completado:  [N tareas]
  → En progreso: [descripción]
  ○ Pendiente:   [N tareas]

Para retomar en la próxima sesión:
  1. Inicia una nueva conversación
  2. Corre /sap-techlead (detectará el HANDOFF.json automáticamente)
  3. O corre /sap-resume para cargar el estado directamente

Archivos sin commit: [N archivos]
[Si hay archivos sin commit]: ¿Querés hacer commit antes de pausar? → /commit-push
```

---

## Notas

- `.planning/HANDOFF.json` está en `.gitignore` — no se commitea (es estado efímero de sesión).
- Si ya existe un HANDOFF.json, sobrescribirlo siempre (solo hay un checkpoint activo).
- El `/sap-techlead` verifica al inicio si existe HANDOFF.json y ofrece retomar desde ahí.
