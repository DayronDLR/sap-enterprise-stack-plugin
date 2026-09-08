---
name: sap-doc-standards
description: Referencia del agente de documentación SAP — estructura maestra del documento de arquitectura, catálogo de templates y herramientas del toolkit (Word, PPTX, theming de cliente), política de diagramas draw.io con guidelines SAP y niveles L0-L2, y errores comunes en entregables. Úsalo al armar, generar o revisar documentación técnica de un proyecto SAP.
---

# Documentación SAP — enrutador

Este skill guarda el material de referencia del agente de documentación. Son ~5k
tokens en total: leé el archivo que la tarea pide, no todos.

| Vas a… | Leé |
| --- | --- |
| Armar o revisar el documento de arquitectura completo | `sap-doc-standards/reference/estructura-maestra.md` |
| Buscar un template, script o guía del toolkit | `sap-doc-standards/reference/archivos-referencia.md` |
| Generar un diagrama de arquitectura o de secuencia | el skill **`sap-diagrams`** (motor validado) |
| Política de diagramas: cuándo motor, cuándo Mermaid, niveles L0-L2 | `sap-doc-standards/reference/diagramas.md` |
| Revisar un entregable antes de mandarlo al cliente | `sap-doc-standards/reference/errores-comunes.md` |

## Reglas que aplican siempre

- **Cero relleno.** Ninguna sección vacía ni con texto genérico. Si no hay
  información para una sección, se omite o se marca `[PENDIENTE: <qué falta>]`.
- **Nada sin verificar.** Una API, feature o servicio SAP citado sin validar
  contra fuente oficial va marcado `[NO VERIFICADO]` y se pide confirmación
  antes de cerrar el `.docx`.
- **Metadatos extraídos, no escritos a mano.** IDs, versiones, entity sets,
  roles y scopes salen de `manifest.json`, `package.json`, CDS, `mta.yaml` o
  `xs-security.json`. Hardcodear metadatos es la causa principal de errores al
  regenerar.
- **Tablas y figuras numeradas** y referenciadas desde el cuerpo del texto.
- **Transacciones SAP con su código** (SE80, SE11, /IWFND/MAINT_SERVICE…).
- **Sin capturas inventadas.** Si no hay screenshot real, se describe el paso.
- **El theme del cliente se aplica con el toolkit**, nunca formateando a mano.
