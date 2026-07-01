---
name: team-refactor
description: "Orquesta un equipo de agents para refactors grandes que tocan múltiples capas del proyecto (backend, frontend, tests). Usa Agent Teams experimental de Claude Code."
disable-model-invocation: true
---

# Team Refactor — Agent Teams para refactors grandes

Orquestar un equipo de teammates para refactors que tocan múltiples capas simultáneamente.

## Prerequisitos

Agent Teams debe estar habilitado. Si no lo está, indicar al usuario:

```bash
# Agregar a .claude/settings.json o como variable de entorno
# "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" }
```

## Instrucciones

### 1. Analizar el refactor pedido

Entender qué capas están involucradas:

- Backend (db/, srv/)
- Frontend (app/webapp/)
- Tests (test/, webapp/test/)
- Config (manifest.json, mta.yaml, package.json)

### 2. Crear el equipo

Spawnar teammates según las capas involucradas. Ejemplo para un refactor full-stack:

```
Creá un agent team para este refactor:

- Teammate "backend": responsable de cambios en db/ y srv/.
  Debe seguir las convenciones del skill sap-cap-backend.

- Teammate "frontend": responsable de cambios en app/webapp/.
  Debe seguir las convenciones del skill sapui5-freestyle.

- Teammate "tests": responsable de crear/actualizar tests en test/ y webapp/test/.
  Debe seguir las convenciones del agent tester.

Coordinen via task list compartida. El orden es:
1. Backend implementa primero (entidades, servicios, handlers)
2. Frontend implementa después (vistas, controllers, fragments)
3. Tests cubre todo al final
4. Cada uno revisa que su parte compile y pase lint
```

### 3. Monitorear

Mientras los teammates trabajan:

- Verificar que no haya conflictos en archivos compartidos (manifest.json, i18n)
- Si un teammate necesita algo que otro está haciendo, coordinar via mensajes
- Mantener máximo 3 teammates para evitar overhead excesivo

### 4. Consolidar

Cuando los teammates terminen:

- Verificar que todo compile junto (`cds build`)
- Correr `/verify` para la pipeline completa
- Correr `/review` para review final

## Cuándo usar Team Refactor vs Pipeline normal

| Situación | Usar |
|-----------|------|
| Feature nueva < 10 archivos | Pipeline normal (architect → implementer → ...) |
| Refactor que toca > 15 archivos en múltiples capas | **Team Refactor** |
| Migración masiva (ej: xmlfragment → Fragment.load en 20 archivos) | `/batch` (más eficiente para cambios repetitivos) |
| Bug fix | Pipeline normal o debugger directo |

## Reglas

- SIEMPRE máximo 3 teammates (más genera overhead sin beneficio)
- SIEMPRE definir orden de dependencias (backend antes de frontend)
- SIEMPRE correr /verify al final para validar todo junto
- NUNCA usar para cambios chicos — el overhead no lo justifica
