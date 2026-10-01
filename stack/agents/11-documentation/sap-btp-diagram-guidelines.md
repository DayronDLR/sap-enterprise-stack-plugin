# SAP BTP Solution Diagram Guidelines (Official)

> Fuente: <https://github.com/SAP/btp-solution-diagrams/blob/main/guideline/docs/>

## Niveles de Diagrama

| Nivel | Audiencia | Detalle |
|-------|-----------|---------|
| **L0** | Business roles, sales, CTO | Overview sin detalles técnicos. Sin legend necesaria, solo descripción breve |
| **L1** | Enterprise architects, solution architects, consultants | Técnico con servicios BTP y flujos principales |
| **L2** | Cloud architects, developers, technical presales | Detalle extenso con protocolos, autenticación, provisioning |

## Atomic Design System

- **Atoms**: Colores, line styles, iconos, texto
- **Molecules**: Elementos compuestos (arrow coloreada, service icon con label)
- **Organisms**: Grupos de molecules (área con servicios y conectores, diagrama completo)

## Colores Oficiales

### Primary (uso principal)

| Uso | Border | Fill | Hex Border | Hex Fill |
|-----|--------|------|------------|----------|
| **SAP/BTP Area** | Azul | Azul claro | `#0070F2` | `#EBF8FF` |
| **Non-SAP Area** | Gris | Gris claro | `#475E75` | `#F5F6F7` |
| **Text Title** | - | - | `#1D2D3E` | - |
| **Text Body** | - | - | `#556B82` | - |

### Semantic (significado de estado)

| Semántica | Border | Fill | Hex Border | Hex Fill |
|-----------|--------|------|------------|----------|
| **Positive/Success** (auth) | Verde | Verde claro | `#188918` | `#F5FAE5` |
| **Critical/Warning** | Naranja | Amarillo claro | `#C35500` | `#FFF8D6` |
| **Negative/Error** | Rojo | Rosa claro | `#D20A0A` | `#FFEAF4` |

### Accent/Emphasized (acento visual)

| Acento | Border | Fill | Hex Border | Hex Fill | Uso típico |
|--------|--------|------|------------|----------|------------|
| **Accent 1 Teal** | Verde azulado | Menta | `#07838F` | `#DAFDF5` | Highlight especial |
| **Accent 2 Indigo** | Violeta | Lavanda | `#5D36FF` | `#F1ECFF` | Authorization, SCIM |
| **Accent 3 Pink** | Magenta | Rosa | `#CC00DC` | `#FFF0FA` | Trust, Network, VPN |

## Estilos de Línea (Connectors)

### Significado obligatorio

- **Solid** = Comunicación directa, síncrona (request-response)
- **Dashed** = Comunicación indirecta, asíncrona
- **Dotted** = Flujos opcionales
- **Thick** = Solo para firewalls

### Colores de connector

- **Gris `#475E75`** = Access, data flow estándar
- **Verde `#188918`** = Authentication (SAML/OIDC)
- **Violeta `#5D36FF`** = Authorization (SCIM, provisioning)
- **Magenta `#CC00DC`** / `#CB00DC` = Trust, mutual trust (bidireccional)
- **Rojo `#D20A0A`** = Error flow
- **Naranja `#C35500`** = Warning flow
- **Teal `#07838F`** = Accent highlight

### Anotaciones estándar

- **Trust Flows** → Pink/Magenta
- **Authentication flows** → Green
- **Authorization flows** → Indigo/Violet
- **Firewalls/Network barriers** → Thick grey lines

## Áreas (Containers)

### Reglas

1. **Corner radius fijo**: 16px recomendado (en draw.io: `arcSize=24; absoluteArcSize=1`)
2. **Alternar fill/no-fill** al anidar áreas para mantener contraste
3. **El parent layer** normalmente es el BTP layer (azul)
4. **Stacking** para mostrar múltiples instancias agrupadas
5. **No sobrecargar** con colores accent — usarlos sparingly

### Patrón de anidamiento

```text
BTP Global (fill=#EBF8FF) → Subaccount (no fill, outline #475E75)
  → Service Area (fill=#EBF8FF) → Inner box (no fill, outline #0070F2)
```

## Iconos

### SAP BTP Service Icons

- **OBLIGATORIO usar versión con círculo gris de fondo** para diagrama
- Disponibles en 3 tamaños: S, M, L
- 100 servicios BTP oficiales

### Generic Icons

- Gradientes suaves en gris neutro
- Para elementos genéricos (devices, databases, users)
- Usar cuando no hay icono específico SAP

## Texto

### 4 estilos jerárquicos (derivados de Fiori Horizon)

1. **Title** (16px, bold, `#1D2D3E`) — nombre de área/servicio principal
2. **Subtitle** (12px, normal, `#1D2D3E`) — descripción secundaria
3. **Body** (10-12px, normal, `#556B82`) — detalles
4. **Caption** (10px, normal, `#556B82`) — labels de connectores

### Fuente: Arial (obligatoria en draw.io)

## Product Names (SAP Brands)

- SAP product names **MUST** ir acompañados del SAP logo
- **No usar demasiados** SAP logos en el mismo diagrama — usar text-only para la mayoría
- Solo los elementos principales llevan el logo SAP

