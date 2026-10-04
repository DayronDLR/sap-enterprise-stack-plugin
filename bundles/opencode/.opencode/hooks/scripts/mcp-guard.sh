#!/bin/bash
# mcp-guard.sh — politica sobre las llamadas MCP: deniega la escritura en el
# sistema SAP, pide confirmacion para leer datos de tablas, y pone un techo por
# defecto a las llamadas que pueden volcar miles de filas al contexto.
#
# PreToolUse sobre los MCP de SAP. Si el modelo no declaró un limite, se lo
# inyecta via `updatedInput`. Si lo declaró, no se toca: el modelo sabe mejor
# que este hook cuantas filas necesita.
#
# Los nombres de parametro NO estan adivinados: salen del `tools/list` de cada
# servidor (ver docs/adr/009). Un parametro inventado haria fallar la llamada,
# asi que este hook solo actua sobre tools cuyo schema se verifico.
#
# Complementa a MAX_MCP_OUTPUT_TOKENS: esa variable trunca la respuesta DESPUES
# de traerla (se paga la latencia igual); esto evita traerla.
#
# Desactivar: SES_MCP_GUARD=off

set -u

INPUT=$(cat)

# Codex (SES_HOST=codex, lo pone su emisor) no acepta `permissionDecision: ask` ni
# `updatedInput`: los rechaza como no soportados y la llamada seguia SIN control.
# Ahi lo que en Claude es una pregunta se deniega con el motivo y la forma de
# habilitarlo, y el limite de filas se pide en vez de inyectarse.
EN_CODEX=0
# Tambien por `turn_id` en el NIVEL SUPERIOR de la entrada, como verify-artefactos.sh
# y como el evaluador node de abajo: la misma regla en los dos caminos. Se confirma
# con python solo si la subcadena aparece (el caso comun no paga el parseo); sin
# python, la subcadena alcanza: un falso positivo solo endurece, nunca abre.
if [[ "${SES_HOST:-}" = "codex" ]]; then
    EN_CODEX=1
elif [[ "$INPUT" == *'"turn_id"'* ]]; then
    EN_CODEX=1
    if command -v python3 >/dev/null 2>&1; then
        NIVEL=$(printf '%s' "$INPUT" | python3 -I -S -c 'import json,sys
try: print("si" if "turn_id" in json.load(sys.stdin) else "no")
except Exception: print("?")' 2>/dev/null)
        [[ "$NIVEL" = "no" ]] && EN_CODEX=0
    fi
fi
# $1 = que hace la llamada; $2 = en Claude, que confirmar; $3 = en Codex, como
# habilitarlo. Pregunta o deniega segun el host.
preguntar() {
    if [[ $EN_CODEX -eq 1 ]]; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[mcp-guard] %s Codex no puede pedir confirmacion: %s"}}\n' "$1" "$3"
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[mcp-guard] %s %s"}}\n' "$1" "$2"
    fi
}

# ── sap-adt: lista de lo que SÍ se permite ────────────────────────────────────
#
# `sap-adt` (`@mcp-abap-adt/core`) no es de solo lectura: expone tools que crean,
# modifican, activan y borran objetos, toman y liberan locks, crean transportes y
# ejecutan clases y programas ABAP. La documentacion decia "solo lectura por
# diseño" y lo unico que lo sostenia era el prompt del agente ABAP.
#
# La primera version de esta politica fue una lista de verbos PELIGROSOS, y la
# revision encontro enseguida lo que le faltaba: `RuntimeRunProgram` (ejecuta un
# programa ABAP arbitrario) y 31 `Lock*`/`Unlock*`. Una lista de lo peligroso no
# converge; una de lo seguro, si. Lo que no esta aca —incluida cualquier tool
# que una version nueva del paquete agregue— se deniega.
#
# Va ANTES de `SES_MCP_GUARD=off`, que apaga los limites de filas y no esta
# politica. Y es bash puro: un control de escritura no depende de node.
#
#   SES_ADT_WRITE=ask  -> en vez de denegar, pide confirmacion llamada a llamada.
#   SES_ADT_DATA=allow -> leer tablas no pide confirmacion.
# Solo importa si la llamada es a sap-adt: las demas no pagan el parseo.
TOOL_NAME=""
case "$INPUT" in
    *sap?adt__*)
        # El nombre sale del JSON parseado: con el primer match del texto, una
        # clave `tool_name` anidada en `tool_input` podia hacerse pasar por la de
        # verdad. Si no hay python3 o el JSON no parsea, se falla CERRADO: si
        # CUALQUIER `tool_name` del texto es una tool de sap-adt que no es de
        # lectura, esa es la que se evalua.
        if command -v python3 >/dev/null 2>&1; then
            TOOL_NAME=$(printf '%s' "$INPUT" | python3 -I -S -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_name") or "")
except Exception: print("")' 2>/dev/null)
        fi
        if [[ -z "$TOOL_NAME" ]]; then
            CANDIDATOS=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/')
            TOOL_NAME=$(printf '%s\n' "$CANDIDATOS" | grep -E 'sap[-_]adt__' \
                | grep -vE 'sap[-_]adt__(Get|Search|List|Read|Describe|Check|Validate|ResolveTransport|RunUnitTest|RunClassUnitTestsLow|RuntimeAnalyze|RuntimeGet|RuntimeList)' | head -1)
            [[ -z "$TOOL_NAME" ]] && TOOL_NAME=$(printf '%s\n' "$CANDIDATOS" | tail -1)
        fi
        ;;
    *) ;;  # no es sap-adt: no hay nombre que evaluar
