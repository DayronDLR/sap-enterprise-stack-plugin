---
applyTo: **/srv/**/*.cds,**/db/**/*.cds,**/mta.yaml,**/package.json
description: Referencia técnica del stack para SAP BTP — arquitectura estándar de un proyecto CAP (estructura de carpetas, srv/db/app, MTA, XSUAA, deployment a Cloud Foundry y Kyma) y modelado en HANA Cloud (Calculation Views, SQLScript, HDI containers, particionado, objetos que produce el agente). Úsalo al diseñar o implementar sobre CAP, BTP o HANA Cloud.
---

# BTP, CAP y HANA — enrutador

Material de referencia de los agentes CAP/BTP y HANA Cloud. Leé el archivo que
la tarea pide, no los dos.

| Vas a… | Leé |
| --- | --- |
| Estructurar un proyecto CAP, MTA, XSUAA, deploy a CF/Kyma | `sap-btp-standards/reference/cap-arquitectura.md` |
| Modelar en HANA: Calculation Views, SQLScript, HDI, particionado | `sap-btp-standards/reference/hana-modelado.md` |

Para concurrencia, batch y baseline de performance en cualquiera de los dos, el
catálogo está en el skill `sap-nfr`.

## Reglas que aplican siempre

**CAP / BTP**

- `@requires` y `@restrict` en TODA acción que modifica estado — sin excepción.
- Una transacción por request: `cds.tx(req)`, nunca compartida entre requests.
- `@odata.etag` en entidades con concurrencia alta.
- Nada de secretos en `package.json`, `mta.yaml` ni `.cds` — van en el servicio
  de destinos o en variables de entorno.
- `$top` / `$skip` en listas; nunca devolver una entidad completa sin paginar.

**HANA**

- Sin `SELECT *` en proyecciones de Calculation Views.
- Cardinalidades declaradas y verificadas en cada join — una cardinalidad mal
  puesta multiplica filas en silencio.
- `SELECT … FOR UPDATE NOWAIT` para reservas de stock o asignación de números.
- Revisar `M_EXPENSIVE_STATEMENTS` y `M_SQL_PLAN_CACHE` antes de pasar a PRD.
