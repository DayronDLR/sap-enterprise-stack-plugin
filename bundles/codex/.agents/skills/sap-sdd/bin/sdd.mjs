#!/usr/bin/env node
// CLI del ciclo SDD (ADR-014). Cero dependencias: corre con `node` a secas.
//
//   node bin/sdd.mjs init       <proyecto> [--raiz <dir>]
//   node bin/sdd.mjs gate       <proyecto> <C1|C2|C3|C4> [--raiz <dir>]
//   node bin/sdd.mjs aprobar    <proyecto> <C1|C2|C3|C4> --decide <nombre> [--raiz <dir>]
//   node bin/sdd.mjs estado     <proyecto> [--raiz <dir>] [--json]
//   node bin/sdd.mjs empaquetar <proyecto> [--raiz <dir>] [--salida <dir>] [--con-entradas]
//   node bin/sdd.mjs raiz
//   node bin/sdd.mjs vigilar-entradas     (rutas por stdin; lo usa el Gate 1)
//
// Contrato: exit 0 si hizo lo pedido, exit 1 si no pudo, exit 2 por error de uso.

import fs from 'node:fs';
import path from 'node:path';
import { crearProyecto, raizSdd, normalizarRuta, errorDeUso, FASES } from '../lib/proyecto.mjs';
import { abrirProyecto, gate, aprobar, calcularEstado, estimacionDe } from '../lib/verificacion.mjs';
import { empaquetar } from '../lib/paquete.mjs';
import { entradasProhibidas } from '../lib/entradas.mjs';

function uso() {
  console.error(`uso: sdd init       <proyecto> [--raiz <dir>]
     sdd gate       <proyecto> <fase> [--raiz <dir>]
     sdd aprobar    <proyecto> <fase> --decide <nombre> [--raiz <dir>]
     sdd estado     <proyecto> [--raiz <dir>] [--json]
     sdd empaquetar <proyecto> [--raiz <dir>] [--salida <dir>] [--con-entradas]
     sdd raiz
     sdd vigilar-entradas   (interno: lo usa el Gate 1; rutas por stdin)

  fases: ${FASES.map((f) => f.id).join(', ')}
  La raíz por defecto es ~/sdd-projects; SES_SDD_HOME (absoluta) o --raiz la cambian.`);
}

/**
 * Parseo estricto: una flag desconocida, una repetida o un argumento de más son
 * error de uso. Ignorarlos en silencio mandaba un proyecto a la carpeta
 * equivocada (`--raiz /a --raiz /b` usaba `/a`) o descartaba un nombre
 * (`init a b` creaba `a`).
 *
 * `spec` mapea cada flag a 'valor' (lleva argumento) o 'bool' (no lleva).
 */
function parsear(args, spec, maxPosicionales) {
  const flags = {};
  const posicionales = [];
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (!a.startsWith('--')) { posicionales.push(a); continue; }
    if (!(a in spec)) throw errorDeUso(`flag desconocida: ${a}`);
    if (a in flags) throw errorDeUso(`${a} aparece más de una vez`);
    if (spec[a] === 'bool') { flags[a] = true; continue; }
    const v = args[i + 1];
    // Un `--x ""` —el `--x "$DIR"` de un script con la variable sin definir—
    // resolvía al cwd y el resultado aparecía en cualquier carpeta.
    if (v === undefined || v.startsWith('--') || !v.trim()) throw errorDeUso(`${a} necesita un valor`);
    flags[a] = v;
    i += 1;
  }
  if (posicionales.length > maxPosicionales) {
    throw errorDeUso(`argumentos de más: ${posicionales.slice(maxPosicionales).join(' ')}`);
  }
  return { flags, posicionales };
}

/** Los errores de E/S de Node dicen qué syscall falló, no qué hacer. */
const ERRORES_DE_ESCRITURA = new Set(['EACCES', 'EPERM', 'EROFS', 'ENOTDIR', 'ENOSPC']);
/** La escritura publica con `link`: hay filesystems (FUSE, 9P, algunos SMB) que no lo tienen. */
const SIN_HARD_LINKS = new Set(['ENOTSUP', 'EOPNOTSUPP', 'EXDEV']);

