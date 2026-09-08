---
name: sap-nfr
description: Catálogo detallado de requisitos no funcionales del stack SAP — concurrencia y locking por tecnología (ABAP, CAP, HANA, CPI), procesamiento masivo con chunking y restart-ability, smells de performance e índices, observabilidad, volúmenes mínimos de prueba en QAS, y captura de baseline de performance con umbrales de regresión. Úsalo al diseñar o revisar procesos batch, interfaces, jobs y cualquier lógica concurrente.
---

# Requisitos No Funcionales — enrutador

Las **reglas duras** ya están en el contexto (vienen en `shared/non-functional-requirements.md`,
que cada agente carga). Este skill guarda el **detalle**: técnicas concretas por
tecnología, tablas de decisión y umbrales.

Leé solo el archivo que la tarea pide.

| Necesitás… | Leé |
| --- | --- |
| Locking por tecnología: ENQUEUE, `@odata.etag`, `FOR UPDATE`, idempotent receiver | `sap-nfr/reference/concurrencia-locking.md` |
| Chunking, paralelismo, checkpoints, restart-ability, idempotencia | `sap-nfr/reference/batch-masivo.md` |
| Smells de performance, índices secundarios, buffering, observabilidad | `sap-nfr/reference/performance.md` |
| Captura de baseline, métricas por tecnología, umbrales de regresión bloqueantes | `sap-nfr/reference/baseline-performance.md` |
| Volumen mínimo de prueba en QAS por tipo de objeto | `sap-nfr/reference/volumen-pruebas.md` |

## Cuándo cargar cuál

| La tarea es… | Leé al menos |
| --- | --- |
| Un job batch o proceso masivo | `batch-masivo.md` + `concurrencia-locking.md` |
| Una interface o iFlow | `concurrencia-locking.md` |
| Un report o query pesada | `performance.md` + `volumen-pruebas.md` |
| Cualquier cambio a código productivo existente | `baseline-performance.md` |
| Un sign-off de QA | los cinco |

## Regla de cierre

Si alguna respuesta del checklist NFR es "no" o "no sé", la tarea **no está lista**.
Bloquear el cierre y decirlo explícitamente — no asumir que alguien más lo validó.
