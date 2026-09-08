# TASK-COMPLETION-REPORT — Reporte de Cierre de Tarea

> **APLICABILIDAD**: OPT-IN — solo se aplica cuando un proyecto activa explícitamente esta regla.
> **ESTADO POR DEFECTO**: ⚪ DESACTIVADA en el workspace `estimaciones/`.
> **ORIGEN**: Directiva de cliente — usar solo cuando el cliente exige trazabilidad documental del uso de asistencia de IA.

## Cómo activar esta regla para un proyecto

Crear el archivo `clients/<cliente>/<proyecto>/CLAUDE.md` con:

```markdown
# <Cliente> — <Proyecto> · Reglas locales

@../../../.claude/rules/TASK-COMPLETION-REPORT.md
```

> La ruta de arriba va **literal**, no como el token de raíz del stack. Es la excepción a la
> neutralización de ADR-012: este bloque no lo procesa ningún emisor — lo copia
> y pega una persona dentro de la config de su propio agente, donde el token no
> se expande y el include quedaría apuntando a la nada. Ajustá el prefijo a
> donde tengas instalado el stack en tu host.

Mientras el agente trabaje dentro de ese directorio, la regla aplicará automáticamente.
Cuando se trabaje en otro proyecto sin ese opt-in, la regla **no genera reportes**.

## Regla: Reporte al Finalizar Cada Tarea (cuando está activa)

Al completar exitosamente cualquier tarea y/o crear un Pull Request, se **DEBE** entregar un reporte de cierre con el siguiente formato:

---

### Plantilla de Reporte

```markdown
## 📋 Reporte de Cierre de Tarea

### Información General
| Campo | Valor |
|-------|-------|
| **Fecha** | YYYY-MM-DD |
| **Tarea / Requerimiento** | [Descripción breve del requerimiento] |
| **Agente(s) utilizado(s)** | [Agente(s) SAP que participaron] |
| **PR asociado** | [Link al PR si aplica] |
| **Branch** | [Nombre del branch] |

### Resumen de lo Realizado
[Descripción concisa de los cambios implementados, decisiones técnicas tomadas y artefactos generados]

### Archivos Modificados / Creados
| Archivo | Acción | Descripción del Cambio |
|---------|--------|----------------------|
| `path/to/file` | Creado / Modificado / Eliminado | Breve descripción |

### Herramienta de Desarrollo
> **Este requerimiento fue resuelto con asistencia de IA.** Completar con la
> herramienta y el modelo REALES de la sesión — es el dato que el cliente audita,
> y el stack corre en varios agentes (ver `docs/HOST-CAPABILITY-MATRIX.md`).
> - Herramienta: `<nombre del agente y proveedor>`
> - Modelo: `<modelo activo en la sesión>`
> - Stack de agentes SAP especializados

### Testing y Validación
[Indicar qué pruebas se realizaron o se recomiendan ejecutar]

### Consideraciones y Próximos Pasos
[Dependencias pendientes, riesgos identificados, o acciones de seguimiento]
```

---

## Cuándo Generar el Reporte

| Escenario | ¿Reporte obligatorio? | ¿Persistir en `docs/claude-reports/`? |
|-----------|----------------------|--------------------------------------|
| Tarea completada + commit/PR | ✅ **SÍ** — mensaje final + archivo | ✅ **SÍ** — incluir en el commit |
| Tarea completada sin commit (solo cambios locales) | ✅ **SÍ** — entregar al confirmar | ✅ **SÍ** — crear archivo para el próximo commit |
| Tarea parcialmente completada (bloqueada) | ⚠️ Reporte parcial indicando el bloqueo | ⚠️ Guardar si hay commit parcial |
| Consulta o análisis sin cambios de código | ❌ No aplica | ❌ No aplica |

## Persistencia del Reporte — Guardado automático en el proyecto

Además de mostrar el reporte en la conversación, se **DEBE** persistir como archivo markdown en el proyecto de trabajo:

### Ubicación y nombre del archivo

```text
<proyecto>/docs/claude-reports/YYYY-MM-DD_<slug-descriptivo>.md
```

- **`<proyecto>`**: La raíz del proyecto en el que se está trabajando (ej: `fury_fps-inv-ctrl-arg/`)
- **`YYYY-MM-DD`**: Fecha actual
- **`<slug-descriptivo>`**: Descripción breve de la tarea en kebab-case, máximo 50 caracteres
- Si ya existe un archivo con el mismo nombre, agregar sufijo incremental: `_02`, `_03`, etc.

**Ejemplos:**

- `docs/claude-reports/2026-04-15_fix-aging-report-buckets.md`
- `docs/claude-reports/2026-04-15_add-expense-approval-cap-app.md`
- `docs/claude-reports/2026-04-15_fix-aging-report-buckets_02.md`

### Pasos obligatorios

1. **Crear la carpeta** `docs/claude-reports/` en el proyecto si no existe
2. **Escribir el reporte** usando la plantilla definida arriba en el archivo `.md`
3. **Incluir el archivo** en el `git add` del commit (junto con los demás archivos del cambio)
4. El reporte debe quedar commiteado — es trazabilidad del uso de asistencia de IA para el cliente

### Cuándo persistir

| Escenario | ¿Guardar archivo? |
|-----------|-------------------|
| Tarea completada + commit | ✅ **SÍ** — incluir en el mismo commit |
| Tarea completada + PR | ✅ **SÍ** — incluir en el commit y referenciar en el PR |
| Tarea parcial (bloqueada) | ⚠️ Guardar reporte parcial si hay commit |
| Consulta sin cambios de código | ❌ No aplica |

---

## Reglas del Reporte

1. **Siempre incluir la sección "Herramienta de Desarrollo"** — es requisito del cliente documentar el uso de asistencia de IA
2. **Listar todos los archivos tocados** — el cliente necesita trazabilidad completa
3. **Ser específico en el resumen** — evitar descripciones genéricas, indicar qué se hizo y por qué
4. **Si se creó un PR**, incluir el link y el título del PR en el reporte
5. **El reporte se entrega como último mensaje** después de confirmar que todo está en orden
6. **El reporte DEBE persistirse como archivo** en `docs/claude-reports/` del proyecto y quedar incluido en el commit
