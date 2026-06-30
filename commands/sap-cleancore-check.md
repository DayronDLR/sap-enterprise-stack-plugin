---
model: claude-opus-4-7
---

Ejecuta una **validacion Clean Core** del codigo modificado contra el catalogo oficial SAP.

Scope solicitado:

$ARGUMENTS

## Estado del MCP

No existe MCP oficial SAP para consultar release-state / Clean Core level (gap registrado en `docs/MCP-ROADMAP.md`). La validacion se hace contra fuentes oficiales SAP por lectura manual:

- **SAP API Business Hub**: <https://api.sap.com> — lista de released APIs y BAPIs
- **SAP Help Portal — ABAP Release Notes** por release target (default S/4HANA 2023)
- **ATC en sistema cliente** (transaccion `SCI` / `ATC`) — variante `S4HANA_READINESS_REMOTE` o `S4HANA_CLOUD_DEVELOPMENT`
- Skills locales `sap-abap` y `sap-abap-cds` para guidelines Clean ABAP

## Pasos

1. Si no hay scope, ejecuta `git diff HEAD` para obtener el codigo modificado en la sesion
2. Extrae todos los objetos SAP referenciados (clases `CL_*`, interfaces `IF_*`, tablas, funciones `CALL FUNCTION`, CDS extendidas, BAPIs)
3. Para cada objeto, clasifica usando heuristicas + skills locales:
   - APIs released conocidas (`CL_HTTP_*`, `CL_ABAP_*` publicos, BAPIs Z-safe) → ✅ compliant
   - Acceso directo a tablas SAP estandar (MARA, BKPF, BSEG, VBAK) sin BAPI/API → ❌ no compliant
   - Clases internas `CL_*_INTERNAL` / namespaces SAP `/1*/` → ❌ no compliant
   - Modificaciones a objetos SAP estandar (sin Enhancement Spot / BAdI) → ❌ no compliant
   - Custom Z*/Y* → ❓ revisar caso a caso
4. Para casos dudosos, citar el ATC remoto del cliente como fuente autoritativa

## Salida esperada

```text
🧬 CLEAN CORE COMPLIANCE — [scope]

📦 Objetos analizados: N

✅ RELEASED — N objetos (validados por heuristica + skills locales)
   - CL_HTTP_CLIENT (CLAS) — released, safe en BTP y on-prem
   - API_PURCHASEORDER_PROCESS_SRV (SRVD) — released

⚠️ CLASSIC API — N objetos (solo on-prem, no BTP)
   - BAPI_PO_CREATE (FUNC) — classic, OK S/4 on-prem; en BTP usar API_PURCHASEORDER_PROCESS_SRV

❌ NO COMPLIANT — N objetos (BLOQUEANTE)
   - CL_ABAP_INTERNAL_FOO (CLAS) — clase interna SAP, NO usar
     ↳ Successor: CL_ABAP_PUBLIC_FOO (released, ver SAP API Hub)
   - UPDATE MARA directo — escritura a tabla SAP estandar
     ↳ Usar: BAPI_MATERIAL_SAVEDATA o API_PRODUCT_SRV

⚠️ A VALIDAR EN ATC CLIENTE — N objetos custom dudosos
   - ZCL_CUSTOM_LOGIC — ejecutar variante ATC S4HANA_READINESS_REMOTE

📊 VEREDICTO: ✅ COMPLIANT | ❌ BLOQUEADO (N violaciones) | ⚠️ REQUIERE ATC REMOTO
```

Si hay `❌ NO COMPLIANT`: NO ejecutar `touch tmp/.review-done`. El usuario debe corregir antes de cerrar.
Si hay `⚠️ A VALIDAR EN ATC`: solicitar al usuario ejecutar ATC remoto en sistema cliente antes de sign-off.
Si todo OK: agregar nota "Clean Core OK (validacion heuristica + skills locales)" al review del Stop hook.
