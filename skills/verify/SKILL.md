---
name: verify
description: "Pipeline de verificación de calidad para proyectos SAP CAP + Fiori. Ejecuta CDS lint, ESLint, UI5 linter, manifest validation, tests y build de producción."
disable-model-invocation: true
---

# Verify — Pipeline de Calidad

Ejecutar la pipeline completa de verificación. NO considerar la tarea terminada hasta que todos los checks pasen.

## Step 1: Backend (CAP/CDS)

```bash
npx cds lint
```

## Step 2: JavaScript linting (srv/ + app/)

```bash
npx eslint srv/ app/ --ext .js --no-error-on-unmatched-pattern
```

## Step 3: UI5 Linter (Fiori apps)

```bash
npx @ui5/linter
```

## Step 4: Manifest validation (each UI5 app)

Para cada `manifest.json` encontrado bajo `app/*/webapp/`:
usar `run_manifest_validation` del MCP ui5-mcp.

## Step 5: Tests

```bash
npm test
```

## Step 6: Production build

```bash
cds build --production
```

---

## Manejo de Fallos

Si **cualquier** paso falla:

1. Analizar el error output
2. Fixear el problema
3. Re-ejecutar la **pipeline completa desde Step 1** (no solo el paso que falló)
4. Repetir hasta que todo pase
5. Solo entonces reportar éxito

## Notas

- Si `eslint` no está configurado, saltear Step 2 pero flaggearlo como warning
- Si no hay tests (`npm test` no tiene script), saltear Step 5 pero flaggearlo como warning
- Steps 1-3 son no-negociables — siempre deben correr y pasar
- Si `cds build --production` falla, verificar `cds build` logs para errores de compilación CDS
