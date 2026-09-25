---
applyTo: **/*.abap,**/*.clas.abap,**/*.prog.abap,**/*.cds,**/*.ddls
description: Material técnico de referencia del stack para ABAP y S/4HANA — RAP (behavior definitions, draft, EML, service binding), CDS views y AMDP, access control DCL, extensibilidad Clean Core con BAdIs, y ABAP clásico/OO con ALV. Úsalo antes de escribir ABAP, CDS o un Business Object RAP para cargar solo el patrón que aplica.
---

# Estándares y patrones ABAP — enrutador

Este skill guarda el material técnico del agente ABAP en `reference/`. **No lo
cargues entero**: son ~4,5k tokens y en una tarea dada aplica un archivo.

| Necesitás… | Leé |
| --- | --- |
| RAP: behavior definitions, draft, EML, service binding, checklist de BO | `sap-abap-standards/reference/rap.md` |
| CDS views, AMDP, access control DCL | `sap-abap-standards/reference/cds-amdp.md` |
| Extensibilidad Clean Core, BAdIs, puntos de extensión | `sap-abap-standards/reference/clean-core-badis.md` |
| ABAP clásico/OO, reports, ALV | `sap-abap-standards/reference/abap-oo-reports.md` |
| Plantillas RAP end-to-end (interface → projection → BDEF → binding) | `sap-abap-standards/reference/rap-shared.md` |

Leelos con la tool Read, por path relativo a este skill.

## Reglas que aplican siempre (sin abrir ningún archivo)

Son las que más se violan y las que un ATC marca primero:

- **Clean Core** — nunca modificar objetos estándar SAP. BAdIs, CDS, RAP o
  extensiones BTP. Si parece que hace falta modificar el estándar, replanteá.
- **`SELECT *` prohibido** en código productivo — lista de campos explícita.
- **Nada de `SELECT` dentro de `LOOP`** — `FOR ALL ENTRIES` o JOIN.
- **`sy-subrc` después de CADA** `SELECT`, `ENQUEUE`, `DEQUEUE`, `UPDATE`,
  `MODIFY`, `CALL FUNCTION`. Nunca asumir éxito.
- **`ENQUEUE_E*` / `DEQUEUE_E*`** antes de escribir tablas con lock object.
- **`COMMIT WORK` por paquete** en procesos masivos (cada 500–2.000 registros),
  nunca uno solo al final, y con estrategia de reinicio definida.
- **`SELECT ... PACKAGE SIZE`** cuando el universo puede crecer.
- **`READ TABLE`** con `BINARY SEARCH` o `WITH KEY` en tablas sorted/hashed.

## Verificación antes de activar

- SyntaxCheck y ATC sobre el objeto (`CheckClass`, `CheckView`… vía MCP ADT)
- Unit tests si el objeto tiene lógica de negocio
- Para RAP: activar en orden — CDS interface → projection → BDEF → BIMP →
  service definition → service binding
