// ses-gates.js — puente entre los hooks de OpenCode y las politicas del stack.
//
// GENERADO por emitters/opencode.mjs desde stack.manifest.json. No editar.
//
// OpenCode expone los hooks como plugins JS y se BLOQUEA lanzando una excepcion,
// no devolviendo una decision. El resto del stack habla el contrato ses.hook.v1
// (schemas/ses-hook-v1.schema.json), asi que este archivo traduce en los dos
// sentidos: arma el JSON del contrato, invoca `ses guard`, y convierte un
// `deny` en un throw.
//
// Politicas cubiertas: delivery-gate, protect-sensitive-files, mcp-guard, shrink-input, auto-lint
// NO cubiertos aca (OpenCode no tiene esos eventos): agent-reinforcement (UserPromptSubmit), log-agent-activity (SubagentStop), session-close-note (Stop)
// Ninguno hace cumplir una politica: son comodidades del host de referencia.

import { spawnSync } from "node:child_process";

// Verbos neutrales del nucleo <- nombres de tool de OpenCode.
const VERBO = {
  bash: "exec", read: "read", write: "write", edit: "edit",
  grep: "search", glob: "search", webfetch: "fetch",
};
const verboDe = (t) => (String(t).startsWith("mcp.") ? "mcp" : VERBO[t] ?? null);

const PRE_TOOL = [
  {
    "id": "delivery-gate",
    "verbos": [
      "exec"
    ]
  },
  {
    "id": "protect-sensitive-files",
    "verbos": [
      "write",
      "edit"
    ]
  },
  {
    "id": "mcp-guard",
    "verbos": [
      "mcp"
    ]
  },
  {
    "id": "shrink-input",
    "verbos": [
      "exec"
    ]
  }
];
const POST_TOOL = [
  {
    "id": "auto-lint",
    "verbos": [
      "write",
      "edit"
    ]
  }
];

function consultar(evento, input, output) {
  const verbo = verboDe(input.tool);
  const entrada = JSON.stringify({
    hook_event_name: evento,
    tool_name: input.tool,
    tool_input: output?.args ?? {},
    cwd: process.cwd(),
  });
  const r = spawnSync("npx", ["ses", "guard"], { input: entrada, encoding: "utf8" });
  // El adaptador falla ABIERTO: si `ses` no esta disponible, bloquear cada
  // herramienta dejaria al dev sin poder trabajar, y los niveles de git y CI
  // siguen ahi (ADR-013).
  if (r.error || r.status !== 0) return null;
  try {
    return JSON.parse((r.stdout || "").trim() || "null");
  } catch {
    return null;
  }
}

export const SesGates = async ({ $ }) => ({
  "tool.execute.before": async (input, output) => {
    const d = consultar("PreToolUse", input, output);
    const esp = d?.hookSpecificOutput;
    if (esp?.permissionDecision === "deny") {
      // Un throw es como OpenCode entiende "no procedas".
      throw new Error(esp.permissionDecisionReason || "Bloqueado por la Definition of Done.");
    }
    // `updatedInput` reemplaza los argumentos antes de ejecutar (p. ej. el
    // limite por defecto de una llamada MCP).
    if (esp?.updatedInput && output) Object.assign(output.args, esp.updatedInput);
  },

  "tool.execute.after": async (input, output) => {
    consultar("PostToolUse", input, output);
  },
});
