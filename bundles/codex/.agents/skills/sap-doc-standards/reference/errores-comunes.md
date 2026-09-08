# Errores comunes en documentación SAP — lecciones aprendidas

> Referencia del agente de documentación. Se lee bajo demanda.

Estos son errores reales detectados en proyectos previos. **Antes de entregar un .docx o .pptx, verificar cada uno:**

## 1. Tablas con columnas comprimidas en .docx

**Síntoma:** columnas con headers cortos (`#`, `ID`, `Versión`) quedan invisibles o con texto cortado.

**Causa:** pandoc genera tablas con `tblLayout=fixed` + columnas proporcionales al número de guiones del markdown. Una columna con header `|---|` quedaba en **0.06"** (invisible).

**Solución obligatoria:** `build-doc.sh` debe invocar `postprocess-docx.py` **después** de pandoc. Verificar siempre:

```python
# Validar tras generar:
# 0 tablas con tblLayout=fixed, 0 columnas < 0.27"
```

## 2. Tablas en .pptx con padding insuficiente

**Síntoma:** el texto toca los bordes de la celda, ilegible.

**Solución:** usar `add_table()` de `build-pptx.py` que aplica padding de 90k/50k EMU automáticamente. Si se construye tabla manualmente, replicar este padding.

## 3. Anchos de columna inadecuados en .pptx

**Síntoma:** columnas con texto largo cortado o columnas con poco contenido demasiado anchas.

**Solución:** dejar `col_widths=None` y usar `auto_width=True` en `add_table()` — el helper `_compute_col_widths()` calcula anchos proporcionales al contenido. Si se especifican `col_widths` manuales, verificar que la columna más larga del contenido quepa en su ancho asignado al body_font_size dado.

## 4. Colores del cliente solo en algunos estilos

**Síntoma:** Heading 1-3 corporativos pero Title, Subtitle, TOCHeading, Heading 4-9 con colores Word default (azul `#0F4761`, gris `#595959`).

**Causa:** modificar solo Heading 1-3 ignora que pandoc usa también Title/Subtitle/Author/Date/TOCHeading/Heading 4-9.

**Solución obligatoria:** usar `apply-theme.py` que aplica el color cliente a **TODOS** los styles: Title, Subtitle, Author, Date, Heading 1-9, TOCHeading, Table.

## 5. Colores hardcodeados en build-pptx.py

**Síntoma:** cambiar de cliente requiere modificar 30+ líneas de código.

**Solución obligatoria:** **NUNCA** hardcodear `RGBColor(...)` en `build-pptx.py`. Siempre importar de `theme_colors.py` (generado por `apply-theme.py`).

## 6. Inconsistencia entre .docx y .pptx

**Síntoma:** el .pptx tiene contenido que no está en el .md/.docx (o viceversa).

**Solución obligatoria:** después de modificar un entregable, verificar que el otro tenga el mismo contenido. Ej.: si se agregan "Premisas y Alcance" al .pptx, agregar el §correspondiente al .md.

## 7. Tablas markdown con dashes uniformes

**Síntoma:** `| --- | --- | --- |` produce columnas equidistantes que pandoc respeta literalmente.

**Solución preventiva:** dar dashes proporcionales al ancho esperado:

```markdown
| #    | Descripción larga del campo               | Valor |
| ---- | ----------------------------------------- | ----- |
```

aunque con `postprocess-docx.py` aplicando autofit esto se mitiga, sigue siendo buena práctica para el .md legible en GitHub/VS Code.

## Checklist final antes de entregar

- [ ] `apply-theme.py` ejecutado si hay `client-theme.yaml`
- [ ] `postprocess-docx.py` ejecutado tras pandoc (lo hace `build-doc.sh`)
- [ ] Inspección XML del .docx: 0 tablas con `tblLayout=fixed`
- [ ] Inspección XML del .docx: 0 columnas con ancho < 0.27"
- [ ] Title, Subtitle, TOCHeading en color primary del cliente (no azul Word)
- [ ] Heading 1-5 en color primary/primary_dark (no defaults)
- [ ] .pptx importa de `theme_colors.py` (no hardcodea colores)
- [ ] Contenido del .pptx alineado 1:1 con secciones del .md/.docx
- [ ] Logos del cliente cargados en cada slide (logo izq + der)
- [ ] Validación de canvas .pptx: 0 elementos fuera de 13.33 × 7.50 in

---
