#!/usr/bin/env node
/**
 * ronda-revision.mjs — qué cambió desde la ronda anterior de un gate.
 *
 * Una entrega que el gate bloquea vuelve a revisarse después de corregir. Sin
 * esto, la segunda ronda relee el diff entero contra HEAD: en la construcción del
 * stack, 2 a 4 rondas por entrega a 150k–290k tokens cada una, la mayoría
 * releyendo archivos que la ronda anterior ya había aprobado.
 *
 * Ciclo de una ronda:
 *   iniciar <gate> --nivel=<n>                     ANTES de lanzar al revisor: fija lo que va a ver
 *   cerrar  <gate> --veredicto=<aprueba|bloquea> [--abiertos=a,b]
 *                                                  al terminar: qué dijo y en qué archivos quedó algo abierto
 *   delta   <gate> --nivel=<n> [--con-hallazgos]   la ronda siguiente: qué revisar
 *
 * Reglas del delta (todas fallan hacia la revisión entera):
 *   - la huella de un archivo es el contenido del ÍNDICE y el del working tree:
 *     lo que publica `git commit` es el índice, y un cambio sólo staged (`MM`)
 *     tiene que aparecer aunque el disco esté igual que antes;
 *   - si la ronda anterior fue más liviana que el nivel de ahora, no acota nada;
 *   - si la ronda anterior bloqueó, sólo acota con `--con-hallazgos`: quien pide
 *     el delta declara que tiene esos hallazgos para pasárselos al revisor (una
 *     sesión nueva no los tiene);
 *   - los archivos con hallazgos abiertos vuelven siempre al delta;
 *   - pasadas 24 h, revisión entera.
 *
 * El delta acota el TRABAJO del revisor, no el sello: `sellar-gate.sh` sigue
 * sellando el árbol entero, y una edición posterior lo invalida igual.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { cambioActual } from './clase-cambio.mjs';
import { NIVELES, desCitar } from './nivel-revision.mjs';

/** Orden por código, no por locale: el delta tiene que salir igual en cualquier máquina. */
const porTexto = (a, b) => (a < b ? -1 : Number(a > b));
const GATES = new Set(['review', 'qa']);
const VEREDICTOS = new Set(['aprueba', 'bloquea']);
/** Una ronda vieja no describe el trabajo de hoy: pasado este plazo, revisión entera. */
export const VIGENCIA_MS = 24 * 60 * 60 * 1000;

