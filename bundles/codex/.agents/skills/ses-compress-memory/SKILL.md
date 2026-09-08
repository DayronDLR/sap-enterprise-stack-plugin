---
name: ses-compress-memory
description: Comprime archivos memory/*.md para reducir uso de ventana de contexto
---
> Generado por `emitters/codex.mjs` desde `stack.manifest.json`.
> En Codex los prompts personalizados están deprecados: los comandos del
> stack se invocan como skills, con `$ses-compress-memory`.
Usa el skill `memory-compress` para comprimir todos los archivos `.md` en el directorio `memory/`.

Instrucciones:

1. Ejecutar las instrucciones del skill `memory-compress` (en `skills/memory-compress/SKILL.md`)
2. Reportar reducción por archivo y total al finalizar
3. No eliminar los backups `.original.md` generados — quedan como respaldo