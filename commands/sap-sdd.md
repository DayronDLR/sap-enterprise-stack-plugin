---
description: Ciclo SDD previo a codear (estimación y arquitectura): requerimiento, escenarios, diseño y plan, fase por fase y con aprobación. Sólo cuando se pide.
model: claude-opus-4-7
---

Vas a conducir el ciclo SDD (ADR-014) sobre este pedido del arquitecto SAP:

> $ARGUMENTS

## 0. ¿Corresponde?

El ciclo es caro: fases, varios artefactos y una aprobación humana en cada una.
Corre sólo cuando el arquitecto invocó este comando o pidió una **estimación**,
una **propuesta de arquitectura previa** o el **SDD** de un requerimiento. Si el
pedido es un fix, un report o un cambio puntual, decilo en una línea y resolvelo
con el agente que corresponde, sin crear un proyecto.

## 1. Cargar el skill y el motor

Leé `skills/sap-sdd/SKILL.md`: tiene el protocolo de cierre de fase,
el contrato de artefactos y cómo resolver el CLI. Resolvelo una vez
(`SDD=...`, con el corte si no aparece) y usalo para todo lo que sigue. **No
escribas `estado.json` ni `decisiones.md` a mano**: los escribe `sdd aprobar`.

## 2. El proyecto

El argumento es `<proyecto> [C1|C2|C3|C4|estado]`.

- Sin nombre: proponé uno corto en minúsculas y guiones (`aging-ar-mx`) y
  confirmalo antes de crear nada.
- `node "$SDD" estado <proyecto>`. Si no existe, `node "$SDD" init <proyecto>`,
  mostrá la ruta de `entradas/` y pedile al arquitecto que deje ahí la
  documentación del cliente. **No sigas hasta que esté.**
- Con `estado`, mostrá el estado y terminá.
- Sin fase: retomá en la primera que esté pendiente o vieja, en orden.

## 3. La fase

| Fase | Guía (leela entera antes de producir nada) |
|---|---|
| C1 Captura | `skills/sap-sdd/reference/C1-captura.md` |
| C2 Escenarios | `skills/sap-sdd/reference/C2-escenarios.md` |
| C3 Diseño | `skills/sap-sdd/reference/C3-diseno.md` |
| C4 Plan y estimación | `skills/sap-sdd/reference/C4-plan.md` |

Cada guía dice qué leer, qué producir, con qué forma y qué no hacer. En C4, la
estimación tiene que ser **justa**: seguí las reglas de «Estimar lo justo» al pie
de la letra y presentá el total que calcula el gate, nunca la suma de los
pesimistas ni un porcentaje de seguridad agregado.

## 4. El cierre, siempre igual

1. `node "$SDD" gate <proyecto> <fase>`. Si falla, corregí y volvé a correrlo.
   No presentes una fase que no pasa.
2. Presentá un resumen corto: qué produjiste, supuestos tomados, preguntas
   abiertas y riesgos. Los artefactos están en disco; no los pegues enteros.
3. Preguntá si aprueba. **Sólo con un sí explícito y el nombre de quien
   aprueba**: `node "$SDD" aprobar <proyecto> <fase> --decide "<nombre>"`.
4. Ofrecé la fase siguiente. No la arranques sin que te la pidan.

Si el arquitecto pide cambios, iterá la misma fase y volvé al paso 1. Si pide
cambiar una fase ya aprobada, editala: `sdd estado` va a mostrar qué fases
siguientes quedaron viejas, y se reaprueban en orden. En `requerimiento.md`, las
reglas nuevas van al final y las que ya no aplican se marcan `(retirado)` en su
línea: mover una regla ya citada rompe las citas, y el gate no lo deja pasar.

## Reglas que no se negocian

- `entradas/` es documentación de un cliente: se lee **sólo en C1**. Las fases
  siguientes citan `C1-captura/requerimiento.md`. No la copies fuera de la
  carpeta del proyecto ni la vuelques en el chat más allá de lo necesario.
- No inventes: lo que la documentación no dice va a `preguntas.md` (C1) o a los
  supuestos del resumen, nunca a un artefacto como si fuera un hecho.
- Nunca pongas en `--decide` un nombre que no te dieron.
