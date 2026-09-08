#!/usr/bin/env node
// CLI del motor de diagramas SAP. Cero dependencias: corre con `node` a secas.
//
//   node bin/sapdiag.mjs validate <spec.sapdiag.json> [--quality showcase] [--json]
//   node bin/sapdiag.mjs render   <spec.sapdiag.json> [--out base] [--only drawio|svg]
//   node bin/sapdiag.mjs deliver  <spec.sapdiag.json> [--out base] [--quality showcase] [--json]
//   node bin/sapdiag.mjs doctor
//
// Contrato: exit 0 sin hallazgos bloqueantes, exit 1 con hallazgos, exit 2 por
// error de uso. Un exit distinto de cero NUNCA se reporta como éxito.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { renderDiagram, readSpec, DIAGRAM_TYPES, schemas } from '../lib/render.mjs';
import { assertSupportedVocabulary } from '../lib/schema-validator.mjs';
import { DEFAULT_THRESHOLDS } from '../lib/checks.mjs';
import { deliver } from '../lib/deliver.mjs';
import { iconsAvailable } from '../lib/icons.mjs';
import { detectRasterizer, svgToPng, DEFAULT_PNG_WIDTH } from '../lib/emit-png.mjs';
import { migrarDrawio } from '../lib/migrate-drawio.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const [key, inline] = arg.slice(2).split('=');
      if (inline !== undefined) flags[key] = inline;
      else if (argv[i + 1] && !argv[i + 1].startsWith('--')) { flags[key] = argv[i + 1]; i += 1; }
      else flags[key] = true;
    } else positional.push(arg);
  }
  return { positional, flags };
}

function printDiagnostics(diagnostics) {
  for (const d of diagnostics) {
    const mark = d.severity === 'error' ? 'ERROR' : 'WARN ';
    console.error(`[${mark}] ${d.code}`);
    console.error(`        ${d.message}`);
    if (Object.keys(d.subject).length) console.error(`        dónde: ${JSON.stringify(d.subject)}`);
    if (Object.keys(d.evidence).length) console.error(`        medido: ${JSON.stringify(d.evidence)}`);
    for (const fix of d.supportedFixes) console.error(`        fix: ${fix}`);
  }
}

function usage() {
  console.error(`sapdiag — motor de diagramas SAP (tipos: ${DIAGRAM_TYPES.join(', ')})

  validate <spec.sapdiag.json> [--quality standard|showcase] [--json]
  render   <spec.sapdiag.json> [--out <base>] [--only drawio|svg] [--png] [--width 1600]
  deliver  <spec.sapdiag.json> [--out <base>] [--quality showcase] [--png] [--json]
  migrate  <heredado.drawio> [--out <spec>.sapdiag.json] [--title "..."]
  check-schemas
  doctor

El perfil por defecto sale de meta.quality_profile; --quality lo pisa.`);
}

/**
 * Avisa a stderr cuando el gate corre con umbrales relajados.
 *
 * El receipt ya los registra, pero un receipt que nadie persiste es auditoría
 * que existe en principio y se evapora en la práctica: `build-doc.sh` descarta
 * la salida de `deliver`. Un aviso en el momento de usarlo aparece en el
 * scrollback del dev Y dentro del mensaje del Gate 1, que captura stdout+stderr.
 */
function avisarRelajacion(result) {
  const overrides = result?.metrics?.thresholdOverrides;
  if (!overrides || !Object.keys(overrides).length) return;
  const detalle = Object.entries(overrides)
    .map(([k, v]) => `${k} ${DEFAULT_THRESHOLDS[k]}→${v}`)
    .join(', ');
  const origen = process.env.SAP_DIAGRAMS_CONFIG || 'config/stack.config.json';
  console.error(`[gate relajado] ${detalle} (desde ${origen})`);
}

function commandValidate(file, flags) {
  const spec = readSpec(file);
  const result = renderDiagram(spec, { profile: flags.quality });
  avisarRelajacion(result);
  if (flags.json) {
    console.log(JSON.stringify({
      schemaVersion: 1,
      ok: result.ok,
      stage: result.stage,
      profile: result.profile,
      summary: result.summary,
      metrics: result.metrics,
      diagnostics: result.diagnostics,
    }, null, 2));
  } else {
    console.log(`perfil: ${result.profile} · etapa: ${result.stage} · `
      + `errores: ${result.summary.errors} · warnings: ${result.summary.warnings}`);
    if (result.metrics) console.log(`métricas: ${JSON.stringify(result.metrics)}`);
    printDiagnostics(result.diagnostics);
    console.log(result.ok ? 'VALIDACIÓN OK' : 'VALIDACIÓN FALLIDA');
  }
  return result.ok ? 0 : 1;
}

function commandRender(file, flags) {
  const spec = readSpec(file);
  const result = renderDiagram(spec, { profile: flags.quality });
  if (!result.ok) {
    printDiagnostics(result.diagnostics);
    console.error(`Render rechazado (${result.summary.errors} errores, ${result.summary.warnings} warnings).`);
    return 1;
  }
  const base = flags.out || file.replace(/\.sapdiag\.json$/, '');
  const only = flags.only;
  const written = [];
  if (!only || only === 'drawio') { fs.writeFileSync(`${base}.drawio`, result.drawio()); written.push(`${base}.drawio`); }
  if (!only || only === 'svg' || flags.png) { fs.writeFileSync(`${base}.svg`, result.svg()); written.push(`${base}.svg`); }
  if (flags.png) {
    const png = svgToPng(`${base}.svg`, `${base}.png`, { width: Number(flags.width) || DEFAULT_PNG_WIDTH });
    if (!png.ok) { console.error(png.error); return 1; }
    written.push(`${base}.png (${png.tool})`);
  }
  console.log(`OK ${result.scene.size.width}×${result.scene.size.height}px → ${written.join(', ')}`);
  return 0;
}

