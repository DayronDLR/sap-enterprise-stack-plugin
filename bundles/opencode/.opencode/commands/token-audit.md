---
description: "Mide en qué se van los tokens de la sesión: baseline, sumideros y reparto por tool."
model: anthropic/claude-haiku-4-5-20251001
---
# /token-audit — Dónde se van los tokens

Corré el auditor sobre los transcripts de este proyecto:

```bash
node scripts/token-audit.mjs --top 12
```

Argumentos del usuario: `$ARGUMENTS`

Interpretá la salida para el dev, en este orden:

1. **Baseline** — el piso que se paga en *cada* request de la sesión: system
   prompt + definiciones de tools + `CLAUDE.md` con sus imports + descripciones
   de skills. Es el número que más importa: bajarlo 10k ahorra 10k × N requests.
2. **Pico vs baseline** — cuánto creció la conversación. Si el pico triplica al
   baseline, el problema es acumulación, no configuración.
3. **Compactaciones** — cada una cuesta releer el contexto y generar el resumen.
   Muchas compactaciones en una sesión corta indican `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
   demasiado bajo.
4. **Reparto por tool y top de sumideros** — si un tool concentra el grueso,
   ahí hay que acotar la salida (`| tail`, `--stat`, `$top`, `PACKAGE SIZE`).

Cerrá con **una** recomendación concreta, la de mayor ahorro por esfuerzo. No
enumeres todo lo que se podría hacer.

## Guardar un baseline para comparar

```bash
node scripts/token-audit.mjs --baseline
```

Escribe `docs/token-baseline.json`. Volvé a correrlo después de un cambio de
configuración o de prompts para medir si sirvió — mismo criterio que el baseline
de performance de la NFR §8: sin medición previa no hay comparación posible.