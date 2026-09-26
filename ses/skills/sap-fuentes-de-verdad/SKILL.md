---
name: sap-fuentes-de-verdad
description: Catálogo de fuentes de verdad por stack SAP — qué documentación oficial es autoritativa para ABAP/RAP, CAP/BTP, Fiori/UI5, HANA Cloud e Integration Suite, qué NO sirve para citar en cada una, y qué archivo del proyecto manda para cada dato (manifest.json, mta.yaml, srv/*.cds, .bdef, exports de iFlow). Úsalo antes de citar una API, una anotación, un release o un valor de configuración, en código o en documentación.
---

<!-- prompt-meta: last_reviewed=2026-09-25; sap_baseline=2025/2026; review_cycle_days=180 -->

# Fuentes de verdad por stack — enrutador

Una fuente de verdad es **de un stack, no del stack entero**. El agente ABAP no
cita capire y el agente CAP no cita la ABAP Keyword Documentation: citar la
fuente equivocada es citar mal, aunque el dato suene plausible.

**No leas los cinco archivos**: leé el de tu stack.

| Tu stack | Leé |
| --- | --- |
| ABAP, RAP, CDS ABAP, S/4HANA | `sap-fuentes-de-verdad/reference/abap.md` |
| CAP (Node.js o Java), BTP, XSUAA, MTA | `sap-fuentes-de-verdad/reference/cap-btp.md` |
| Fiori, SAPUI5, Fiori Elements, Launchpad | `sap-fuentes-de-verdad/reference/fiori-ui5.md` |
| HANA Cloud, SQLScript, Calculation Views | `sap-fuentes-de-verdad/reference/hana.md` |
| Integration Suite, CPI, IDoc, APIs externas | `sap-fuentes-de-verdad/reference/integration.md` |

Cada archivo tiene lo mismo, en este orden:

1. **Fuentes oficiales** — qué documento es autoritativo para qué, con enlace
   y un **ID estable**.
2. **Qué NO citar en este stack** — las confusiones frecuentes.
3. **Fuentes del proyecto** — qué archivo del repo manda para cada dato.

## Cómo se cita

Una fuente oficial se cita **por su ID**, entre corchetes:

```text
El draft exige ETag total en la entidad raíz [fuente:abap.rap].
Desde @sap/cds 8 el comportamiento cambió [fuente:cap.releases] — ver «Breaking changes».
```

El ID es lo que se verifica: al terminar un subagente, el hook de `SubagentStop`
comprueba que cada `[fuente:…]` exista en el catálogo, y avisa al orquestador
si no. La cita va en una sola línea, con los IDs separados por coma; una
escrita de otra forma (partida en dos líneas, con corchetes adentro o de más de
200 caracteres) no se reconoce y queda sin verificar. Un ID que no está en estas tablas no es una fuente citable: o falta en el
catálogo —y se agrega con su enlace, en el PR que lo necesite— o el dato va
`[NO VERIFICADO]`.

El hook comprueba que la fuente **exista**, no que diga lo que se le atribuye:
eso sigue siendo juicio de quien lee. Las filas sin ID (herramientas MCP,
skills vendored) no se citan: sirven para llegar a la fuente, no son la fuente.
Dentro del corchete, el ID va primero y lo que sigue es detalle: una SAP Note
se cita `[fuente:sap.notes 3456789]`, una sección `[fuente:abap.rap §draft]`.
Varias fuentes van separadas por coma: `[fuente:abap.rap, abap.cloud]`.

## Reglas de cita (aplican a los cinco stacks)

- **Un dato del proyecto se lee del proyecto.** IDs, versiones, entity sets,
  scopes, paths y nombres de servicio salen del archivo que los define, nunca de
  memoria ni de un ejemplo de la documentación.
- **Un dato de producto se lee de la documentación oficial de _ese_ stack.** Un
  skill (propio o vendored) es material de trabajo, no norma: sirve para llegar
  rápido al patrón, pero lo que se cita es la fuente oficial.
- **Nunca inventar** un número de SAP Note, un release, una versión de SDK ni el
  nombre de una anotación. Sin verificar, va marcado `[NO VERIFICADO]` y se pide
  confirmación antes de entregar.
- **Blogs, SAP Community y respuestas de foro no son fuente.** Sirven para
  encontrar la pista; se cita el documento oficial al que llevan.
- **Fuente citada = fuente abierta.** Si no se pudo abrir (pide S-user, el
  enlace cambió), se dice en la entrega en lugar de citarla igual.

## Fuentes del proyecto — genéricas (todos los stacks)

| Fuente | Datos |
| --- | --- |
| `README.md` | Descripción del proyecto, setup, comandos |
| `CHANGELOG.md` / historial de commits | Versiones, cambios relevantes |
| `mta.yaml` o `manifest.yml` | Runtime BTP (CF / Kyma), dependencias de servicios |
| CI/CD (`.pipeline/`, `.github/workflows/`) | Estrategia de build y deploy |

## Regla de oro

Si un valor puede obtenerse de un archivo de configuración, un manifiesto, una
definición CDS, una vista XML o la metadata del servicio — **extraelo**, no lo
escribas a mano. Hardcodear metadatos es la causa principal de documentación que
miente al regenerarse y de código que no compila contra el sistema del cliente.
