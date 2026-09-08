---
name: sap-diagrams
description: "Motor de diagramas SAP validados — genera diagramas de arquitectura de solución (BTP, subaccounts, on-premise, Cloud Connector) y de secuencia (OData, RFC, IDoc, llamadas entre servicios) a partir de una especificación JSON tipada, y los entrega como .drawio editable y .svg para el .docx. El agente escribe semántica, no coordenadas: el layout, el ruteo ortogonal y la ubicación de etiquetas se calculan, y un gate de composición mide el resultado (solapes, cruces, corredores ambiguos, etiquetas tapadas, legibilidad) antes de aceptar la entrega. Úsalo siempre que haya que producir un diagrama de arquitectura o de secuencia SAP para documentación técnica, en vez de escribir Mermaid o XML de draw.io a mano."
---

# Diagramas SAP

Un diagrama sale de una especificación JSON chica y tipada. **Nunca escribas
coordenadas, waypoints ni XML de draw.io a mano**: el motor los calcula y después
los mide. Un diagrama que no pasa el gate no se entrega.

## Resolver el CLI (una vez por sesión)

El motor vive dentro del skill, y el skill puede estar en el checkout del stack o
en el plugin instalado. Resolvé la ruta una sola vez y usá `$SAPDIAG` después:

```bash
SAPDIAG=$(ls "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/skills/sap-diagrams/bin/sapdiag.mjs" \
             skills/sap-diagrams/bin/sapdiag.mjs 2>/dev/null | head -1)
node "$SAPDIAG" doctor
```

## Ruta de autoría

1. Elegí el tipo:

   | Tipo | Para qué | Lo específico |
   | --- | --- | --- |
   | `architecture` | Componentes, zonas BTP/on-premise, servicios | `zones` anidadas, `meta.level` L0-L2 |
   | `sequence` | Cadena de llamadas, retornos, auto-mensajes | `note` por mensaje, `return: true` |
   | `integration` | iFlows de Integration Suite | carriles BPMN, rama de excepción, `protocol` |
   | `landscape` | Ruta de transportes DEV→QAS→PRD | sistemas por columna, mandantes, tipo de TR |

2. Leé **un** schema (`schemas/<tipo>.schema.json`) y **un** ejemplo del mismo tipo
   en `examples/`. Nada más. El ejemplo da la forma de los campos, no los hechos.
3. **Escribí el candidato antes de mirar nada más.** La siguiente acción después
   de leer el schema es crear el `.sapdiag.json`. No planifiques geometría en prosa.
4. Validá después de cada edición:

   ```bash
   node "$SAPDIAG" validate <spec>.sapdiag.json --quality showcase
   ```

5. Entregá una sola vez, al final:

   ```bash
   node "$SAPDIAG" deliver <spec>.sapdiag.json --quality showcase --png
   ```

   `deliver` congela el spec, escribe `.drawio` + `.svg` (+ `.png` con `--png`)
   de forma atómica y devuelve SHA-256 y bytes de cada artefacto. Un exit distinto de cero **nunca**
   se reporta como éxito. Una entrega fallida no toca los artefactos anteriores.

## Loop de reparación

Cada diagnóstico trae `subject` (dónde), `evidence` (la medición en px) y
`supportedFixes` (qué se puede tocar). Reglas:

- Aplicá **un solo fix diagnosticado por ronda**. Cambiar tres cosas a la vez
  hace imposible saber cuál sirvió.
- Corregí solo lo que el diagnóstico nombra. No inventes `layer` ni `order` que
  nadie pidió.
- Seguí mientras el conteo de errores baje a un mínimo nuevo. **Si dos rondas
  seguidas no bajan ese mínimo, pará y reportá los diagnósticos que quedaron.**
  Un diagrama entregado con defectos declarados es honesto; uno entregado
  diciendo que pasó, no.

## Perfiles

| Perfil | Acepta | Cuándo |
| --- | --- | --- |
| `standard` | 0 errores, warnings permitidos | borrador interno, iteración |
| `showcase` | 0 errores **y** 0 warnings | todo entregable a cliente |

