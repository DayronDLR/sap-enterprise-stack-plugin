// Orquestación del pipeline: spec → schema → layout → ruteo → checks → emisores.
//
// Un solo camino, sin ramas por formato: el .drawio y el .svg salen de la MISMA
// escena ya validada. Es la razón por la que el diagrama del Word y el que el
// cliente abre en draw.io no pueden divergir.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { validateAgainstSchema } from './schema-validator.mjs';
import { DiagnosticBag } from './diagnostics.mjs';
import { layoutArchitecture, finalizeScene } from './layout-architecture.mjs';
import { layoutSequence } from './layout-sequence.mjs';
import { layoutIntegration, finalizeIntegration } from './layout-integration.mjs';
import { layoutLandscape, finalizeLandscape } from './layout-landscape.mjs';
import { translateScene } from './scene.mjs';
import { routeEdges } from './route.mjs';
import { runChecks } from './checks.mjs';
import { emitSvg } from './emit-svg.mjs';
import { emitDrawio } from './emit-drawio.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCHEMA_DIR = path.resolve(HERE, '../schemas');

export const DIAGRAM_TYPES = ['architecture', 'sequence', 'integration', 'landscape'];

let schemaCache = null;

export function schemas() {
  if (schemaCache) return schemaCache;
  const read = (name) => JSON.parse(fs.readFileSync(path.join(SCHEMA_DIR, name), 'utf8'));
  const common = read('common.schema.json');
  schemaCache = {
    store: { 'common.schema.json': common },
    architecture: read('architecture.schema.json'),
    sequence: read('sequence.schema.json'),
    integration: read('integration.schema.json'),
    landscape: read('landscape.schema.json'),
    common,
  };
  return schemaCache;
}

/** Valida el spec contra su schema. Devuelve diagnósticos (vacío si pasa). */
export function validateSpec(spec) {
  const s = schemas();
  const type = spec?.diagram_type;
  if (!DIAGRAM_TYPES.includes(type)) {
    return [{
      code: 'schema/diagram-type',
      severity: 'error',
      message: `diagram_type "${type ?? '(ausente)'}" no está soportado.`,
      subject: { path: '/diagram_type' },
      evidence: { supported: DIAGRAM_TYPES },
      supportedFixes: [`usar uno de ${JSON.stringify(DIAGRAM_TYPES)}`],
    }];
  }
  return validateAgainstSchema(s[type], spec, { store: s.store, diagramType: type });
}

/** Construye la escena posicionada y ruteada. No valida composición. */
export function buildScene(spec) {
  if (spec.diagram_type === 'sequence') {
    const scene = layoutSequence(spec);
    return { scene, routes: scene.routes, problems: scene.problems };
  }
  const porTipo = {
    landscape: [layoutLandscape, finalizeLandscape, 'transports'],
    integration: [layoutIntegration, finalizeIntegration, 'flows'],
    architecture: [layoutArchitecture, finalizeScene, 'edges'],
  };
  const [layout, finalize, campo] = porTipo[spec.diagram_type] || porTipo.architecture;

  const raw = layout(spec);
  const { routes, extraBottom, extraTop } = routeEdges(raw, spec[campo] || []);
  // Si el ruteo usó calles por encima del contenido, la escena baja lo justo
  // para que quepan: reservar ese espacio antes estiraría toda lámina aunque
  // ningún diagrama lo necesite.
  const movida = translateScene(raw, routes, extraTop || 0);
  const scene = finalize(movida.scene, { bottom: extraBottom });
  return { scene, routes: movida.routes, problems: raw.problems };
}

/**
 * Pipeline completo. `ok` es false si hay CUALQUIER error; en `showcase` los
 * warnings también cuentan, porque ese perfil es "esto se entrega al cliente".
 */
export function renderDiagram(spec, { profile } = {}) {
  const schemaDiagnostics = validateSpec(spec);
  if (schemaDiagnostics.length) {
    return {
      ok: false,
      stage: 'schema',
      profile: profile || spec?.meta?.quality_profile || 'standard',
      diagnostics: schemaDiagnostics,
      summary: { errors: schemaDiagnostics.length, warnings: 0 },
      metrics: null,
    };
  }

  const resolved = profile || spec.meta?.quality_profile || 'standard';
  const { scene, routes, problems } = buildScene(spec);

  const bag = new DiagnosticBag();
  for (const p of problems) bag.add({ ...p, severity: 'error' });
  if (bag.errors.length) {
    return {
      ok: false,
      stage: 'model',
      profile: resolved,
      diagnostics: bag.sorted(),
      summary: bag.summary(),
      metrics: null,
    };
  }

  const { bag: checkBag, metrics } = runChecks(scene, routes, { profile: resolved });
  const summary = checkBag.summary();
  const blocked = resolved === 'showcase'
    ? summary.errors > 0 || summary.warnings > 0
    : summary.errors > 0;

  return {
    ok: !blocked,
    stage: 'composition',
    profile: resolved,
    scene,
    routes,
    diagnostics: checkBag.sorted(),
    summary,
    metrics,
    svg: () => emitSvg(scene, routes),
    drawio: () => emitDrawio(scene, routes),
  };
}

/** Lee un `.sapdiag.json` del disco con un diagnóstico honesto si falla. */
export function readSpec(file) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (err) {
    throw Object.assign(new Error(`No se pudo leer "${file}": ${err.message}`), {
      diagnostics: [{
        code: 'input/read',
        severity: 'error',
        message: `No se pudo leer "${file}": ${err.message}`,
        subject: { input: file },
        evidence: { systemCode: err.code },
        supportedFixes: ['pasar la ruta de un archivo .sapdiag.json legible'],
      }],
    });
  }
  try {
    return JSON.parse(text);
  } catch (err) {
    throw Object.assign(new Error(`JSON inválido en "${file}": ${err.message}`), {
      diagnostics: [{
        code: 'input/json-parse',
        severity: 'error',
        message: `JSON inválido en "${file}": ${err.message}`,
        subject: { input: file },
        evidence: { reason: err.message },
        supportedFixes: ['corregir la sintaxis JSON y volver a validar'],
      }],
    });
  }
}