esac
if [[ "$TOOL_NAME" =~ ^mcp__.*sap[-_]adt__([A-Za-z0-9_]+)$ ]]; then
    TOOL_ADT="${BASH_REMATCH[1]}"
    ADT_LECTURA_RE='^(Get|Search|List|Read|Describe|Check|Validate|ResolveTransport|RunUnitTest|RunClassUnitTestsLow|RuntimeAnalyze|RuntimeGet|RuntimeList)'
    if [[ ! "$TOOL_ADT" =~ $ADT_LECTURA_RE ]]; then
        if [[ "${SES_ADT_WRITE:-}" = "ask" ]]; then
            preguntar "$TOOL_ADT modifica o ejecuta en el sistema SAP del archivo de SAP_ADT_ENV_PATH." \
                "Confirmá que es DEV y que corresponde." \
                "la escritura en SAP queda denegada en este host; activá el objeto desde ADT."
            exit 0
        fi
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[mcp-guard] %s modifica o ejecuta en el sistema SAP, y el stack usa sap-adt en solo lectura. Entregá el código para activarlo en ADT%s."}}\n' "$TOOL_ADT" "$([[ $EN_CODEX -eq 1 ]] || printf ', o, si la persona lo decide, exportá SES_ADT_WRITE=ask para confirmar cada llamada')"
        exit 0
    fi
    # Leer filas de una tabla las manda al modelo: pueden ser datos personales.
    # La confirmacion no depende de node ni de SES_MCP_GUARD: si alguno de los dos
    # falta, se pide aca y se pierde solo el limite de filas.
    if [[ "$TOOL_ADT" =~ ^(GetTableContents|GetSqlQuery)$ && "${SES_ADT_DATA:-}" != "allow" ]] \
       && { [[ "${SES_MCP_GUARD:-}" = "off" ]] || ! command -v node >/dev/null 2>&1; }; then
        preguntar "$TOOL_ADT lee datos del sistema SAP (pueden ser datos personales)." \
            "Confirmá la lectura; SES_ADT_DATA=allow la habilita sin preguntar." \
            "si la persona lo autoriza, que exporte SES_ADT_DATA=allow y reinicie la sesion."
        exit 0
    fi
fi

[[ "${SES_MCP_GUARD:-}" = "off" ]] && exit 0

# AUDITORIA A6 — este guard tenia cinco salidas con `exit 0` y todas producian el
# mismo resultado observable: permitir. Un guard que NO PUDO evaluar era
# indistinguible de uno que evaluo y aprobo.
#
# La distincion importa:
#   no aplica          -> silencio correcto (la tool no tiene limite conocido)
#   no pude evaluar    -> hay que avisar (falta node, JSON invalido, node crasheo)
#
# No bloquea: este guard solo acota el tamano de un resultado, no hace cumplir una
# politica de la DoD. El nivel correcto es visibilidad, no denegacion.
aviso_no_evaluable() {
    printf '{"systemMessage":%s}\n' \
        "$(printf '%s' "[mcp-guard] no se pudo evaluar el limite de esta llamada MCP: $1. La tool corre sin el limite por defecto." | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s.trim())))' 2>/dev/null || printf '"[mcp-guard] no se pudo evaluar el limite de esta llamada MCP."')"
    exit 0
}