function commandDeliver(file, flags) {
  const spec = readSpec(file);
  const receipt = deliver(spec, {
    specPath: file,
    outBase: flags.out,
    profile: flags.quality || spec?.meta?.quality_profile || 'showcase',
    formats: flags.only ? [flags.only] : ['drawio', 'svg', ...(flags.png ? ['png'] : [])],
    pngWidth: Number(flags.width) || DEFAULT_PNG_WIDTH,
  });
  if (flags.json) console.log(JSON.stringify({ schemaVersion: 1, ...receipt }, null, 2));
  else if (!receipt.ok) {
    printDiagnostics(receipt.diagnostics);
    console.error(receipt.note);
  } else {
    console.log(`ENTREGADO · perfil ${receipt.profile} · ${receipt.canvas.width}×${receipt.canvas.height}px`);
    console.log(`spec  sha256=${receipt.spec.sha256} bytes=${receipt.spec.bytes}`);
    for (const a of receipt.artifacts) console.log(`  ${a.path}  sha256=${a.sha256} bytes=${a.bytes}`);
  }
  return receipt.ok ? 0 : 1;
}

/**
 * Los schemas los valida un validador propio que implementa 11 keywords. Si
 * alguien agrega `uniqueItems` u `oneOf`, el archivo AFIRMA una restricción que
 * en runtime se ignora en silencio. Esto lo detecta en CI.
 */
function commandCheckSchemas() {
  const s = schemas();
  let bad = 0;
  for (const name of [...DIAGRAM_TYPES, 'common']) {
    const unknown = assertSupportedVocabulary(s[name]);
    if (unknown.length) {
      bad += 1;
      console.error(`[schemas] ${name} usa keywords que el validador NO implementa: ${unknown.join(', ')}`);
      console.error('          implementalas en lib/schema-validator.mjs o sacalas del schema.');
    }
  }
  if (!bad) console.log(`[schemas] ${DIAGRAM_TYPES.length + 1} schema(s) usan solo vocabulario implementado.`);
  return bad ? 1 : 0;
}

/**
 * Convierte un .drawio heredado en un punto de partida .sapdiag.json.
 *
 * No pretende ser fiel: el .drawio no contiene la semántica que el motor
 * necesita. Los avisos dicen exactamente qué revisar, y el spec sale con
 * `quality_profile: standard` a propósito — subirlo a showcase es una decisión
 * de quien lo revise, no del conversor.
 */
function commandMigrate(file, flags) {
  let xml;
  try {
    xml = fs.readFileSync(file, 'utf8');
  } catch (err) {
    console.error(`No se pudo leer "${file}": ${err.message}`);
    return 1;
  }
  const { spec, avisos } = migrarDrawio(xml, { titulo: flags.title });
  if (!spec.nodes.length) {
    console.error('No se recuperó ningún nodo con texto. ¿Es un .drawio de mxGraph?');
    return 1;
  }
  const salida = flags.out || file.replace(/\.drawio$/, '') + '.sapdiag.json';
  fs.writeFileSync(salida, `${JSON.stringify(spec, null, 2)}\n`);

  console.log(`Migrado a ${salida}: ${spec.nodes.length} nodo(s), ${(spec.edges || []).length} relación(es).`);
  console.log('');
  console.log('REVISAR ANTES DE ENTREGAR:');
  for (const aviso of avisos) console.log(`  - ${aviso}`);
  console.log('');
  console.log(`Después: node bin/sapdiag.mjs validate ${salida} --quality showcase`);
  return 0;
}

function commandDoctor() {
  const s = schemas();
  const lines = [
    `node          ${process.version}`,
    `schemas       ${DIAGRAM_TYPES.map((t) => `${t}(${Object.keys(s[t].properties).length} props)`).join(' ')}`,
    `iconos SAP    ${iconsAvailable() ? 'disponibles' : 'ausentes — los nodos salen como cajas rotuladas'}`,
    `rasterizador  ${detectRasterizer()?.bin ?? 'ninguno — --png no disponible (ver `sapdiag deliver --png`)'}`,
    `ejemplos      ${fs.readdirSync(path.resolve(HERE, '../examples')).filter((f) => f.endsWith('.json')).length}`,
  ];
  console.log(lines.join('\n'));
  return 0;
}

function main() {
  const { positional, flags } = parseArgs(process.argv.slice(2));
  const [command, file] = positional;
  if (!command || flags.help) { usage(); return 2; }

  try {
    if (command === 'doctor') return commandDoctor();
    if (command === 'check-schemas') return commandCheckSchemas();
    if (command === 'migrate') return commandMigrate(file, flags);
    if (!file) { usage(); return 2; }
    if (command === 'validate') return commandValidate(file, flags);
    if (command === 'render') return commandRender(file, flags);
    if (command === 'deliver') return commandDeliver(file, flags);
    usage();
    return 2;
  } catch (err) {
    if (err.diagnostics) { printDiagnostics(err.diagnostics); return 1; }
    console.error(`Fallo no clasificado: ${err.message}`);
    if (process.env.SAPDIAG_DEBUG) console.error(err.stack);
    return 1;
  }
}

process.exit(main());
