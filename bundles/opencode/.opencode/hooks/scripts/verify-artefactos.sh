#!/bin/bash
# verify-artefactos.sh
# SubagentStop hook: comprueba que lo que el subagente AFIRMA en su mensaje final
# exista de verdad. Recibe el JSON del evento por stdin. Verifica tres cosas:
#
#   - los artefactos que declara producidos (roadmap F1, lib/artefactos.mjs);
#   - las ubicaciones `archivo:línea` que cita como evidencia (roadmap F2,
#     lib/citas.mjs): los hallazgos del reviewer y la evidencia de QA, que son lo
#     que decide si una entrega se sella;
#   - las fuentes oficiales que cita por ID, `[fuente:abap.rap]`, contra el
#     catalogo de `sap-fuentes-de-verdad` (F5), generado en
#     lib/fuentes-catalogo.mjs.
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
_VA_ARTEFACTOS="${_VA_DIR}/lib/artefactos.mjs"
_VA_CITAS="${_VA_DIR}/lib/citas.mjs"
_VA_FUENTES="${_VA_DIR}/lib/fuentes-catalogo.mjs"

INPUT=$(cat)

# Sin node no hay verificacion posible. Se avisa por stderr: un control que
# desaparece en silencio deja la impresion de estar cubierto.
if ! command -v node >/dev/null 2>&1; then
    echo "[artefactos] node no disponible: no se verificaron los artefactos declarados." >&2
    exit 0
fi
if [[ ! -f "$_VA_ARTEFACTOS" || ! -f "$_VA_CITAS" ]]; then
    echo "[artefactos] no encuentro $_VA_ARTEFACTOS o $_VA_CITAS: no se verificaron artefactos, citas ni fuentes." >&2
    exit 0
fi

# El JSON va por STDIN, no por el entorno.
#
# Pasarlo en una variable exportada lo mete en el bloque de entorno del `exec`,
# que comparte el limite `ARG_MAX` (1 MiB en macOS). Un mensaje final grande
# —una tarea con muchos artefactos, justo la de mas riesgo— hacia fallar el
# `exec` con E2BIG: el hook salia 0, sin verificar y sin `additionalContext`.
# El control desaparecia exactamente donde mas falta hacia.
printf '%s' "$INPUT" | SES_RAIZ="$_VA_RAIZ" SES_ARTEFACTOS="$_VA_ARTEFACTOS" SES_CITAS="$_VA_CITAS" SES_FUENTES="$_VA_FUENTES" node --input-type=module -e '
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const { rutasDeclaradas, verificarArtefactos, informe } =
  await import(pathToFileURL(process.env.SES_ARTEFACTOS).href);
const { citasDe, verificarCitas, informeCitas, fuentesDe, fuentesDesconocidas, informeFuentes } =
  await import(pathToFileURL(process.env.SES_CITAS).href);

let crudo = "";
try { crudo = fs.readFileSync(0, "utf8"); } catch { /* sin stdin: nada que leer */ }

let ev = {};
try { ev = JSON.parse(crudo || "{}"); } catch { /* entrada rara: nada que leer */ }
const mensaje = ev.last_assistant_message || ev.lastAssistantMessage || "";

// Cada verificacion corre sola: un agente que no declaro artefactos igual puede
// haber citado evidencia, y al reves. Y una que falla no apaga a la otra: un
// EACCES leyendo una cita dejaba sin verificar tambien los artefactos (F1).
const avisos = [];
const aislada = (nombre, fn) => {
  try { avisos.push(fn()); } catch (e) {
    process.stderr.write(`[${nombre}] el verificador falló: ${e.message}\n`);
  }
};
aislada("artefactos", () => {
  const rutas = rutasDeclaradas(mensaje);
  return rutas.length ? informe(verificarArtefactos(rutas, process.env.SES_RAIZ)) : "";
});
aislada("citas", () => {
  const citas = citasDe(mensaje);
  return citas.length ? informeCitas(verificarCitas(citas, process.env.SES_RAIZ)) : "";
});
// El catalogo se carga aparte y aislado: si falta, se pierde solo esta
// verificacion, no las otras dos. Y se dice al orquestador: callar dejaba leer
// el silencio como "fuentes verificadas".
let catalogo = null;
let errorCatalogo = "";
try {
  ({ FUENTES: catalogo } = await import(pathToFileURL(process.env.SES_FUENTES).href));
  if (!catalogo || typeof catalogo !== "object") throw new Error("el modulo no exporta FUENTES");
} catch (e) {
  errorCatalogo = e.message;
}
aislada("fuentes", () => {
  const ids = fuentesDe(mensaje);
  if (!ids.length) return "";
  if (errorCatalogo) {
    process.stderr.write(`[fuentes] catalogo no disponible (${errorCatalogo}): regeneralo con node scripts/build-fuentes.js\n`);
    return `[fuentes] ${ids.length} fuente(s) citada(s) quedaron SIN VERIFICAR: el catalogo lib/fuentes-catalogo.mjs no cargo. No las tomes como verificadas.`;
  }
  return informeFuentes({ total: ids.length, desconocidas: fuentesDesconocidas(ids, catalogo) });
});
const aviso = avisos.filter(Boolean).join("\n");
if (!aviso) process.exit(0);

process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "SubagentStop", additionalContext: aviso },
}) + "\n");
process.stderr.write(aviso + "\n");
' || {
    # Sin `2>/dev/null`: el stderr de node es el unico lugar donde se ve POR QUE
    # fallo. Taparlo dejaba este mensaje generico como unica senial, que es el
    # modo de falla que este archivo dice querer evitar.
    echo "[artefactos] el verificador falló: no se comprobaron los artefactos ni las citas." >&2
}

exit 0