# Fast path: solo tools MCP de SAP con limite conocido. Que no matchee es
# "no aplica", no un fallo.
case "$INPUT" in
    *GetTableContents*|*GetSqlQuery*|*SearchObject*|*search_docs*) ;;
    *) exit 0 ;;
esac

# Node ausente en un stack que corre sobre Node es una anomalia, no un caso
# esperado: se avisa en vez de fingir que se evaluo.
if ! command -v node >/dev/null 2>&1; then
    printf '{"systemMessage":"[mcp-guard] node no esta disponible: no se pudo aplicar el limite por defecto a esta llamada MCP."}\n'
    exit 0
fi

printf '%s' "$INPUT" | node -e '
let raw = "";
process.stdin.on("data", (d) => (raw += d)).on("end", () => {
  let ev;
  try { ev = JSON.parse(raw); } catch {
    // Entrada invalida: no se pudo evaluar. Se avisa y se permite.
    process.stdout.write(JSON.stringify({
      systemMessage: "[mcp-guard] la entrada del hook no es JSON valido: no se pudo aplicar el limite por defecto.",
    }));
    process.exit(0);
  }

  // Nombre corto: mcp__<prefijo>__<Tool> -> <Tool>
  const full = ev.tool_name || "";
  const tool = full.split("__").pop();

  // param -> default. Verificados contra el tools/list de cada servidor.
  const LIMITS = {
    GetTableContents: ["max_rows", 100],
    GetSqlQuery:      ["row_number", 100],
    SearchObject:     ["maxResults", 50],
    search_docs:      ["maxResults", 10],
  };
  const rule = LIMITS[tool];
  if (!rule) process.exit(0);

  const [param, value] = rule;
  const input = ev.tool_input || {};

  // Leer filas de una tabla del cliente las manda al modelo: pueden ser datos
  // personales. Se pide confirmacion, salvo que la persona lo haya habilitado.
  const esSapAdt = /sap[-_]adt__/.test(full);
  const datos = esSapAdt && (tool === "GetTableContents" || tool === "GetSqlQuery")
    && process.env.SES_ADT_DATA !== "allow";
  const conLimite = input[param] !== undefined && input[param] !== null;
  // El modelo ya eligio un limite y no hay nada que confirmar: respetarlo.
  if (conLimite && !datos) process.exit(0);

  // Codex no soporta `ask` ni `updatedInput` (ver EN_CODEX arriba).
  if (process.env.SES_HOST === "codex" || ev.turn_id !== undefined) {
    const motivos = [];
    if (datos) motivos.push(`${tool} lee datos del sistema SAP (pueden ser datos personales). ` +
      "Codex no puede pedir confirmacion: si la persona lo autoriza, que exporte SES_ADT_DATA=allow y reinicie la sesion.");
    if (!conLimite) motivos.push(`${tool} sin ${param}: volvé a llamarla con ${param}: ${value} (o el limite que necesites).`);
    process.stdout.write(JSON.stringify({ hookSpecificOutput: {
      hookEventName: "PreToolUse", permissionDecision: "deny",
      permissionDecisionReason: `[mcp-guard] ${motivos.join(" ")}`,
    } }));
    process.exit(0);
  }

  const salida = { hookEventName: "PreToolUse" };
  const motivos = [];
  if (!conLimite) {
    salida.updatedInput = { ...input, [param]: value };
    motivos.push(`${tool} sin ${param}: se aplica ${value} por defecto. ` +
      `Volvé a llamarla con ${param} explícito si necesitás más.`);
  }
  if (datos) {
    salida.permissionDecision = "ask";
    motivos.push(`${tool} lee datos del sistema SAP (pueden ser datos personales). ` +
      "Confirmá la lectura; SES_ADT_DATA=allow la habilita sin preguntar.");
  }
  salida.permissionDecisionReason = `[mcp-guard] ${motivos.join(" ")}`;
  process.stdout.write(JSON.stringify({ hookSpecificOutput: salida }));
});
' 2>/dev/null || aviso_no_evaluable "el evaluador de limites fallo"

exit 0
