---
name: dashboard
description: "Muestra métricas y actividad de los agents del proyecto. Lee los logs de logs/ y presenta un resumen de qué agents corrieron, cuántas veces, y sus últimas actividades."
disable-model-invocation: true
---

# Agent Dashboard

Leer los logs de actividad de agents y presentar un resumen visual.

## Instrucciones

### 1. Leer logs

```bash
# Ver logs de hoy
cat logs/agents-$(date +%Y-%m-%d).jsonl 2>/dev/null || echo "No hay logs de hoy"

# Ver logs de los últimos 7 días
for i in $(seq 0 6); do
    DATE=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)
    if [ -f "logs/agents-$DATE.jsonl" ]; then
        echo "=== $DATE ==="
        cat "logs/agents-$DATE.jsonl"
    fi
done
```

### 2. Generar resumen

Presentar en formato:

```markdown
## 📊 Dashboard de Agents — [fecha]

### Actividad de Hoy
| Agent | Ejecuciones | Última actividad |
|-------|-------------|-----------------|
| architect | X | [timestamp] |
| implementer | X | [timestamp] |
| mentor | X | [timestamp] |
| tester | X | [timestamp] |
| debugger | X | [timestamp] |
| reviewer | X | [timestamp] |

### Actividad Últimos 7 Días
| Día | Total ejecuciones | Agents más usados |
|-----|-------------------|-------------------|
| [fecha] | X | [lista] |
...

### Insights
- Agent más usado: [nombre] ([X] veces)
- Agent menos usado: [nombre] ([X] veces)
- [Cualquier patrón notable, ej: "El debugger se usó 5 veces ayer, posible problema recurrente"]
```

### 3. Revisar decisions.md

También mostrar las últimas decisiones arquitectónicas:

```bash
tail -30 memory/decisions.md 2>/dev/null || echo "No hay decisiones registradas"
```
