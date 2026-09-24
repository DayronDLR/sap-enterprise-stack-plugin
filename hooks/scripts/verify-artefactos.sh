#!/bin/bash
# verify-artefactos.sh
# SubagentStop hook: comprueba que los archivos que el subagente DICE haber
# producido existan de verdad. Recibe el JSON del evento por stdin.
#
# QUE RESUELVE. El contrato de `/sap-techlead` exige que cada subagente cierre
# con `ESTADO: COMPLETADO | Artefactos producidos: [lista]`. Esa linea existe
# desde siempre y nadie la comprueba: un agente que devuelve los hallazgos como
# texto, o que nombra un archivo que no llego a escribir, cierra igual con
# COMPLETADO y el orquestador lo da por bueno.
#
# POR QUE ACA Y NO DENTRO DEL AGENTE. Pedirle al agente que verifique lo que el
# mismo declaro es volver a confiar en una afirmacion. El hook lee el mensaje
# final y resuelve las rutas contra el disco.
#
# NO BLOQUEA, AVISA. `SubagentStop` corre cuando el subagente ya termino: no hay
# nada que impedir. Lo que si se puede es que el orquestador se entere, via
# `additionalContext`, en vez de propagar una tarea que se declaro hecha.

set -u

_VA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_VA_RAIZ="${CLAUDE_PROJECT_DIR:-$(cd "${_VA_DIR}/../.." && pwd)}"
_VA_MOD="${_VA_DIR}/lib/artefactos.mjs"

INPUT=$(cat)

# Sin node no hay verificacion posible. Se avisa por stderr: un control que
# desaparece en silencio deja la impresion de estar cubierto.
if ! command -v node >/dev/null 2>&1; then
    echo "[artefactos] node no disponible: no se verificaron los artefactos declarados." >&2
    exit 0
fi
if [[ ! -f "$_VA_MOD" ]]; then
    echo "[artefactos] no encuentro $_VA_MOD: no se verificaron los artefactos declarados." >&2
    exit 0
fi

# El JSON va por STDIN, no por el entorno.
#
# Pasarlo en una variable exportada lo mete en el bloque de entorno del `exec`,
# que comparte el limite `ARG_MAX` (1 MiB en macOS). Un mensaje final grande
# —una tarea con muchos artefactos, justo la de mas riesgo— hacia fallar el
# `exec` con E2BIG: el hook salia 0, sin verificar y sin `additionalContext`.
# El control desaparecia exactamente donde mas falta hacia.
printf '%s' "$INPUT" | SES_RAIZ="$_VA_RAIZ" SES_MOD="$_VA_MOD" node --input-type=module -e '
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const { rutasDeclaradas, verificarArtefactos, informe } =
  await import(pathToFileURL(process.env.SES_MOD).href);

let crudo = "";
try { crudo = fs.readFileSync(0, "utf8"); } catch { /* sin stdin: nada que leer */ }

let ev = {};
try { ev = JSON.parse(crudo || "{}"); } catch { /* entrada rara: nada que leer */ }
const mensaje = ev.last_assistant_message || ev.lastAssistantMessage || "";

const rutas = rutasDeclaradas(mensaje);
if (!rutas.length) process.exit(0);   // no declaro nada: no hay contrato que verificar

const r = verificarArtefactos(rutas, process.env.SES_RAIZ);
const aviso = informe(r);
if (!aviso) process.exit(0);

process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "SubagentStop", additionalContext: aviso },
}) + "\n");
process.stderr.write(aviso + "\n");
' || {
    # Sin `2>/dev/null`: el stderr de node es el unico lugar donde se ve POR QUE
    # fallo. Taparlo dejaba este mensaje generico como unica senial, que es el
    # modo de falla que este archivo dice querer evitar.
    echo "[artefactos] el verificador falló: no se comprobaron los artefactos declarados." >&2
}

exit 0
