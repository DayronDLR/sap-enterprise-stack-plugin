---
name: memory-compress
description: "Comprime archivos .md en memory/ para reducir uso de contexto. Preserva frontmatter YAML, bloques de código, términos SAP técnicos, paths y URLs. Hace backup de originales."
model: sonnet
---

# Memory Compress

Comprimir archivos `.md` en el directorio `memory/` del proyecto para reducir el consumo de ventana de contexto. Meta: ~40% de reducción manteniendo toda la información técnica.

## Qué preservar SIEMPRE (nunca comprimir)

- Bloques de código (fenced `` ``` `` e indentados)
- Frontmatter YAML (entre `---`)
- Términos SAP técnicos exactos: BAdI, CDS, RAP, RFC, BAPI, XSUAA, MTA, HDI, AMDP, ABAP, OData, Fiori, BTP, S/4HANA, CAP, CPI, iFlow
- Paths de archivo, comandos shell, nombres de función/clase
- URLs completas
- Números de versión, IDs de transport request, nombres de sistema (DEV/QAS/PRD)
- Líneas de frontmatter (`name:`, `description:`, `type:`)

## Qué comprimir

- Frases introductoras redundantes ("Es importante destacar que...", "Cabe mencionar que...")
- Explicaciones de contexto ya conocido (el stack es SAP BTP — no necesita reexplicarse)
- Sinónimos consecutivos ("verificar y validar y comprobar" → "verificar")
- Párrafos de cierre generéricos sin información nueva

## Instrucciones paso a paso

### 1. Listar archivos objetivo

```bash
ls memory/*.md 2>/dev/null | grep -v '\.original\.md$'
```

Si no hay archivos: reportar "No hay archivos en memory/ para comprimir" y terminar.

### 2. Por cada archivo `.md` encontrado

**a. Leer el archivo**

**b. Hacer backup del original**

```bash
cp memory/ARCHIVO.md memory/ARCHIVO.original.md
```

**c. Comprimir el contenido** respetando las reglas de preservación de arriba.

**d. Escribir el archivo comprimido** en la misma ruta (`memory/ARCHIVO.md`).

**e. Verificar integridad**: el archivo comprimido debe tener el mismo frontmatter que el original y no puede haber perdido términos SAP críticos del original.

### 3. Reportar resultado

Para cada archivo procesado, mostrar:

```
✓ memory/ARCHIVO.md: XXX → YYY líneas (−ZZ%)
  Backup: memory/ARCHIVO.original.md
```

Y al final: total de archivos procesados y reducción promedio.

## Condiciones de error

- Si un archivo tiene menos de 10 líneas: omitir (no vale la pena comprimir)
- Si la compresión resultante es mayor al original: descartar y restaurar el original
- Si el archivo contiene solo frontmatter y código: omitir
