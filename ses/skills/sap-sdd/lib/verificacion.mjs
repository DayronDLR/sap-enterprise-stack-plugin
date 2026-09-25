/**
 * El gate de cada fase y el estado del proyecto, anclados al contenido
 * (ADR-014 §4, fase P2).
 *
 * La idea es la de ADR-011 aplicada a documentos: una aprobación cubre un
 * CONTENIDO, no un momento. Al aprobar una fase se guarda el sha256 de todo lo
 * que consumió —los artefactos de las fases anteriores y, para C1, `entradas/`—
 * y el de sus propios artefactos. Si después cambia cualquiera de los dos, la
 * fase queda vieja sin que nadie tenga que acordarse. Como cada fase consume
 * TODAS las anteriores, reabrir C1 deja viejas C2, C3 y C4 de una vez.
 */
import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

import { CONTRATO, REQUERIMIENTO, MINIMO_CARACTERES, MARCA_PENDIENTE, esIgnorable } from './contrato.mjs';
import { FASES, VERSION_ESTADO, validarNombre, errorDeUso, bloqueEstado } from './proyecto.mjs';
import { leerInventario, verificarEstimacion, riesgosDe, leerSi, rutaSapdiag } from './estimacion.mjs';

const AQUI = path.dirname(fileURLToPath(import.meta.url));

const IDS = FASES.map((f) => f.id);

export function faseValida(id) {
  if (!IDS.includes(id)) throw errorDeUso(`fase inválida: ${JSON.stringify(id)} — usá ${IDS.join(', ')}`);
  return FASES.find((f) => f.id === id);
}

// ── Lectura del proyecto ────────────────────────────────────────────────────

/** Abre un proyecto existente. Lanza si no hay proyecto o si `estado.json` no sirve. */
export function abrirProyecto(raiz, nombre) {
  const malo = validarNombre(nombre);
  if (malo) throw errorDeUso(malo);
  const dir = path.join(path.resolve(raiz), nombre);
  const pEstado = path.join(dir, 'estado.json');
  let texto;
  try { texto = fs.readFileSync(pEstado, 'utf8'); } catch (e) {
    if (e.code === 'ENOENT') throw new Error(`no hay un proyecto SDD en ${dir} (falta estado.json). Crealo con: sdd init ${nombre}`);
    throw e;
  }
  let estado;
  try { estado = JSON.parse(texto); } catch {
    throw new Error(`${pEstado} no es JSON válido. Restauralo desde el último paquete o borralo y corré sdd init (se pierden las aprobaciones)`);
  }
  const mala = formaInvalida(estado);
  if (mala) throw new Error(`${pEstado} no tiene la forma esperada: ${mala}. Restauralo desde el último paquete`);
  return { dir, nombre, estado };
}

const esObjeto = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
const esHuella = (v) => esObjeto(v) && Object.values(v).every((h) => typeof h === 'string' && /^[0-9a-f]{64}$/.test(h));

/**
 * Qué tiene mal `estado.json`, o null. Se valida la forma COMPLETA: con sólo
 * mirar que cada fase fuera un objeto, un `{}` editado a mano borraba una
 * aprobación sin error, y un `consumio: "abc"` reventaba con un TypeError.
 */
function formaInvalida(estado) {
  if (!esObjeto(estado) || estado.version !== VERSION_ESTADO) return `version tiene que ser ${VERSION_ESTADO}`;
  if (!esObjeto(estado.fases)) return 'falta fases';
  for (const id of IDS) {
    const f = estado.fases[id];
    if (!esObjeto(f)) return `falta la fase ${id}`;
    const a = f.aprobacion;
    if (a !== null && !(esObjeto(a) && ['dec', 'fecha', 'decide'].every((k) => typeof a[k] === 'string'))) {
      return `${id}.aprobacion tiene que ser null o { dec, fecha, decide }`;
    }
    if (!esHuella(f.consumio) || !esHuella(f.artefactos)) return `${id}.consumio y ${id}.artefactos tienen que ser { ruta: sha256 }`;
    if (f.lineas !== undefined && !(esObjeto(f.lineas) && Object.values(f.lineas).every((n) => Number.isInteger(n) && n > 0))) {
      return `${id}.lineas tiene que ser { 'RQ-NN': línea }`;
    }
  }
  return null;
}