function explicar(e) {
  if (SIN_HARD_LINKS.has(e.code)) {
    return `el filesystem de ${e.path ?? 'la raíz SDD'} no soporta hard links (${e.code}), y sin ellos no puedo escribir de forma atómica. Usá una raíz en un disco local con --raiz <ruta>`;
  }
  if (ERRORES_DE_ESCRITURA.has(e.code)) {
    return `no puedo escribir en ${e.path ?? 'la raíz SDD'} (${e.code}). Revisá permisos y espacio, o usá otra raíz con --raiz <ruta>`;
  }
  return e.message;
}

// `--raiz` puede ser relativa: la escribió quien corre el comando, desde su
// cwd. SES_SDD_HOME no, porque no se sabe desde dónde se la va a leer.
function raizDe(flags) {
  return flags['--raiz'] === undefined ? raizSdd() : path.resolve(normalizarRuta(flags['--raiz']));
}

/** `<proyecto>` y, si el comando la pide, `<fase>`, abiertos y validados. */
function proyectoDe(args, spec, conFase) {
  const n = conFase ? 2 : 1;
  const { flags, posicionales } = parsear(args, { '--raiz': 'valor', ...spec }, n);
  if (posicionales.length < n) throw errorDeUso(conFase ? 'faltan el proyecto y la fase' : 'falta el nombre del proyecto');
  return { flags, proyecto: abrirProyecto(raizDe(flags), posicionales[0]), fase: posicionales[1] };
}

function init(args) {
  const { flags, posicionales } = parsear(args, { '--raiz': 'valor' }, 1);
  const [nombre] = posicionales;
  if (!nombre) throw errorDeUso('falta el nombre del proyecto');
  const r = crearProyecto({ nombre, raiz: raizDe(flags) });

  if (r.creados.length) console.log(`  creado:    ${r.creados.join(', ')}`);
  if (r.huerfanos.length) console.log(`  limpiado:  ${r.huerfanos.join(', ')} (temporales de una corrida interrumpida)`);
  if (r.existentes.length) console.log(`  ya estaba: ${r.existentes.join(', ')} (no se tocó)`);
  if (r.danados.length) {
    console.error(`✗ ${r.dir}: hay archivos que no sirven y no los piso: ${r.danados.join(', ')}.`);
    console.error('  Revisalos, o borralos y volvé a correr init para regenerarlos.');
    return 1;
  }
  console.log(`${r.creados.length ? '✓ proyecto listo' : '✓ el proyecto ya estaba completo'}: ${r.dir}`);
  console.log(`  la documentación del cliente va en ${path.join(r.dir, 'entradas')}/`);
  return 0;
}

function imprimirHallazgos(titulo, hallazgos) {
  console.error(`✗ ${titulo}: ${hallazgos.length} hallazgo(s)`);
  for (const h of hallazgos) console.error(`  - ${h}`);
}

/** Los números de la estimación, para el juicio del arquitecto. */
function imprimirEstimacion(dir) {
  const { resumen: r } = estimacionDe(dir);
  if (!r) return;
  console.log(`  estimación: base ${r.base} h + contingencia ${r.contingencia} h = ${r.total} h (P80 ${r.p80} h)`);
  console.log(`  rango de las tareas: ${r.optimista}–${r.sumaPesimistas} h`);
  console.log('  el número que se presenta es el total; la suma de pesimistas no es una estimación');
  const top = r.porObjeto.slice(0, 5).map((x) => `${x.obj} ${x.horas} h`).join(', ');
  if (top) console.log(`  por objeto (mayores): ${top}${r.transversal ? `; transversales ${r.transversal} h` : ''}`);
  for (const a of r.avisos) console.log(`  aviso: ${a}`);
}

function cmdGate(args) {
  const { proyecto, fase } = proyectoDe(args, {}, true);
  const h = gate(proyecto, fase);
  if (h.length) {
    imprimirHallazgos(`gate ${fase} de ${proyecto.nombre}`, h);
    // El resumen también mientras se itera: los avisos ayudan a corregir.
    if (fase === 'C4') imprimirEstimacion(proyecto.dir);
    return 1;
  }
  if (fase === 'C4') imprimirEstimacion(proyecto.dir);
  console.log(`✓ gate ${fase} de ${proyecto.nombre}: pasa. Presentá el resumen y pedí la aprobación antes de avanzar.`);
  const propia = calcularEstado(proyecto)[fase];
  if (propia.estado === 'vieja') console.log(`  ${fase} estaba aprobada y quedó vieja (${propia.motivos.join('; ')}): hay que reaprobarla.`);
  return 0;
}

