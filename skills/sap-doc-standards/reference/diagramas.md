# Política de diagramas: guidelines SAP, draw.io, niveles L0-L2

> Referencia del agente de documentación. Se lee bajo demanda.

## Regla 1: Mermaid en el Markdown (SIEMPRE)

- **Todos los diagramas** en el `.md` deben ser bloques ` ```mermaid `.
- **NUNCA** diagramas ASCII (`┌──`, `│`, `└──`, etc.) — estos se eliminan.
- GitHub renderiza Mermaid nativamente en `.md`.
- Tipos de diagramas a usar:
  - `graph TB` / `graph LR` para arquitectura de componentes
  - `sequenceDiagram` para flujos de secuencia (llamadas entre servicios)
  - `flowchart LR` para pipelines y decisiones
  - `erDiagram` para modelos de datos
  - `classDiagram` para estructura de clases/servicios

## Regla 2: Mermaid → PNG para Word (.docx)

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

## Regla 3: Draw.io con SAP BTP Solution Diagrams (SIEMPRE)

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