/**
 * sha256 por bloques: `entradas/` puede traer un PDF de cientos de MB, y leerlo
 * entero para hashearlo costaba su tamaño en memoria (679 MB de RSS medidos con
 * un archivo de 600 MB).
 */
export function sha256(p) {
  const h = createHash('sha256');
  const buf = Buffer.allocUnsafe(1 << 20);
  const fd = fs.openSync(p, 'r');
  try {
    for (let n = fs.readSync(fd, buf); n > 0; n = fs.readSync(fd, buf)) h.update(buf.subarray(0, n));
  } finally {
    fs.closeSync(fd);
  }
  return h.digest('hex');
}

/**
 * Los archivos de un directorio, recursivo, como rutas relativas a `base`, sin
 * lo ignorable. Un symlink no se sigue ni se hashea: se informa, porque un
 * artefacto que apunta afuera no es contenido del proyecto.
 */
export function archivosBajo(base, rel, symlinks) {
  const dir = path.join(base, rel);
  let nombres;
  try { nombres = fs.readdirSync(dir); } catch (e) {
    if (e.code === 'ENOENT') return [];
    throw e;
  }
  const out = [];
  for (const n of nombres.sort()) {
    if (esIgnorable(n)) continue;
    const r = path.posix.join(rel, n);
    const st = fs.lstatSync(path.join(base, r));
    if (st.isSymbolicLink()) symlinks.push(r);
    else if (st.isDirectory()) out.push(...archivosBajo(base, r, symlinks));
    else if (st.isFile()) out.push(r);
  }
  return out;
}

/** Los artefactos presentes de una fase (obligatorios y opcionales), con su hash. */
function huellaDeFase(dir, fase) {
  const c = CONTRATO[fase.id];
  const h = {};
  for (const n of [...c.obligatorios, ...c.opcionales]) {
    const rel = `${fase.dir}/${n}`;
    const p = path.join(dir, rel);
    if (fs.existsSync(p) && fs.lstatSync(p).isFile()) h[rel] = sha256(p);
  }
  return h;
}

/**
 * Lo que la fase consume: los artefactos de TODAS las fases anteriores, y para
 * C1 el contenido de `entradas/`. De `entradas/` sólo sale el hash: el contenido
 * no se lee para otra cosa (ADR-014 §3).
 */
function huellaDeEntradas(dir, fase) {
  const i = IDS.indexOf(fase.id);
  const h = {};
  if (i === 0) {
    for (const r of archivosBajo(dir, 'entradas', [])) h[r] = sha256(path.join(dir, r));
  }
  for (const f of FASES.slice(0, i)) Object.assign(h, huellaDeFase(dir, f));
  return h;
}

/** Qué cambió entre dos huellas, en palabras. */
function diferencias(guardada, actual) {
  const out = [];
  for (const [r, h] of Object.entries(guardada)) {
    if (!(r in actual)) out.push(`${r} se borró`);
    else if (actual[r] !== h) out.push(`${r} cambió`);
  }
  for (const r of Object.keys(actual)) if (!(r in guardada)) out.push(`${r} es nuevo`);
  return out;
}

// ── Estado calculado ────────────────────────────────────────────────────────

/**
 * El estado REAL de cada fase: `pendiente`, `aprobada` o `vieja`, con los
 * motivos. El que dice `estado.json` es el de la última aprobación; éste es el
 * que resulta del contenido de hoy.
 */
export function calcularEstado(proyecto) {
  const { dir, estado } = proyecto;
  const out = {};
  for (const f of FASES) {
    const e = estado.fases[f.id];
    if (!e.aprobacion) { out[f.id] = { estado: 'pendiente', motivos: [] }; continue; }
    const motivos = [
      ...diferencias(e.consumio ?? {}, huellaDeEntradas(dir, f)).map((m) => `entrada: ${m}`),
      ...diferencias(e.artefactos ?? {}, huellaDeFase(dir, f)).map((m) => `propio: ${m}`),
    ];
    out[f.id] = { estado: motivos.length ? 'vieja' : 'aprobada', motivos, aprobacion: e.aprobacion };
  }
  return out;
}

// ── Gate ────────────────────────────────────────────────────────────────────

const RE_CITA = /\[C1-captura\/requerimiento\.md:(\d+)(?:-(\d+))?\]/g;
// Sin `g`: con `g`, `.test` guarda estado entre llamadas y la segunda da falso.
const RE_CITA_UNA = /\[C1-captura\/requerimiento\.md:\d+(?:-\d+)?\]/;
const RE_CITA_ENTRADAS = /\[entradas\/[^\]\n]*\]/g;
/** Una regla del requerimiento: `RQ-` y sólo dígitos, al principio de la línea. */
const RE_RQ = /^RQ-\d+(?![\w-])/;