function resolverBinario(nombre) {
  for (const dir of String(process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const c = path.join(dir, nombre);
    try { fs.accessSync(c, fs.constants.X_OK); return c; } catch { /* sigue */ }
  }
  return null;
}
const GIT = resolverBinario('git');
const git = (args, input) => execFileSync(GIT, args, { encoding: 'utf8', input, stdio: ['pipe', 'pipe', 'ignore'] });

let raizCache;
const raiz = () => (raizCache ??= git(['rev-parse', '--show-toplevel']).trim());
const archivo = (gate, sufijo = '') => path.join(raiz(), 'tmp', `.ronda-${gate}${sufijo}.json`);

/** ruta → `<blob del índice>:<blob del working tree>` para cada archivo del diff. */
export function huellas(rutas) {
  const dir = raiz();
  const indice = {};
  if (rutas.length) {
    for (const l of git(['-c', 'core.quotePath=false', 'ls-files', '-s', '-z', '--', ...rutas]).split('\0')) {
      const m = /^\d+ ([0-9a-f]+) \d+\t(.+)$/.exec(l);
      if (m) indice[m[2]] = m[1];
    }
  }
  const vivos = rutas.filter((r) => fs.existsSync(path.join(dir, r)));
  const disco = vivos.length
    ? git(['hash-object', '--no-filters', '--stdin-paths'], `${vivos.map((r) => path.join(dir, r)).join('\n')}\n`).trim().split('\n')
    : [];
  const enDisco = Object.fromEntries(vivos.map((r, i) => [r, disco[i]]));
  return Object.fromEntries(rutas.map((r) => [r, `${indice[r] ?? 'sin-indice'}:${enDisco[r] ?? 'borrado'}`]));
}

/** Compara dos mapas de huellas: lo que la ronda anterior NO vio tal como está ahora. */
export function compararHuellas(antes, ahora) {
  const cambiados = Object.keys(ahora).filter((r) => antes[r] !== ahora[r]).sort(porTexto);
  // Un archivo que estaba en el diff y ya no está volvió a como era en HEAD: también cambió.
  const fueraDelDiff = Object.keys(antes).filter((r) => !(r in ahora)).sort(porTexto);
  return { cambiados, fueraDelDiff };
}

const leerJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };
const escribirJson = (f, v) => {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  // Escritura atómica: dos procesos a la vez dejan uno u otro, nunca un JSON partido.
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(v)}\n`);
  fs.renameSync(tmp, f);
};

export function iniciar(gate, nivel, ahora = Date.now()) {
  if (!NIVELES.includes(nivel)) throw new Error(`nivel desconocido: ${nivel}`);
  const rutas = [...cambioActual().keys()].map(desCitar);
  escribirJson(archivo(gate, '.pendiente'), { fecha: ahora, nivel, huellas: huellas(rutas) });
  return { gate, nivel, archivos: rutas.length };
}

/** `srv/a.js:12` o `./srv/a.js` → `srv/a.js`: el revisor cita `archivo:línea`. */
const normalizar = (r) => String(r).trim().replace(/^\.\//, '').replace(/:\d+(:\d+)?$/, '');

export function cerrar(gate, veredicto, abiertosCrudos = []) {
  if (!VEREDICTOS.has(veredicto)) throw new Error(`veredicto desconocido: ${veredicto}`);
  const abiertos = [...new Set(abiertosCrudos.map(normalizar).filter(Boolean))];
  if (veredicto === 'bloquea' && !abiertos.length) {
    throw new Error('una ronda que bloquea tiene que nombrar los archivos con hallazgos abiertos (--abiertos=a,b)');
  }
  const pendiente = leerJson(archivo(gate, '.pendiente'));
  if (!pendiente?.huellas) throw new Error('no hay una ronda iniciada: corré `iniciar` antes de lanzar al revisor');
  escribirJson(archivo(gate), { ...pendiente, veredicto, abiertos });
  fs.rmSync(archivo(gate, '.pendiente'), { force: true });
  return { gate, veredicto, abiertos };
}

export function delta(gate, nivel, { conHallazgos = false, ahora = Date.now() } = {}) {
  const entera = (motivo) => ({ hayRonda: false, motivo });
  const previa = leerJson(archivo(gate));
  if (!previa?.huellas) return entera('no hay ronda anterior: revisión entera');
  // Una fecha en el futuro no es una ronda válida: no puede «no vencer nunca».
  if (!(ahora - previa.fecha < VIGENCIA_MS) || previa.fecha > ahora) return entera('la ronda anterior venció o tiene una fecha inválida: revisión entera');
  if (NIVELES.indexOf(previa.nivel) < NIVELES.indexOf(nivel)) {
    return entera(`la ronda anterior fue '${previa.nivel}' y ahora el cambio exige '${nivel}': revisión entera`);
  }
  if (previa.veredicto === 'bloquea' && !conHallazgos) {
    return entera('la ronda anterior bloqueó y no se pasan sus hallazgos: revisión entera');
  }
  const ahoraHuellas = huellas([...cambioActual().keys()].map(desCitar));
  const { cambiados, fueraDelDiff } = compararHuellas(previa.huellas, ahoraHuellas);
  // Una ruta que sigue en el diff pero no se pudo leer ni en el índice ni en disco
  // (git la citó: comillas, barras, caracteres de control) no tiene huella real:
  // cuenta siempre como cambiada.
  for (const [r, h] of Object.entries(ahoraHuellas)) {
    if (h === 'sin-indice:borrado' && !cambiados.includes(r)) cambiados.push(r);
  }
  // Un hallazgo abierto vuelve siempre, aunque su archivo no haya cambiado. Si no
  // corresponde a ninguna ruta del diff, no se puede garantizar: revisión entera.
  const perdidos = (previa.abiertos || []).filter((r) => !(r in ahoraHuellas) && !fueraDelDiff.includes(r));
  if (perdidos.length) return entera(`hallazgos abiertos en archivos que no están en el diff: ${perdidos.join(', ')}: revisión entera`);
  const abiertos = (previa.abiertos || []).filter((r) => !cambiados.includes(r) && !fueraDelDiff.includes(r));
  return {
    hayRonda: true,
    desde: new Date(previa.fecha).toISOString(),
    veredictoAnterior: previa.veredicto,
    cambiados: [...cambiados, ...abiertos].sort(porTexto),
    fueraDelDiff,
  };
}

const opcion = (args, nombre) => args.find((a) => a.startsWith(`--${nombre}=`))?.slice(nombre.length + 3);

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const [accion, gate, ...resto] = process.argv.slice(2);
  if (!GATES.has(gate) || !['iniciar', 'cerrar', 'delta'].includes(accion)) {
    process.stderr.write('uso: ronda-revision.mjs <iniciar|cerrar|delta> <review|qa> [--nivel=<n>] [--veredicto=<v>] [--abiertos=a,b] [--con-hallazgos]\n');
    process.exit(2);
  }
  try {
    process.chdir(raiz());   // rutas del diff relativas a la raíz, corra desde donde corra
    let r;
    if (accion === 'iniciar') r = iniciar(gate, opcion(resto, 'nivel'));
    else if (accion === 'cerrar') {
      r = cerrar(gate, opcion(resto, 'veredicto'), (opcion(resto, 'abiertos') || '').split(',').filter(Boolean));
    } else r = delta(gate, opcion(resto, 'nivel') || 'completa', { conHallazgos: resto.includes('--con-hallazgos') });
    process.stdout.write(`${JSON.stringify(r)}\n`);
  } catch (e) {
    if (accion !== 'delta') { process.stderr.write(`[ronda] ${e.message}\n`); process.exit(1); }
    // Sin delta calculable, la revisión es entera: nunca se asume que algo ya se vio.
    process.stdout.write(`${JSON.stringify({ hayRonda: false, motivo: `no se pudo calcular: ${e.message}` })}\n`);
  }
}
