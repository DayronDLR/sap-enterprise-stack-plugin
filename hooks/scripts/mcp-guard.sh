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

# Fast path: solo tools MCP de SAP con limite conocido.
case "$INPUT" in
    *GetTableContents*|*GetSqlQuery*|*SearchObject*|*search_docs*) ;;
    *) exit 0 ;;
esac

command -v node >/dev/null 2>&1 || exit 0

printf '%s' "$INPUT" | node -e '
let raw = "";
process.stdin.on("data", (d) => (raw += d)).on("end", () => {
  let ev;
  try { ev = JSON.parse(raw); } catch { process.exit(0); }

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
' 2>/dev/null || exit 0

exit 0