/** `{ 'RQ-01': 4, ... }`: en qué línea está cada regla. */
export function lineasRq(texto) {
  const out = {};
  lineasDe(texto.replace(/^\uFEFF/, '')).forEach((l, i) => {
    const m = RE_RQ.exec(l);
    if (m && !(m[0] in out)) out[m[0]] = i + 1;
  });
  return out;
}
// Todo lo que PARECE una cita al requerimiento. Lo que matchea esto y no
// RE_CITA está mal escrito (`:  3`, `:3a`, `:tres`) y antes se ignoraba callado.
const RE_CASI_CITA = /\[C1-captura\/requerimiento\.md:[^\]\n]*\]/g;

function lineaDe(texto, indice) {
  return texto.slice(0, indice).split('\n').length;
}

/**
 * El texto sin código: bloques cercados y código inline se reemplazan por
 * espacios, conservando los saltos de línea para que los números de línea de
 * los hallazgos sigan siendo los del archivo. Una cita en un ejemplo de código
 * no es una afirmación: no cuenta para cumplir, ni da un falso "fuera de rango".
 */
export function sinCodigo(texto) {
  const blanco = (m) => m.replace(/[^\n]/g, ' ');
  return texto
    .replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, blanco)
    .replace(/`[^`\n]*`/g, blanco);
}

/** Líneas de un texto como las ve un editor: un salto final no abre otra. */
export function lineasDe(texto) {
  const l = texto.split(/\r?\n/);
  if (l.length > 1 && l[l.length - 1] === '') l.pop();
  return l;
}

/** Hallazgos de citas de un archivo: rotas, a `entradas/`, o faltantes. */
function revisarCitas(rel, original, modo, lineasReq) {
  const texto = sinCodigo(original);
  const h = [];
  for (const m of texto.matchAll(RE_CASI_CITA)) {
    if (!/^\[C1-captura\/requerimiento\.md:\d+(?:-\d+)?\]$/.test(m[0])) {
      h.push(`${rel}:${lineaDe(texto, m.index)} cita mal escrita ${m[0]}: el formato es [${REQUERIMIENTO}:N] o [${REQUERIMIENTO}:N-M]`);
    }
  }
  for (const m of texto.matchAll(RE_CITA_ENTRADAS)) {
    h.push(`${rel}:${lineaDe(texto, m.index)} cita ${m[0]}: las fases posteriores a C1 citan ${REQUERIMIENTO}, nunca entradas/`);
  }
  for (const m of texto.matchAll(RE_CITA)) {
    const problema = destinoDeCita(Number(m[1]), m[2] === undefined ? Number(m[1]) : Number(m[2]), lineasReq);
    if (problema) h.push(`${rel}:${lineaDe(texto, m.index)} cita ${m[0]}: ${problema}`);
  }
  // Un «Fuente: RQ-11» es la forma natural de citar y el gate no la ve: se
  // avisa en vez de ignorarla.
  // Los dos puntos son obligatorios: «Fuente de datos: CDS …» o «- Fuentes
  // primarias del alcance» son prosa, no un intento de citar.
  for (const m of texto.matchAll(/^[ \t>*_-]*(?:\*\*)?Fuentes?(?:\*\*)?\s*:[^\n]*$/gim)) {
    if (!RE_CITA_UNA.test(m[0])) h.push(`${rel}:${lineaDe(texto, m.index)} "Fuente:" sin cita: escribila como [${REQUERIMIENTO}:N]`);
  }
  if (modo === 'alguna' && !RE_CITA_UNA.test(texto)) {
    h.push(`${rel} no cita el requerimiento: toda afirmación funcional lleva [${REQUERIMIENTO}:N] (lo que está entre backticks o en bloques de código no cuenta)`);
  }
  if (modo === 'por-seccion') h.push(...seccionesSinCita(rel, texto));
  return h;
}

/**
 * Qué tiene de malo una cita a las líneas `desde`–`hasta`, o null. Tiene que
 * apuntar a reglas: líneas `RQ-NN` no retiradas. Con sólo exigir que la línea
 * no estuviera vacía, una regla insertada en el medio corría todas las citas
 * siguientes una línea —a un título, o a la regla de al lado— y el gate pasaba.
 */
function destinoDeCita(desde, hasta, lineasReq) {
  if (!lineasReq) return `${REQUERIMIENTO} no existe`;
  if (desde < 1 || hasta < desde || hasta > lineasReq.length) {
    return `fuera de rango (el requerimiento tiene ${lineasReq.length} líneas)`;
  }
  // Las puntas tienen que ser reglas; en el medio se aceptan líneas en blanco,
  // pero no títulos ni reglas retiradas: un rango que las cruza cita ruido.
  for (let n = desde; n <= hasta; n += 1) {
    const l = lineasReq[n - 1];
    const punta = n === desde || n === hasta;
    if (!l.trim()) { if (punta) return `la línea ${n} está vacía`; continue; }
    if (!RE_RQ.test(l)) return `la línea ${n} no es una regla (tiene que empezar con RQ- y sólo dígitos, como RQ-07): «${l.trim().slice(0, 60)}»`;
    if (/\(retirad[oa]\)/i.test(l)) return `la línea ${n} es una regla retirada`;
  }
  return null;
}

/** Cada sección `##` / `###` / `####` con contenido tiene que citar. */
function seccionesSinCita(rel, texto) {
  const h = [];
  const lineas = texto.split('\n');
  let titulo = null;
  let desde = 0;
  let cuerpo = [];
  const cerrar = () => {
    if (titulo && cuerpo.join('\n').trim() && !RE_CITA_UNA.test(cuerpo.join('\n'))) {
      h.push(`${rel}:${desde} la sección "${titulo}" no cita el requerimiento`);
    }
  };
  lineas.forEach((l, i) => {
    const m = /^#{2,4} (.+)$/.exec(l);
    if (m) { cerrar(); titulo = m[1].trim(); desde = i + 1; cuerpo = []; } else if (titulo) cuerpo.push(l);
  });
  cerrar();
  return h;
}