El perfil sale de `meta.quality_profile`; `--quality` lo pisa. Para documentación
de proyecto: **siempre `showcase`**.

## Nivel de detalle (`meta.level`)

No es decorativo: fija el techo de nodos, porque un diagrama que le habla a un
comité y uno que le habla a un desarrollador no admiten la misma densidad.

| `meta.level` | Máx. nodos | Le habla a |
| --- | ---: | --- |
| `L0` | 6 | Comité / sponsor: qué sistemas participan |
| `L1` | 12 | Arquitecto / funcional: componentes y sus relaciones |
| `L2` | 24 | Desarrollador: servicios, protocolos, detalle de integración |

Sin `meta.level` rige el techo del schema (24). Pasarse **bloquea en la etapa de
modelo**, antes de calcular geometría: la respuesta correcta es partir en dos
niveles, no compactar.

## Invariantes de autoría

- **Un camino principal claro**, de izquierda a derecha. Las ramas salen del nodo
  del camino principal más cercano.
- **Máximo 12 nodos primarios.** Si no entra, partilo en L1 (general) + L2 (detalle),
  no lo compactes.
- **No pongas `layer` ni `order`** salvo que un diagnóstico lo pida. El motor
  infiere las capas del grafo y pega los nodos sin predecesores a su consumidor.
- **`zones` es semántica, no decoración.** Un nodo va en `wraps` si realmente
  corre ahí dentro. Un marco que envuelve un nodo ajeno es una afirmación falsa
  sobre el landscape, y el gate la bloquea.
- **Las etiquetas de relación son datos.** Llevan protocolo, dirección o
  mecanismo (`OData V4`, `RFC / OData`, `túnel TLS`). Si una colisiona, primero
  acortala conservando el significado; borrarla no es una reparación geométrica.
  Omitila solo si ambos extremos ya la implican por completo.
- **`kind` define el color y la leyenda**: `data`, `auth`, `deploy`, `event`,
  `access`, `replication`. La leyenda se deriva sola de los `kind` usados.
- **`bidirectional: true` solo cuando el ida y vuelta es el hecho**, no cuando
  "hay respuesta". Casos legítimos: un `request-reply` de CPI, una replicación
  que sincroniza en ambos sentidos, un túnel. Una llamada OData que devuelve un
  payload **no** es bidireccional: toda llamada devuelve algo. En `sequence` el
  idioma es otro — el retorno se modela con `return: true` en un mensaje aparte,
  que además deja ver el orden. En `landscape` no existe: un transporte avanza.
- **`note` (solo secuencia) es para el porqué, no para el qué.** Va lo que el
  mensaje no dice y el lector necesita: idempotencia, timeout, política de
  reintento. El motor le reserva ancho y la mide como a cualquier otra caja.
- **Nombres de producto exactos**: `SAP HANA Cloud`, `S/4HANA 2023`, `XSUAA`,
  `SAP Integration Suite`. Nunca genéricos como "base de datos" o "el backend".

## Tipos de nodo

`user` `client` `fiori` `work-zone` `bas` `cap` `abap-cloud` `cf-runtime` `kyma`
`hana` `sac` `dms` `job-scheduler` `event-mesh` `integration-suite` `iflow`
`api-management` `destination` `connectivity` `cloud-connector` `private-link`
`ias` `xsuaa` `audit-log` `s4-onprem` `s4-cloud` `ecc` `bw` `external`
`database` `note`

Los que tienen icono oficial SAP BTP lo usan; el resto sale como caja rotulada
con el mismo color. La librería de iconos es un asset propietario de SAP y no se
redistribuye: sin ella el diagrama sigue siendo correcto, solo pierde el pictograma.

## Zonas (solo `architecture`)

`btp` · `subaccount` · `service-area` · `onpremise` · `external` · `network`

Se anidan declarando `wraps` como subconjunto: `subaccount` dentro de `btp` se
expresa poniendo en `btp.wraps` todo lo que está en `sub.wraps` más lo demás.

## Carriles (solo `integration`)

