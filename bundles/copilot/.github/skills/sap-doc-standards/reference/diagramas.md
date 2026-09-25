# Política de diagramas: motor validado, Mermaid y niveles L0-L2

> Referencia del agente de documentación. Se lee bajo demanda.

## Regla 1: arquitectura y secuencia van por el motor `sap-diagrams`

Un diagrama de arquitectura de solución o una secuencia de llamadas **no se
escriben a mano** — ni en Mermaid, ni en XML de draw.io, ni colocando
coordenadas. Se declaran en un `.sapdiag.json` y el skill `sap-diagrams` calcula
la geometría y **la mide** antes de aceptarla.

```bash
# $SAPDIAG se resuelve una vez por sesión — ver skills/sap-diagrams/SKILL.md
node "$SAPDIAG" validate <spec>.sapdiag.json --quality showcase
node "$SAPDIAG" deliver  <spec>.sapdiag.json --quality showcase
```

`deliver --png` produce el `.drawio` (editable por el cliente), el `.svg` (lo que
se referencia desde el `.md`) y el `.png` (lo que entra al `.docx`), los tres
desde la misma escena validada. Leé `skills/sap-diagrams/SKILL.md` antes de
escribir el primer spec.

**Convención en el `.md`:** referenciá el `.svg` — GitHub lo renderiza nativo —
y `build-doc.sh` lo cambia por el `.png` en la copia que consume pandoc:

```markdown
![Arquitectura de solución (L1)](arquitectura.svg)
```

`build-doc.sh` regenera todos los `.sapdiag.json` de la carpeta antes de armar el
`.docx` y **aborta si alguno no pasa `showcase`**: un documento con un diagrama
ilegible es peor que un build fallido, porque el ilegible llega al cliente.

**Por qué:** Mermaid decide el layout por su cuenta y nadie mide el resultado; el
generador Python exigía tipear x/y a mano. Las dos vías producían cajas
solapadas, conectores cruzados y etiquetas encima de las líneas, sin ninguna
señal de que el diagrama estaba mal.

## Regla 2: Mermaid, solo donde el motor no llega

- Modelos de datos: `erDiagram`
- Estructura de clases/servicios: `classDiagram`
- Flujos triviales de 3-4 cajas dentro del `.md`: `flowchart LR`
- **NUNCA** diagramas ASCII (`┌──`, `│`, `└──`) — se eliminan.
- Para arquitectura (`graph TB`/`graph LR`), secuencia (`sequenceDiagram`),
  iFlows de CPI y rutas de transporte: usá el motor, no Mermaid.

## Regla 3: Mermaid → PNG para Word (.docx)

Para que los diagramas aparezcan en el `.docx` como imágenes:

1. Extraer cada bloque ` ```mermaid ` del `.md` a archivos `.mmd` individuales
2. Renderizar con `mmdc` (mermaid-cli) o `mermaid.ink` API:

   ```bash
   # Opción A: mmdc local (si Puppeteer/Chrome disponible)
   mmdc -i diagrama.mmd -o diagrama.png -t neutral -w 1400 -b white -s 2

   # Opción B: mermaid.ink API (siempre funciona, requiere internet)
   ENCODED=$(base64 -w0 diagrama.mmd)
   curl -sS -o diagrama.png "https://mermaid.ink/img/${ENCODED}?bgColor=white&width=1400"
   ```

   El `build-doc.sh` intenta mmdc primero; si Puppeteer falla, usa mermaid.ink automáticamente.
3. En una copia del `.md` para pandoc, reemplazar el bloque mermaid por:

   ```markdown
   ![Nombre del diagrama](diagrama.png)
   ```

4. Generar el `.docx` con pandoc desde esa copia

El `build-doc.sh` debe automatizar todo este proceso.

## Regla 4: draw.io heredado (solo mantenimiento de diagramas viejos)

> Para diagramas **nuevos** usá el motor `sap-diagrams` (Regla 1). Esta sección
> queda para mantener diagramas `.drawio` preexistentes que todavía no se
> migraron a `.sapdiag.json`.

Genera un archivo `.drawio` siguiendo las guidelines oficiales SAP BTP Solution Diagrams (Horizon 2023).

**ANTES de generar cualquier .drawio, LEE estos archivos:**

1. `sap-btp-diagram-guidelines.md` — Guidelines oficiales SAP + REGLAS XML CRÍTICAS
2. `examples/*.drawio` — 5 ejemplos validados (L1 y L2) generados con el generador Python
3. `sap-btp-icons/extracted-icons.json` — 21 iconos SVG base64 listos para embeber

**Herramienta de generación:**
Usar `tools/sap-drawio-generator.py` (`SAPDiagramBuilder`) para generar diagramas programáticamente.
Este generador ENFORCE todas las reglas automáticamente:

- Icon labels siempre texto plano (nunca HTML)
- HTML escapado correctamente en áreas con subtítulos
- Colores SAP oficiales (Primary, Semantic, Accent)
- Conectores orthogonales
- Legend box siempre presente
- arcSize=24, absoluteArcSize=1, strokeWidth=1.5

```python
# Ejemplo de uso del generador (importable como módulo cuando se ejecuta
# desde la raíz del repo: PYTHONPATH=agents/11-documentation/tools python3 -m ...)
from sap_drawio_generator import SAPDiagramBuilder

d = SAPDiagramBuilder("Mi Diagrama", "id-1")
d.add_title(20, 10, "Mi Proyecto — SAP BTP Solution Diagram")
d.add_btp_area(50, 50, 800, 500)
d.add_subaccount(70, 100, 760, 430)
d.add_icon(100, 160, "hana-cloud", "SAP HANA\\nCloud", 32)
d.add_icon(200, 160, "cap-model", "CAP Service", 32)
d.add_connector("ico-101", "ico-102", "blue", "OData V4")
d.add_legend(600, 570)
d.save("output.drawio")
```

---