/** Un obligatorio presente: JSON válido, o texto que no sea esqueleto ni esté marcado pendiente. */
function revisarObligatorio(rel, texto) {
  const h = [];
  if (rel.endsWith('.json')) {
    try { JSON.parse(texto); } catch { h.push(`${rel} no es JSON válido`); }
  } else if (texto.trim().length < MINIMO_CARACTERES) {
    h.push(`${rel} tiene ${texto.trim().length} caracteres: es un esqueleto, no un artefacto (mínimo ${MINIMO_CARACTERES})`);
  }
  if (texto.includes(MARCA_PENDIENTE)) h.push(`${rel} tiene la marca ${MARCA_PENDIENTE}: está sin terminar`);
  return h;
}

const UTF8 = new TextDecoder('utf-8', { fatal: true });
function esUtf8(p) {
  try { UTF8.decode(fs.readFileSync(p)); return true; } catch { return false; }
}

/** Completitud, whitelist y citas de los archivos de una fase. */
function revisarArtefactos(dir, fase) {
  const c = CONTRATO[fase.id];
  const h = [];
  const symlinks = [];
  const presentes = new Set(archivosBajo(dir, fase.dir, symlinks).map((r) => r.slice(fase.dir.length + 1)));
  for (const s of symlinks) h.push(`${s} es un symlink: un artefacto tiene que ser un archivo del proyecto`);

  const permitidos = new Set([...c.obligatorios, ...c.opcionales]);
  const lista = [...permitidos].join(', ');
  for (const n of presentes) {
    if (!permitidos.has(n)) h.push(`${fase.dir}/${n} no es un artefacto de ${fase.id} (permitidos: ${lista})`);
  }

  const leer = (n) => fs.readFileSync(path.join(dir, fase.dir, n), 'utf8');
  const noUtf8 = new Set();
  for (const n of c.obligatorios) {
    if (!presentes.has(n)) { h.push(`falta ${fase.dir}/${n}`); continue; }
    if (!esUtf8(path.join(dir, fase.dir, n))) {
      h.push(`${fase.dir}/${n} no es UTF-8: guardalo como UTF-8 (en otro encoding, acentos y citas se leen mal)`);
      noUtf8.add(n);
      continue;
    }
    h.push(...revisarObligatorio(`${fase.dir}/${n}`, leer(n)));
  }

  const pReq = path.join(dir, REQUERIMIENTO);
  const lineasReq = fs.existsSync(pReq) ? lineasDe(fs.readFileSync(pReq, 'utf8').replace(/^\uFEFF/, '')) : null;
  for (const [n, modo] of Object.entries(c.citas)) {
    if (presentes.has(n) && !noUtf8.has(n)) h.push(...revisarCitas(`${fase.dir}/${n}`, leer(n), modo, lineasReq));
  }
  return h;
}

