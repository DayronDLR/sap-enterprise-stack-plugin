# Catálogo de templates, guías y herramientas del agente de documentación

> Referencia del agente de documentación. Se lee bajo demanda.

**TODO está dentro de `agents/11-documentation/`. LEER SIEMPRE antes de generar documentación:**

## Guías y templates

| Archivo | Propósito |
| --- | --- |
| `client-docs/<cliente>/<cliente>-template-structure.md` | Estructura del template del cliente (secciones, tipografía, colores, patrones de tabla). Se almacena en `client-docs/` (fuera del repo). |
| `sap-btp-diagram-guidelines.md` | **Guidelines SAP oficiales** — colores, connectors, áreas, iconos, niveles L0-L2, REGLAS XML |

## Templates Word

| Archivo | Propósito |
| --- | --- |
| `client-docs/<cliente>/templates/*.docx` | Templates Word del cliente para pandoc `--reference-doc`. Se almacenan en `client-docs/` (fuera del repo, nunca commitear). |

## Herramientas (tools/)

| Archivo | Propósito |
| --- | --- |
| `tools/sap-drawio-generator.py` | **Generador Python** de diagramas draw.io SAP BTP — importar `SAPDiagramBuilder` |
| `tools/build-doc.sh` | Script para Mermaid→PNG→pandoc→docx (aplica theme cliente automáticamente) |
| `tools/build-pptx.py` | Generador de presentaciones .pptx parametrizable por cliente (importa `theme_colors.py`) |
| `tools/apply-theme.py` | Aplica la identidad visual del cliente — genera `reference.docx`, `theme_colors.py` y `theme.json` desde un `client-theme.yaml` |
| `tools/postprocess-docx.py` | Post-procesa el .docx generado por pandoc: cambia `tblLayout=fixed` a `autofit` y corrige columnas con ancho < 0.4". Lo invoca automáticamente `build-doc.sh` después de pandoc. |
| `tools/client-theme.example.yaml` | Template de paleta cliente (primary/accent/text/border + fonts + logos) |
| `tools/generate-examples.py` | Genera 5 diagramas de ejemplo |

## Sistema de theming parametrizable (NUEVO)

**Principio:** un único archivo `client-theme.yaml` controla la identidad visual de **todos** los entregables (.docx, .pptx, draw.io). Cambiar la paleta → regenerar todo.

**Flujo:**

> **Dónde está el toolkit:** los scripts viven en `$TOOLKIT`. En un checkout del
> stack es `agents/11-documentation/tools/`; instalado como plugin, el toolkit se
> distribuye aparte (`dist/sap-doc-toolkit/`) y hay que desempaquetarlo en el
> proyecto. Si `$TOOLKIT` no existe, decilo y pedí el toolkit antes de seguir —
> no inventes los scripts.

```bash
TOOLKIT=agents/11-documentation/tools    # o ./sap-doc-toolkit/tools si vino del plugin

# 1. Copiar el template del theme al proyecto
cp "$TOOLKIT/client-theme.example.yaml" \
   docs/architecture/client-theme.yaml

# 2. Editar la paleta del cliente
#    colors: primary, primary_dark, accent, accent_dark, light, text, muted, border
#    fonts:  primary, monospace
#    logos:  consultora, client
#    client: name, group, short_name

# 3. Aplicar el theme — genera reference.docx + theme_colors.py + theme.json
python3 "$TOOLKIT/apply-theme.py" docs/architecture/client-theme.yaml

# 4. Regenerar entregables (consume el theme automáticamente)
bash docs/architecture/build-doc.sh          # → .docx con paleta cliente
python3 docs/architecture/build-pptx.py      # → .pptx con paleta cliente
```

**Qué se parametriza con el theme:**

| Elemento | docx | pptx |
| --- | --- | --- |
| Heading 1, 2 (color) | ✓ primary | — |
| Heading 3, 4, 5 (color) | ✓ primary_dark | — |
| Title, Subtitle, TOCHeading | ✓ primary | — |
| Author, Date | ✓ primary_dark | — |
| Tabla — header fill | ✓ primary | ✓ primary |
| Tabla — filas alternas | ✓ light | ✓ light |
| Tabla — borde | ✓ border | — |
| Banner de slide | — | ✓ primary + accent (bicolor) |
| Caja destacada / estimación | — | ✓ accent |
| Tarjetas de fase | — | ✓ primary + dark |
| Logos en cada slide | — | ✓ paths del theme |

**Paletas de cliente comunes:**

| Cliente | primary | accent | Observación |
| --- | --- | --- | --- |
| HOCOL / Ecopetrol | `00833F` | `FFCD00` | Verde institucional + amarillo corporativo |
| Bancolombia | `FDDA24` | `2C2A29` | Amarillo institucional + negro |
| Bavaria / AB-InBev | `D9261C` | `1A1A1A` | Rojo corporativo + negro |
| Genérico Tivit | `4F2D7F` | `7B4EB6` | Púrpura Tivit (default fallback) |

## Librería SAP BTP Icons (sap-btp-icons/)

| Archivo | Propósito |
| --- | --- |
| `sap-btp-icons/extracted-icons.json` | **21 iconos SVG base64** listos para embeber en draw.io |
| `sap-btp-icons/essentials.xml` | Shapes genéricos (End User, On-Premise, Legend, Cloud Connector) |
| `sap-btp-icons/area_shapes.xml` | 44 containers en 5 sistemas de color x 4 tamaños |
| `sap-btp-icons/connectors.xml` | 87 conectores en 7 colores x 3 estilos |
| `sap-btp-icons/20-02-99-02-sap-btp-service-icons-all-size-M.xml` | 100 service icons SAP BTP (size M) |

## Ejemplos (examples/)

| Archivo | Tipo |
| --- | --- |
| `examples/01-cap-fiori-hana-L1.drawio` | CAP + Fiori + HANA (L1) |
| `examples/02-integration-suite-L1.drawio` | Integration Suite CPI (L1) |
| `examples/03-multitenant-saas-L1.drawio` | Multi-Tenant SaaS (L1) |
| `examples/04-s4-extension-L2.drawio` | S/4HANA Extension (L2) |
| `examples/05-document-ai-ocr-L2.drawio` | Document AI Pipeline (L2) |