function cmdAprobar(args) {
  const { flags, proyecto, fase } = proyectoDe(args, { '--decide': 'valor' }, true);
  if (flags['--decide'] === undefined) throw errorDeUso('--decide <nombre> es obligatorio: la aprobación la firma una persona');
  const r = aprobar(proyecto, fase, { decide: flags['--decide'] });
  if (!r.aprobada) { imprimirHallazgos(`no se aprueba ${fase}; el gate no pasa`, r.hallazgos); return 1; }
  if (r.yaEstaba) { console.log(`✓ ${fase} ya estaba aprobada como ${r.dec} con este mismo contenido; no se agrega otra decisión`); return 0; }
  console.log(`✓ ${fase} aprobada como ${r.dec} en ${path.join(proyecto.dir, 'decisiones.md')}`);
  return 0;
}

function cmdEstado(args) {
  const { flags, proyecto } = proyectoDe(args, { '--json': 'bool' }, false);
  const calc = calcularEstado(proyecto);
  if (flags['--json']) { console.log(JSON.stringify(calc, null, 2)); return 0; }
  console.log(`${proyecto.nombre} — ${proyecto.dir}`);
  for (const f of FASES) {
    const e = calc[f.id];
    const aprob = e.aprobacion ? ` (${e.aprobacion.dec}, ${e.aprobacion.fecha}, ${e.aprobacion.decide})` : '';
    console.log(`  ${f.id} ${f.titulo.padEnd(11)} ${e.estado}${aprob}`);
    for (const m of e.motivos) console.log(`       · ${m}`);
  }
  return 0;
}

function cmdEmpaquetar(args) {
  const { flags, proyecto } = proyectoDe(args, { '--salida': 'valor', '--con-entradas': 'bool' }, false);
  const salida = flags['--salida'] === undefined ? undefined : path.resolve(normalizarRuta(flags['--salida']));
  const r = empaquetar(proyecto, { conEntradas: Boolean(flags['--con-entradas']), salida });
  console.log(`✓ paquete: ${r.archivo} (${r.archivos} archivos${r.conEntradas ? ', CON entradas/' : ', sin entradas/'})`);
  if (r.pendientes.length) console.log(`  fases pendientes, van como borrador: ${r.pendientes.join(', ')}`);
  if (r.omitidos.length) console.log(`  no incluido (fuera de lo que se presenta): ${r.omitidos.join(', ')}`);
  return 0;
}

/**
 * Lo usa el Gate 1: recibe rutas relativas al cwd (una por línea) y falla si
 * alguna es documentación de un cliente dentro de un proyecto SDD.
 */
function cmdVigilarEntradas(args) {
  parsear(args, {}, 0);
  const rutas = fs.readFileSync(0, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean);
  const malas = entradasProhibidas(rutas.filter((r) => fs.existsSync(r)), (r) => fs.existsSync(r));
  if (!malas.length) return 0;
  console.error('✗ documentación de cliente en entradas/ de un proyecto SDD: no entra a un repo (ADR-014 §3)');
  for (const r of malas) console.error(`  - ${r}`);
  console.error('  Sacala del índice: git rm --cached <ruta>. Queda en disco, fuera del repo.');
  return 1;
}

const COMANDOS = {
  init, gate: cmdGate, aprobar: cmdAprobar, estado: cmdEstado,
  empaquetar: cmdEmpaquetar, 'vigilar-entradas': cmdVigilarEntradas,
};

function main(argv) {
  const [cmd, ...resto] = argv;
  try {
    if (cmd === 'raiz') { parsear(resto, {}, 0); console.log(raizSdd()); return 0; }
    if (['-h', '--help', 'help'].includes(cmd)) { uso(); return 0; }
    if (cmd === undefined) throw errorDeUso('falta el comando');
    if (!Object.hasOwn(COMANDOS, cmd)) throw errorDeUso(`comando desconocido: ${cmd}`);
    return COMANDOS[cmd](resto);
  } catch (e) {
    console.error(`✗ ${explicar(e)}`);
    if (e.uso) { uso(); return 2; }
    return 1;
  }
}

process.exitCode = main(process.argv.slice(2));