/**
 * El gate de una fase. Devuelve la lista de hallazgos; vacía = pasa.
 *
 * Además de sus propios artefactos exige que TODAS las fases anteriores estén
 * aprobadas y frescas: no se diseña sobre una captura que nadie aprobó, ni
 * sobre una que cambió después de aprobarse. Así se ve la cascada: reabrir C1
 * frena el gate de C2, C3 y C4 hasta que cada una se reaprueba en orden.
 */
export function gate(proyecto, id) {
  const fase = faseValida(id);
  const calc = calcularEstado(proyecto);
  const h = [];
  for (const f of FASES.slice(0, IDS.indexOf(id))) {
    const e = calc[f.id];
    if (e.estado === 'pendiente') h.push(`${f.id} no está aprobada: se aprueba antes de avanzar a ${id}`);
    if (e.estado === 'vieja') h.push(`${f.id} quedó vieja (${e.motivos.join('; ')}): reaprobala antes de avanzar a ${id}`);
  }
  if (id === 'C1') h.push(...reglasDuplicadas(proyecto.dir), ...reglasMovidas(proyecto));
  // Que ESTA fase haya quedado vieja no bloquea su gate: reaprobarla es
  // justamente la salida. Si bloqueara, una fase vieja no se podría reaprobar
  // nunca. La que bloquea es la fase SIGUIENTE, por el chequeo de arriba.
  const artefactos = revisarArtefactos(proyecto.dir, fase);
  h.push(...artefactos);
  // Lo específico de cada fase corre sobre artefactos que ya existen: sobre uno
  // faltante sólo repetiría el "falta".
  if (!artefactos.some((x) => x.startsWith('falta '))) {
    if (id === 'C3') h.push(...revisarDiseno(proyecto.dir));
    if (id === 'C4') h.push(...estimacionDe(proyecto.dir).hallazgos);
  }
  return h;
}

/**
 * C3: el inventario de objetos, y el diagrama validado por el motor de
 * sap-diagrams con el perfil de entrega (showcase). Sin el motor no se puede
 * afirmar que el diagrama se entrega bien: falla cerrado.
 */
function revisarDiseno(dir) {
  const rel = 'C3-diseno/diseno.md';
  const h = [...leerInventario(rel, leerSi(path.join(dir, rel))).hallazgos];
  const spec = path.join(dir, 'C3-diseno/arquitectura.sapdiag.json');
  const motor = rutaSapdiag(AQUI);
  if (!fs.existsSync(motor)) {
    h.push(`no encuentro el motor de diagramas (${motor}): sin él, arquitectura.sapdiag.json se entregaría sin validar`);
    return h;
  }
  const r = spawnSync(process.execPath, [motor, 'validate', spec, '--quality', 'showcase'], { encoding: 'utf8' });
  if (r.status === 1) {
    const detalle = `${r.stdout}${r.stderr}`.split('\n').filter((l) => /ERROR|WARN/.test(l)).slice(0, 5).join(' · ');
    h.push(`C3-diseno/arquitectura.sapdiag.json no pasa el gate de composición de sap-diagrams (perfil showcase): ${detalle || 'corré sapdiag validate para el detalle'}`);
  } else if (r.status !== 0) {
    h.push(`el motor de diagramas falló al validar arquitectura.sapdiag.json (exit ${r.status}): ${(r.stderr || r.stdout).trim().split('\n')[0]}`);
  }
  return h;
}

/** C4: la estimación contra el inventario de C3 y los riesgos del plan. */
export function estimacionDe(dir) {
  // Un archivo que no es UTF-8 ya tiene su hallazgo; parsearlo igual sólo
  // agregaría ruido ("no tiene la tabla…") encima del problema real.
  const rutas = ['C3-diseno/diseno.md', 'C4-plan/estimacion.md', 'C4-plan/plan.md'].map((r) => path.join(dir, r));
  if (rutas.some((p) => fs.existsSync(p) && !esUtf8(p))) return { hallazgos: [], resumen: null };
  const inventario = leerInventario('C3-diseno/diseno.md', leerSi(path.join(dir, 'C3-diseno/diseno.md')));
  return verificarEstimacion({
    rel: 'C4-plan/estimacion.md',
    texto: leerSi(path.join(dir, 'C4-plan/estimacion.md')),
    objetos: inventario.objetos,
    riesgosDelPlan: riesgosDe(leerSi(path.join(dir, 'C4-plan/plan.md'))),
  });
}

