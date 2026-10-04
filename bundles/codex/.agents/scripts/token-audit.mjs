#!/usr/bin/env node
/**
 * token-audit.mjs — mide en que se van los tokens de una sesion de Claude Code.
 *
 * Lee los transcripts JSONL que Claude Code deja en
 * ~/.claude/projects/<slug>/<session>.jsonl y reporta:
 *
 *   - Baseline: cuanto pesa el contexto ANTES de trabajar (system prompt +
 *     definiciones de tools + CLAUDE.md + skills). Es el piso que se paga en
 *     cada request de la sesion.
 *   - Crecimiento por turno y numero de compactaciones.
 *   - Top-N de tool results mas caros: los sumideros concretos que atacar.
 *   - Reparto de tokens por tool.
 *
 * El objetivo es que ninguna optimizacion de contexto se decida por intuicion:
 * primero se mide, despues se toca. Ver docs/adr/008 y el plan de optimizacion.
 *
 * Uso:
 *   node scripts/token-audit.mjs                 # sesiones del proyecto actual
 *   node scripts/token-audit.mjs --top 15        # mas sumideros en el ranking
 *   node scripts/token-audit.mjs --session <id>  # una sesion puntual
 *   node scripts/token-audit.mjs --json          # salida JSON (para baseline)
 *   node scripts/token-audit.mjs --baseline      # guarda docs/token-baseline.json
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

// El proyecto auditado es el de la sesión, no el de este script: instalado como
// plugin, el script vive en el cache del plugin y auditaba ESE directorio, que no
// tiene transcripts. Se corre desde la raíz del proyecto.
const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();

// ─── args ────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const flag = (name, def = undefined) => {
  const i = argv.indexOf(`--${name}`);
  if (i === -1) return def;
  const next = argv[i + 1];
  return next && !next.startsWith('--') ? next : true;
};
const TOP = Number(flag('top', 10));
const AS_JSON = argv.includes('--json');
const SAVE_BASELINE = argv.includes('--baseline');
const ONLY_SESSION = flag('session');

// Claude Code deriva el nombre del directorio del path del proyecto: todo lo que
// no es letra o dígito pasa a guion (medido: `POC — Insight` → `POC---Insight`).
// Reemplazar sólo las barras no encontraba los transcripts de una ruta con
// espacios o puntos.
const projectSlug = (dir) => dir.replace(/[^A-Za-z0-9]/g, '-');
const PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');
const projectDir = flag('project')
  ? path.join(PROJECTS_DIR, String(flag('project')))
  : path.join(PROJECTS_DIR, projectSlug(ROOT));

// ─── helpers ─────────────────────────────────────────────────────────────────
const fmt = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));
const pad = (s, n) => String(s).padEnd(n);
const lpad = (s, n) => String(s).padStart(n);

/** Tamaño aproximado en tokens de un valor arbitrario del transcript. */
function approxTokens(value) {
  if (value == null) return 0;
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  return Math.round(text.length / 4);
}

/** Total de input real de un request: lo cacheado tambien se paga (mas barato). */
function inputTotal(u) {
  return (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
}

// ─── parseo ──────────────────────────────────────────────────────────────────
// Acumula un registro del transcript sobre los tres colectores. Devuelve true si
// el registro es una compactacion, que es el unico contador que no vive en un
// colector propio.
function acumularRegistro(rec, { requests, toolNames, results }) {
  if (rec.type === 'assistant') {
    if (rec.message?.usage) requests.push(rec.message.usage);
    for (const c of rec.message?.content || []) {
      if (c.type === 'tool_use') toolNames.set(c.id, c.name);
    }
    return false;
  }
  if (rec.type === 'user') {
    for (const c of rec.message?.content || []) {
      if (c.type !== 'tool_result') continue;
      results.push({
        tool: toolNames.get(c.tool_use_id) || 'desconocida',
        tokens: approxTokens(c.content),
      });
    }
    return false;
  }
  // Claude Code marca la compactacion como un mensaje de sistema.
  return rec.type === 'system'
    && /compact/i.test(JSON.stringify(rec.subtype ?? rec.content ?? ''));
}

function analyzeSession(file) {
  const id = path.basename(file, '.jsonl');
  const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);

  const requests = [];      // usage por request del asistente
  const toolNames = new Map(); // tool_use_id -> nombre
  const results = [];       // { tool, tokens }
  let compactions = 0;

  for (const line of lines) {
    let rec;
    try { rec = JSON.parse(line); } catch { continue; }
    if (acumularRegistro(rec, { requests, toolNames, results })) compactions++;
  }

  if (!requests.length) return null;

  const inputs = requests.map(inputTotal);
  // El baseline es el request mas chico: el primero de la sesion, antes de que
  // la conversacion acumule. Es el piso fijo que paga TODO request posterior.
  const baseline = Math.min(...inputs);
  const peak = Math.max(...inputs);
  const outputTotal = requests.reduce((a, u) => a + (u.output_tokens || 0), 0);
  const thinking = requests.reduce((a, u) => a + (u.output_tokens_details?.thinking_tokens || 0), 0);
  const inputSum = inputs.reduce((a, b) => a + b, 0);

  const byTool = new Map();
  for (const r of results) {
    const cur = byTool.get(r.tool) || { calls: 0, tokens: 0 };
    cur.calls++; cur.tokens += r.tokens;
    byTool.set(r.tool, cur);
  }

  return {
    session: id,
    mtime: fs.statSync(file).mtime.toISOString(),
    requests: requests.length,
    baselineTokens: baseline,
    peakTokens: peak,
    inputTotal: inputSum,
    outputTotal,
    thinkingTokens: thinking,
    compactions,
    toolResults: results.length,
    toolResultTokens: results.reduce((a, r) => a + r.tokens, 0),
    topSinks: [...results].sort((a, b) => b.tokens - a.tokens).slice(0, TOP),
    byTool: [...byTool.entries()]
      .map(([tool, v]) => ({ tool, ...v }))
      .sort((a, b) => b.tokens - a.tokens),
  };
}

