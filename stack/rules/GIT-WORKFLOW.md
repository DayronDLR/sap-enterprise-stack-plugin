# GIT-WORKFLOW — Control de Versiones

> **APLICABILIDAD**: Todo el proyecto — aplica a TODOS los agentes y tareas
> **PRIORIDAD**: ⭐ CRÍTICO — Cumplimiento obligatorio al 100%

## Regla: Confirmar Antes de Revertir Cambios

Cuando se solicite **revertir**, **deshacer** o **hacer rollback** de cambios, siempre preguntar al usuario cuál es su intención antes de ejecutar cualquier acción:

**Opción A - Revertir al último commit (cambios commiteados)**

```bash
git reset --soft HEAD~1    # Conservar cambios en staging
git reset --hard HEAD~1    # Descartar cambios (DESTRUCTIVO)
git revert <commit-hash>   # Crea un nuevo commit inverso (seguro)
```

**Opción B - Descartar cambios de la sesión actual (sin commit)**

```bash
git status                 # Ver qué archivos tienen cambios sin commitear
git restore <archivo>      # Descartar cambios de un archivo específico
git restore .              # Descartar todos los cambios sin commitear
git clean -fd              # Eliminar archivos no trackeados (DESTRUCTIVO)
```

## ❌ PROHIBIDO: Acciones Destructivas Sin Confirmación

```bash
# ❌ NUNCA ejecutar sin confirmación explícita del usuario
git reset --hard HEAD~1    # Destruye cambios commiteados sin recuperación
git clean -fd              # Elimina archivos no trackeados permanentemente
git push --force           # Sobreescribe historial remoto
```

## Tabla de Decisión Rápida

| El usuario dice... | Preguntar si quiere... |
|--------------------|------------------------|
| "revertir cambios" | ¿Sesión actual o último commit? |
| "deshacer lo que hice" | ¿Solo archivos modificados o también commits? |
| "volver al estado anterior" | ¿Anterior a qué? ¿Último commit o hace N commits? |
| "rollback" | ¿Qué alcance? ¿Conservar o descartar cambios? |

## Checklist Antes de Revertir

- [ ] Confirmar con el usuario si es rollback de sesión o de commit
- [ ] Confirmar si se deben conservar o descartar los cambios revertidos
- [ ] Nunca ejecutar `reset --hard` o `clean -fd` sin confirmación explícita