/** Líneas del requerimiento citadas por un texto (las dos puntas y lo del medio). */
function lineasCitadas(texto) {
  const out = new Set();
  for (const m of sinCodigo(texto).matchAll(RE_CITA)) {
    const desde = Number(m[1]);
    const hasta = m[2] === undefined ? desde : Number(m[2]);
    for (let n = desde; n <= hasta && n - desde < 1000; n += 1) out.add(n);
  }
  return out;
}

/**
 * Qué reglas citan las fases APROBADAS posteriores a C1, y desde qué archivo:
 * `{ 'RQ-05': 'C2-escenarios/escenarios.md', ... }`. Las líneas citadas se
 * traducen a reglas con las líneas que C1 tenía al aprobarse, que son las que
 * esas fases vieron.
 */
function reglasCitadas(proyecto, guardadas) {
  const porLinea = Object.fromEntries(Object.entries(guardadas).map(([rq, n]) => [n, rq]));
  const citantes = FASES.slice(1)
    .filter((f) => proyecto.estado.fases[f.id].aprobacion)
    .flatMap((f) => Object.keys(proyecto.estado.fases[f.id].artefactos))
    .filter((rel) => rel.endsWith('.md') && fs.existsSync(path.join(proyecto.dir, rel)));
  const out = {};
  for (const rel of citantes) {
    for (const n of lineasCitadas(fs.readFileSync(path.join(proyecto.dir, rel), 'utf8'))) {
      const rq = porLinea[n];
      if (rq && !(rq in out)) out[rq] = rel;
    }
  }
  return out;
}

/**
 * Reglas que una fase aprobada posterior CITA y que cambiaron de línea o
 * desaparecieron desde que se aprobó C1. Las citas son por número de línea:
 * una regla citada que se mueve arrastra la cita, en silencio, a otra cosa. Las
 * que nadie cita se pueden mover: por eso se buscan las citas de verdad en vez
 * de congelar el archivo entero.
 */
function reglasMovidas(proyecto) {
  const guardadas = proyecto.estado.fases.C1.lineas;
  const p = path.join(proyecto.dir, REQUERIMIENTO);
  if (!guardadas || !fs.existsSync(p)) return [];
  const citadas = reglasCitadas(proyecto, guardadas);
  const actuales = lineasRq(fs.readFileSync(p, 'utf8'));
  const h = [];
  for (const [rq, quien] of Object.entries(citadas)) {
    const n = guardadas[rq];
    if (!(rq in actuales)) {
      h.push(`${rq} desapareció de ${REQUERIMIENTO} y ${quien} lo cita: no se borra, se deja como «${rq} (retirado) <motivo>» en su línea ${n}`);
    } else if (actuales[rq] !== n) {
      h.push(`${rq} pasó de la línea ${n} a la ${actuales[rq]} de ${REQUERIMIENTO} y ${quien} lo cita: la cita quedaría corrida. Las reglas nuevas van al final del archivo`);
    }
  }
  return h;
}

/** Códigos `RQ-NN` repetidos: una cita a «la regla RQ-05» sería ambigua. */
function reglasDuplicadas(dir) {
  const p = path.join(dir, REQUERIMIENTO);
  if (!fs.existsSync(p)) return [];
  const vistas = {};
  const h = [];
  lineasDe(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')).forEach((l, i) => {
    const m = RE_RQ.exec(l);
    if (!m) return;
    if (m[0] in vistas) h.push(`${REQUERIMIENTO}:${i + 1} repite ${m[0]} (ya está en la línea ${vistas[m[0]]}): cada regla tiene un código propio`);
    else vistas[m[0]] = i + 1;
  });
  return h;
}

// ── Aprobación ──────────────────────────────────────────────────────────────

export const LOCK_VIEJO_MS = 120_000;

/** ¿El dueño del lock está muerto? Sólo se puede saber en la misma máquina. */
function duenioMuerto(contenido) {
  const [pid, host] = contenido.split('\n');
  if (host !== os.hostname() || !/^\d+$/.test(pid)) return false;
  try { process.kill(Number(pid), 0); return false; } catch (e) { return e.code === 'ESRCH'; }
}