// ─── main ────────────────────────────────────────────────────────────────────
if (!fs.existsSync(projectDir)) {
  console.error(`No hay transcripts en ${projectDir}`);
  console.error('Corré Claude Code en este proyecto al menos una vez.');
  process.exit(1);
}

let files = fs.readdirSync(projectDir)
  .filter((f) => f.endsWith('.jsonl'))
  .map((f) => path.join(projectDir, f));

if (ONLY_SESSION) files = files.filter((f) => f.includes(String(ONLY_SESSION)));
if (!files.length) { console.error('No se encontraron sesiones.'); process.exit(1); }

const sessions = files.map(analyzeSession).filter(Boolean)
  .sort((a, b) => b.mtime.localeCompare(a.mtime));

if (!sessions.length) { console.error('Sesiones sin datos de uso.'); process.exit(1); }

if (AS_JSON) {
  console.log(JSON.stringify({ generatedAt: new Date().toISOString(), sessions }, null, 2));
} else {
  console.log('');
  console.log('TOKEN AUDIT — ' + path.basename(projectDir));
  console.log('='.repeat(78));

  for (const s of sessions) {
    console.log('');
    console.log(`Sesión ${s.session.slice(0, 8)}  ·  ${s.requests} requests  ·  ${s.mtime.slice(0, 16).replace('T', ' ')}`);
    console.log('-'.repeat(78));
    console.log(`  Baseline (piso por request)   ${lpad(fmt(s.baselineTokens), 10)}`);
    console.log(`  Pico de contexto              ${lpad(fmt(s.peakTokens), 10)}`);
    console.log(`  Input acumulado               ${lpad(fmt(s.inputTotal), 10)}`);
    console.log(`  Output  (thinking incluido)   ${lpad(fmt(s.outputTotal), 10)}  (${fmt(s.thinkingTokens)} razonamiento)`);
    console.log(`  Compactaciones                ${lpad(s.compactions, 10)}`);
    console.log(`  Tool results                  ${lpad(fmt(s.toolResultTokens), 10)}  en ${s.toolResults} llamadas`);

    if (s.byTool.length) {
      console.log('');
      console.log('  Reparto por tool:');
      for (const t of s.byTool.slice(0, TOP)) {
        const share = s.toolResultTokens ? Math.round((t.tokens / s.toolResultTokens) * 100) : 0;
        console.log(`    ${pad(t.tool, 34)} ${lpad(fmt(t.tokens), 8)}  ${lpad(t.calls, 4)} llamadas  ${lpad(share + '%', 5)}`);
      }
    }

    if (s.topSinks.length) {
      console.log('');
      console.log(`  Top ${Math.min(TOP, s.topSinks.length)} resultados más caros:`);
      for (const r of s.topSinks) {
        if (!r.tokens) continue;
        console.log(`    ${lpad(fmt(r.tokens), 8)}  ${r.tool}`);
      }
    }
  }
  console.log('');
}

if (SAVE_BASELINE) {
  // `--out` existe para que los tests no escriban sobre el baseline real del repo.
  const out = flag('out') && flag('out') !== true
    ? path.resolve(String(flag('out')))
    : path.join(ROOT, 'docs', 'token-baseline.json');
  const latest = sessions[0];
  const payload = {
    capturedAt: new Date().toISOString(),
    note: 'Baseline de consumo de contexto. Regenerar con: node scripts/token-audit.mjs --baseline',
    session: latest.session,
    baselineTokens: latest.baselineTokens,
    peakTokens: latest.peakTokens,
    requests: latest.requests,
    compactions: latest.compactions,
    toolResultTokens: latest.toolResultTokens,
    byTool: latest.byTool.slice(0, 15),
  };
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(payload, null, 2) + '\n');
  console.log(`Baseline guardado en ${path.relative(ROOT, out)} (piso: ${fmt(latest.baselineTokens)} tok)`);
}
