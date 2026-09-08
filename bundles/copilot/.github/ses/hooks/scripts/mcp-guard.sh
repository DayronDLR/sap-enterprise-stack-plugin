#!/bin/bash
# mcp-guard.sh — pone un techo por defecto a las llamadas MCP que pueden volcar
# miles de filas al contexto.
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
  // El modelo ya eligio un limite: respetarlo.
  if (input[param] !== undefined && input[param] !== null) process.exit(0);

  const updated = { ...input, [param]: value };
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput: updated,
      permissionDecisionReason:
        `[mcp-guard] ${tool} sin ${param}: se aplica ${value} por defecto. ` +
        `Volvé a llamarla con ${param} explícito si necesitás más.`,
    },
  }));
});
' 2>/dev/null || aviso_no_evaluable "el evaluador de limites fallo"

exit 0