/** ¿Se puede reclamar el lock en `p`? Dueño muerto, o más viejo que el límite. */
function reclamable(p) {
  try {
    return duenioMuerto(fs.readFileSync(p, 'utf8')) || Date.now() - fs.statSync(p).mtimeMs > LOCK_VIEJO_MS;
  } catch (e) {
    if (e.code === 'ENOENT') return true;  // lo soltaron recién
    throw e;
  }
}

/**
 * Una sola escritura a la vez sobre `estado.json` y `decisiones.md`: dos
 * aprobaciones simultáneas numerarían dos DEC iguales.
 *
 * El lock se crea en exclusiva y lleva `pid`, `host` y un token propio. Se
 * reclama si su dueño murió (mismo host, pid inexistente) o si tiene más de
 * `LOCK_VIEJO_MS`.
 *
 * Reclamar es la parte difícil, y dos versiones fallaron medidas:
 *   - "mirar, borrar, crear": el segundo en ver el lock viejo borraba el lock
 *     recién tomado por el primero, y entraban los dos;
 *   - "renombrar y crear": igual de ciego; B juzgaba viejo el lock, A lo
 *     reemplazaba por uno nuevo, y el rename de B se llevaba el de A.
 * Lo que funciona es serializar el reclamo: quien reclama toma primero
 * `.sdd.lock.reclamo` en exclusiva y, YA CON ESE, vuelve a mirar si el lock
 * sigue siendo reclamable. Un lock nuevo sólo se crea después de borrar el
 * viejo, y el viejo sólo se borra bajo el reclamo: nadie borra uno fresco.
 */
export function conLock(dir, fn) {
  const p = path.join(dir, '.sdd.lock');
  const token = randomUUID();
  const tomar = () => fs.writeFileSync(p, `${process.pid}\n${os.hostname()}\n${token}\n`, { flag: 'wx' });
  const ocupado = () => new Error(
    `hay otra operación en curso sobre ${dir} (.sdd.lock). Esperá y reintentá; si no hay otro proceso, ` +
    `el lock se libera solo a los ${LOCK_VIEJO_MS / 60_000} minutos`,
  );
  try { tomar(); } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    if (!reclamable(p)) throw ocupado();
    reclamar(p, token, tomar, ocupado);
  }
  try {
    return fn();
  } finally {
    // Sólo se borra si sigue siendo NUESTRO: si alguien lo reclamó por viejo
    // mientras corríamos, borrarlo le sacaría el lock a él.
    try { if (fs.readFileSync(p, 'utf8').split('\n')[2] === token) fs.rmSync(p, { force: true }); } catch { /* ya no está */ }
  }
}

/** El reclamo de un lock viejo, serializado por `.sdd.lock.reclamo`. Exportado para testearlo. */
export function reclamar(p, token, tomar, ocupado) {
  const r = `${p}.reclamo`;
  try { fs.writeFileSync(r, token, { flag: 'wx' }); } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    // Un reclamo abandonado (su proceso murió en el medio) se limpia para la
    // próxima vez; esta vuelta igual cede.
    try { if (Date.now() - fs.statSync(r).mtimeMs > 30_000) fs.rmSync(r, { force: true }); } catch { /* ya no está */ }
    throw ocupado();
  }
  try {
    if (!reclamable(p)) throw ocupado();
    fs.rmSync(p, { force: true });
    try { tomar(); } catch (e) {
      if (e.code === 'EEXIST') throw ocupado();
      throw e;
    }
  } finally {
    fs.rmSync(r, { force: true });
  }
}

/**
 * Reemplaza `p` entero y de forma atómica (temporal + rename). El temporal usa
 * el patrón de `escribirEntero` (`.<nombre>.<uuid>.tmp`): el gate y el paquete
 * lo ignoran, e `init` limpia los que deja una corrida matada.
 */
function reemplazar(p, contenido) {
  const tmp = path.join(path.dirname(p), `.${path.basename(p)}.${randomUUID()}.tmp`);
  fs.writeFileSync(tmp, contenido, { flag: 'wx' });
  try { fs.renameSync(tmp, p); } catch (e) { fs.rmSync(tmp, { force: true }); throw e; }
}

