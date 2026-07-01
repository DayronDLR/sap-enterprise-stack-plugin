# Contribuir

¡Gracias por tu interés en el **SAP Enterprise Stack**! 🙌

## Importante: este repo es una distribución generada

Este repositorio contiene el **artefacto construido** del plugin (comandos,
agentes, skills, hooks, MCP). Se **regenera y publica automáticamente** desde un
repositorio de desarrollo separado. Por eso:

- Los archivos acá **no se editan a mano**.
- Los **Pull Requests a este repo no se mergean** (se sobrescriben en la próxima
  publicación).

## Cómo contribuir

- 🐛 **Bugs** → abrí un [issue](../../issues/new/choose) con la plantilla
  *Bug report*.
- 💡 **Ideas / features / nuevos agentes o skills** → issue con *Feature request*.
- ❓ **Preguntas** → un issue con la etiqueta correspondiente.

Para bugs, incluí: **versión del plugin** (la ves con `/plugin`), sistema
operativo, `pnpm --version`, pasos para reproducir y qué esperabas.

## Requisitos del entorno

- `pnpm` en el PATH (los MCP y linters de hooks lo usan).
- Los hooks de calidad son scripts **bash** — en Windows necesitás Git Bash o WSL.

## Licencia

Este proyecto es **GPL-3.0** (copyleft). Al contribuir aceptás que las mejoras
derivadas se distribuyan bajo la misma licencia. Ver [`LICENSE`](LICENSE) y
[`NOTICE`](NOTICE).
