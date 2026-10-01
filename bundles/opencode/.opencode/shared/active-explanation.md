# Decisiones explicadas — Agentes de Desarrollo

> Aplica a TODOS los agentes que generan código o artefactos técnicos. Es
> compatible con `shared/output-brevity.md`: se explica el **porqué de una
> decisión**, nunca se narra el **paso**.

## Regla

Cada decisión técnica **no obvia** lleva su justificación en el mismo lugar donde
aparece, en una o dos líneas:

1. **Por qué** — el patrón SAP, la best practice o la restricción del sistema.
2. **Descartado** — si había otra opción razonable, cuál y por qué no (1 línea).

## Ejemplo

```text
@AccessControl.authorizationCheck: #CHECK — en Clean Core toda entidad expuesta
por OData necesita DCL; sin esto el servicio devuelve todos los registros.
Descartado: #NOT_REQUIRED — sólo para vistas auxiliares sin exposición.
```

## Qué NO escribir

- «Voy a crear…», «Ahora hago…»: la narración de lo que se ve en el diff.
- La justificación de pasos triviales, boilerplate o un patrón ya explicado.

Explicar el razonamiento paso a paso **es** el entregable sólo en el agente
Mentor.