function siguienteDec(texto) {
  let max = 0;
  // Sin los comentarios: la plantilla trae un `## DEC-001` de ejemplo dentro de
  // uno, y contarlo hacía que la primera decisión real naciera como DEC-002.
  const sinComentarios = texto.replace(/<!--[\s\S]*?-->/g, '');
  for (const m of sinComentarios.matchAll(/^## DEC-(\d+)\b/gm)) max = Math.max(max, Number(m[1]));
  return `DEC-${String(max + 1).padStart(3, '0')}`;
}

function listar(huella) {
  // Los 12 primeros: la huella completa está en estado.json; acá es para leer.
  const filas = Object.entries(huella).map(([r, h]) => `  - \`${r}\` sha256 ${h.slice(0, 12)}…`);
  return filas.length ? filas.join('\n') : '  - (nada)';
}

/**
 * Aprueba una fase: corre el gate y, si pasa, escribe la entrada DEC con los
 * hashes y actualiza `estado.json` y la portada.
 *
 * `decide` es obligatorio y es la persona que aprobó. El agente llama a esto
 * SÓLO después de un sí explícito del arquitecto (ADR-014 §6).
 */
export function aprobar(proyecto, id, { decide, ahora = new Date() }) {
  const fase = faseValida(id);
  if (typeof decide !== 'string' || !decide.trim()) throw errorDeUso('--decide necesita el nombre de quien aprueba');
  return conLock(proyecto.dir, () => {
    // Releer bajo el lock: otra aprobación pudo haber terminado entre medio.
    const p = abrirProyecto(path.dirname(proyecto.dir), proyecto.nombre);
    const hallazgos = gate(p, id);
    if (hallazgos.length) return { aprobada: false, hallazgos };
    // Aprobar otra vez lo mismo no agrega nada: sin esto cada reintento dejaba
    // otra DEC idéntica en el log.
    const actual = calcularEstado(p)[id];
    if (actual.estado === 'aprobada') return { aprobada: true, dec: actual.aprobacion.dec, yaEstaba: true, hallazgos: [] };

    const consumio = huellaDeEntradas(p.dir, fase);
    const artefactos = huellaDeFase(p.dir, fase);
    const pDec = path.join(p.dir, 'decisiones.md');
    const decisiones = fs.existsSync(pDec) ? fs.readFileSync(pDec, 'utf8') : '';
    const dec = siguienteDec(decisiones);
    const fecha = ahora.toISOString().slice(0, 10);
    const entrada = `
## ${dec} — Aprobación de gate ${id}

- **Fecha:** ${fecha}
- **Tipo:** Aprobación de gate
- **Fase:** ${id}
- **Decide:** ${decide.trim()}
- **Artefactos aprobados:**
${listar(artefactos)}
- **Consumió:** ${Object.keys(consumio).length} archivo(s) de las fases anteriores${id === 'C1' ? ' y de entradas/' : ''}
`;
    p.estado.fases[id] = {
      estado: 'aprobada',
      aprobacion: { dec, fecha, decide: decide.trim() },
      consumio,
      artefactos,
      ...(id === 'C1' ? { lineas: lineasRq(fs.readFileSync(path.join(p.dir, REQUERIMIENTO), 'utf8')) } : {}),
    };
    // Orden: primero el log, después el estado. Si algo cae en el medio queda
    // una DEC sin estado —visible y reaprobable—, nunca un estado sin su DEC.
    reemplazar(pDec, `${decisiones.replace(/\n*$/, '\n')}${entrada}`);
    reemplazar(path.join(p.dir, 'estado.json'), `${JSON.stringify(p.estado, null, 2)}\n`);
    actualizarPortada(p);
    return { aprobada: true, dec, hallazgos: [] };
  });
}

/**
 * Reescribe el bloque de estado de la portada con el estado CALCULADO. Si el
 * arquitecto borró los marcadores, no toca el archivo y lo dice.
 */
export function actualizarPortada(proyecto) {
  const p = path.join(proyecto.dir, 'README.md');
  if (!fs.existsSync(p)) return false;
  const texto = fs.readFileSync(p, 'utf8');
  const re = /<!-- sdd:estado -->[\s\S]*?<!-- \/sdd:estado -->/;
  if (!re.test(texto)) return false;
  const calc = Object.fromEntries(Object.entries(calcularEstado(proyecto)).map(([k, v]) => [k, v.estado]));
  const nuevo = texto.replace(re, bloqueEstado(proyecto.estado, calc));
  if (nuevo !== texto) reemplazar(p, nuevo);
  return true;
}