`sender` · `process` · `local-process` · `exception` · `receiver`

**El orden de declaración es el orden de lectura, de arriba hacia abajo.** El
subproceso de excepción va último: si lo ponés entre el proceso y el receptor,
los flujos de error cruzan los de datos y el gate lo bloquea — con razón.

Los pasos llevan `type`: `start` `end` `timer` `mapping` `router` `splitter`
`aggregator` `gather` `script` `request-reply` `content-modifier` `filter`
`converter` `encoder` `persist` `process-call` `exception-start`
`sender-system` `receiver-system` `external-system`. El color va por familia, así
que un router se distingue de un mapping y la rama de excepción del camino feliz.

## Sistemas (solo `landscape`)

Un sistema por columna, **en el orden de la ruta de transportes**. El motor no lo
infiere del grafo a propósito: dejarlo al grafo permitiría dibujar un landscape
donde PRD queda antes que QAS.

- `role`: `development` · `quality` · `production` · `sandbox` · `training`.
  Define el color, y PRD tiene que saltar a la vista.
- `sid`: tres caracteres, el de verdad (`S4D`, no `DEV`).
- Los **mandantes** son los nodos: un transporte va de un mandante a otro
  (`dev-100` → `qas-200`), no de sistema a sistema. Así el diagrama no puede
  mentir sobre a qué mandante entra el TR.
- `kind` del transporte: `workbench` · `customizing` · `gcts` · `cts-plus` ·
  `manual`. Un transporte que retrocede en la ruta se reporta como
  `model/backward-transport`: si es un retrofit deliberado, declaralo
  `manual` y etiquetalo.

## Salida al documento

| Artefacto | Para qué |
| --- | --- |
| **`.drawio`** | El entregable que el cliente edita. Reproduce exactamente la geometría validada: waypoints explícitos, sin re-ruteo del editor. |
| **`.svg`** | Lo que se referencia desde el `.md` — GitHub lo renderiza nativo. |
| **`.png`** (`--png`) | Lo que entra al `.docx`/`.pptx`. `build-doc.sh` cambia solo la referencia `.svg` → `.png` en la copia que consume pandoc. |

Los tres salen de la misma escena validada, así que no pueden divergir.

El PNG necesita un rasterizador del sistema: `rsvg-convert`, ImageMagick,
`cairosvg`, Inkscape o Chrome/Chromium (`CHROME_PATH` si está en un lugar raro).
`doctor` dice cuál encontró. Si no hay ninguno, `deliver --png` **falla con la
lista de opciones** en vez de entregar un documento con un hueco.

## Qué NO hace este motor

- No reemplaza Mermaid en el Markdown de GitHub para diagramas triviales de 3 cajas.
- No genera diagramas de datos (ER), de despliegue de transportes ni de red L3.
- No inspecciona el repositorio: los hechos los pone el autor del spec.

## Migrar un `.drawio` heredado

```bash
node "$SAPDIAG" migrate viejo.drawio --out viejo.sapdiag.json
```

Es un **punto de partida, no una traducción fiel**. El `.drawio` no contiene la
semántica que el motor necesita: qué caja es una zona, qué tipo SAP es cada nodo
y qué protocolo lleva cada relación no están en el archivo. El comando lista
exactamente qué tuvo que adivinar y qué dejó afuera — leé esos avisos antes de
tocar nada. Sale en `standard`; subirlo a `showcase` es decisión de quien revise.

## Ajustar umbrales por proyecto

Los umbrales del gate viven en `config/stack.config.json` → `diagrams.thresholds`.
Solo se declara lo que se quiere cambiar. El caso real: una lámina destinada a un
A3 impreso tolera más ancho que una de PowerPoint.

**Subir un umbral relaja el gate** — no es una preferencia de estilo, es aceptar
más defecto visual. Dejá escrito el porqué al lado del valor.

## Verificación del entorno

`node "$SAPDIAG" doctor` informa la versión de Node, los schemas cargados, si la
librería de iconos SAP BTP está disponible y cuántos ejemplos hay.