## Legend

- **SIEMPRE incluir legend** en diagramas L1 y L2
- L0 puede omitir legend si el diagrama es simple
- La legend explica el significado de cada color y estilo de línea

## Spacing

- Los elementos deben tener espacio para "respirar"
- Regla de thumb: el espacio alrededor de objetos debe ser parejo y aproximadamente la altura del logo SAP

## REGLAS CRÍTICAS DE XML PARA DRAW.IO (evitar HTML roto)

### Regla 1: html=1 en style SIEMPRE que value tenga tags HTML

```xml
<!-- CORRECTO: value tiene HTML → style tiene html=1 -->
<mxCell value="Subaccount&lt;div&gt;&lt;font&gt;Multi-Cloud&lt;/font&gt;&lt;/div&gt;"
        style="...;html=1;..." />

<!-- CORRECTO: value es texto plano → NO necesita html=1 -->
<mxCell value="CORE Service" style="shape=image;..." />

<!-- INCORRECTO: value tiene HTML pero NO hay html=1 → se muestra el HTML crudo -->
<mxCell value="&lt;b&gt;SAP DOX&lt;/b&gt;" style="shape=image;..." />
```

**REGLA**: Si `value` contiene CUALQUIER tag HTML (`<b>`, `<font>`, `<div>`, `<br>`, `<span>`), entonces `html=1` DEBE estar en `style`. Sin excepción.

### Regla 2: Icon labels deben ser SIMPLES (texto plano o \n)

```xml
<!-- CORRECTO: texto plano sin HTML -->
<mxCell value="CORE Service" style="shape=image;...;fontColor=#1D2D3E;fontSize=12;" />

<!-- CORRECTO: multiline con salto de línea literal -->
<mxCell value="Identity&#10;Directory" style="shape=image;...;fontColor=#1D2D3E;fontSize=12;" />

<!-- CORRECTO: multiline con <br> PERO con html=1 -->
<mxCell value="Application&lt;br&gt;Clients" style="shape=image;...;html=1;fontColor=#1D2D3E;" />

<!-- INCORRECTO: HTML complejo en icon label → se rompe -->
<mxCell value="&lt;b style=&quot;font-family: arial;&quot;&gt;&lt;font color=&quot;#1d2d3e&quot;&gt;SAP DOX&lt;/font&gt;&lt;/b&gt;"
        style="shape=image;..." />
```

**REGLA**: Para icon labels, usar SIEMPRE texto plano con el formato controlado via el `style` attribute (fontColor, fontSize, fontStyle, fontFamily). NUNCA poner `<b>`, `<font>`, `<span>` dentro del value de un icon.

### Regla 3: Áreas con subtítulos usan html=1

```xml
<!-- CORRECTO: área con título bold + subtítulo normal -->
<mxCell value="Subaccount&lt;div&gt;&lt;font style=&quot;font-size: 12px;&quot;&gt;&lt;span style=&quot;font-weight: normal;&quot;&gt;Multi-Cloud&lt;/span&gt;&lt;/font&gt;&lt;/div&gt;"
        style="rounded=1;...;html=1;verticalAlign=top;align=left;fontSize=16;fontStyle=1;spacingLeft=10;spacingTop=10;" />
```

### Regla 4: Text labels usan html=1 con HTML real (no escaped)

En draw.io XML, cuando el value es un atributo del `<mxCell>`:

- Los `<` y `>` del HTML se escriben como `&lt;` y `&gt;` porque están dentro de un atributo XML
- PERO `html=1` en el style le dice a draw.io que interprete esas entidades como HTML

```xml
<!-- Así se ve en el XML raw -->
<mxCell value="&lt;font color=&quot;#1d2d3e&quot;&gt;Legend&lt;/font&gt;"
        style="text;html=1;..." />
<!-- draw.io interpreta el value como: <font color="#1d2d3e">Legend</font> -->
```

### Regla 5: Preferir SIEMPRE la forma más simple

| Necesidad | Solución correcta |
|-----------|------------------|
| Label simple en icon | `value="CORE Service"` sin html=1 |
| Label multiline en icon | `value="Identity&#10;Directory"` sin html=1 |
| Label con color/formato | Usar style: `fontColor=#1D2D3E;fontSize=12;fontStyle=1` |
| Área con subtítulo | value con HTML + `html=1` en style |
| Text label con formato | value con HTML escaped + `html=1;` en style |
| Protocol pill | `value="SAML2/OIDC"` con style de rounded rect |

## Referencia de archivos

Todos dentro de `agents/11-documentation/`:

- **Generador Python**: `tools/sap-drawio-generator.py` — importar `SAPDiagramBuilder`
- **Service icons (100)**: `sap-btp-icons/20-02-99-02-sap-btp-service-icons-all-size-M.xml`
- **Essentials**: `sap-btp-icons/essentials.xml`
- **Area shapes**: `sap-btp-icons/area_shapes.xml`
- **Connectors**: `sap-btp-icons/connectors.xml`
- **Extracted icons (21 SVG)**: `sap-btp-icons/extracted-icons.json`
- **Ejemplos generados**: `examples/01-*.drawio` a `examples/05-*.drawio`
- **Build script**: `tools/build-doc.sh`
