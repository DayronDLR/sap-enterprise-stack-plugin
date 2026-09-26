/**
 * citas.mjs — comprueba que las ubicaciones `archivo:línea` que cita un
 * subagente existan de verdad (roadmap F2).
 *
 * POR QUE EXISTE. El reviewer tiene que dar "archivo:línea exacto" en cada
 * hallazgo, y QA responde "con evidencia". Son las citas que deciden si una
 * entrega se sella: un hallazgo CRITICAL sobre una línea que no existe, o un
 * "OK, verificado en `srv/x.js:120`" sobre un archivo de 80 líneas, pasaban
 * igual. Nadie comprobaba que la cita apuntara a algo.
 *
 * Lo mismo que F1 con los artefactos: no se aprueba una afirmación, se resuelve
 * el hecho. Y en el hook, no en el agente: pedirle al autor que verifique su
 * propia cita es volver a confiar en él.
 *
 * QUE VERIFICA, Y QUE NO. Que el archivo exista dentro del proyecto y que la
 * línea (o el rango) esté dentro del archivo. No que la línea diga lo que el
 * agente le atribuye: eso es juicio, y lo sigue haciendo quien lee.
 *
 * LOS DOS MODOS DE FALLA, como en F1:
 *
 *   - Falso NEGATIVO: una cita que el parser no ve no se verifica. Se aceptan las
 *     formas que un modelo escribe —`x.js:42`, `x.js:42-50` (también con raya),
 *     `x.js:42:7`, `x.js#L42`, `x.js (línea 42)`, con backslashes de Windows,
 *     con acentos y ñ— en prosa, entre backticks o en un link.
 *   - Falso POSITIVO: reportar "no existe" sobre algo que existe, o sobre algo
 *     que ni era una cita, entrena al orquestador a ignorar el aviso. Por eso no
 *     cuentan los bloques de código ni los marcos de un stack trace; una cita
 *     relativa a una subcarpeta se resuelve por sufijo; y lo ambiguo, lo de fuera
 *     del proyecto o lo que no se pudo leer no se afirma roto.
 *
 * Nunca rompe: un error leyendo una cita la deja "sin verificar", no apaga la
 * verificación de las demás ni la de artefactos que corre al lado.
 *
 * Sin git: el plugin no trae `scripts/`, y el hook tiene que andar en cualquier
 * proyecto donde esté instalado.
 */
import fs from 'node:fs';
import path from 'node:path';

/** Lo que puede formar un nombre: letras y dígitos de cualquier alfabeto (pédido, año). */
const C = String.raw`[\p{L}\p{N}_.@-]`;
/**
 * El último segmento de una ruta: con extensión (hasta 20 caracteres, por
 * `.hdbcalculationview`, que tiene 18), un dotfile (`.gitignore`), o un nombre
 * conocido sin extensión.
 */
const FINAL = String.raw`(?:[\p{L}\p{N}_@-]${C}*\.\p{L}[\p{L}\p{N}]{0,19}|\.[\p{L}\p{N}_-]${C}*|Makefile|Dockerfile|Jenkinsfile|Procfile)`;
/** Dentro de una carpeta oculta (`.husky/pre-commit`, `.github/CODEOWNERS`) el archivo no suele tener extensión. */
const OCULTA = String.raw`\.[\p{L}\p{N}_-]${C}*\/(?:${C}+\/)*[\p{L}\p{N}_@-]${C}*`;
const ARCHIVO = String.raw`(?:\/?(?:${C}+\/)*${FINAL}|${OCULTA})`;
/**
 * Una cita no empieza después de una letra, un dígito, `/`, `:`, `.`, `@`, `-` o
 * `\`: así un host o una ruta de URL (`https://api.sap.com:443`) no se toma por
 * una ubicación del proyecto. El `@` además evita que una corrida de `@@@…`
 * haga cuadrática la búsqueda.
 */
const ANTES = String.raw`(?<![\p{L}\p{N}_\/.:@\\-])`;
/** `x.js:42`, `x.js:42-50`, `x.js:42:7`. Un punto final cierra la oración, no la cita. */
const RE_DOS_PUNTOS = new RegExp(String.raw`${ANTES}(${ARCHIVO}):(\d+)(?:-(\d+))?(?::\d+)?(?![\p{L}\p{N}_]|\.\d)`, 'gu');
/** `x.js#L42`, `x.js#L42-L50`: el formato de GitHub y de los links de VS Code. */
const RE_ANCLA = new RegExp(String.raw`${ANTES}(${ARCHIVO})#L(\d+)(?:-L?(\d+))?(?![\p{L}\p{N}_])`, 'gu');
/** `x.js (línea 42)`, `x.js (líneas 42-50)`, `x.js (line 42)`. */
const RE_PALABRA = new RegExp(String.raw`${ANTES}(${ARCHIVO})\s*\((?:l[ií]neas?|lines?)\s+(\d+)(?:\s*-\s*(\d+))?\)`, 'giu');

/** Directorios que no son del proyecto, o que son salida: no se indexan. */
const NO_INDEXAR = new Set(['node_modules', '.git', '.claude', 'coverage', 'dist', '.next', '.cache']);
/** Techo del índice: un proyecto más grande se verifica sólo por ruta exacta. */
const MAX_INDICE = 50_000;
/** Un archivo más grande no se recorre para contar líneas. */
const MAX_BYTES = 100 * 1024 * 1024;
/** Lo que se escanea del mensaje: más no es un reporte, y el tiempo del hook tiene techo. */
export const MAX_TEXTO = 256 * 1024;

/**
 * El mensaje, listo para buscar citas: sin bloques de código (también los
 * sangrados dentro de una lista), sin marcos de stack trace, con las rayas de
 * un rango (`42–50`, que pone el autocorrector) como guion y con los
 * backslashes de una ruta de Windows como barras.
 */
export function normalizar(mensaje) {
  return String(mensaje || '').slice(0, MAX_TEXTO)
    .replace(/^([ \t]*)(```|~~~)[^\n]*\n[\s\S]*?^[ \t]*\2[^\n]*$/gm, '')
    .replace(/\bat\s+[^\s()]*\s*\([^()\n]*:\d+(?::\d+)?\)/g, '')
    .replace(/\bat\s+\S+:\d+:\d+/g, '')
    .replace(/(\d)\s*[–—]\s*(\d)/g, '$1-$2')
    .replace(/(?<=[\p{L}\p{N}_.-])\\(?=[\p{L}\p{N}_.-])/gu, '/');
}

/**
 * Las citas de un mensaje, sin repetir: `[{ texto, ruta, desde, hasta }]`.
 * Lo que está entre backticks cuenta: es como un modelo escribe una ubicación.
 */
export function citasDe(mensaje) {
  const texto = normalizar(mensaje);
  const out = new Map();
  for (const re of [RE_DOS_PUNTOS, RE_ANCLA, RE_PALABRA]) {
    for (const m of texto.matchAll(re)) {
      const desde = Number(m[2]);
      const hasta = m[3] === undefined ? desde : Number(m[3]);
      const clave = `${m[1]}:${desde}-${hasta}`;
      if (!out.has(clave)) out.set(clave, { texto: m[0], ruta: m[1], desde, hasta });
    }
  }
  return [...out.values()];
}

/** Índice perezoso de los archivos del proyecto, para resolver citas por sufijo. */
function indiceDe(base) {
  const archivos = [];
  const pila = [''];
  while (pila.length && archivos.length < MAX_INDICE) {
    const rel = pila.pop();
    for (const e of entradasDe(path.join(base, rel))) {
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) pila.push(r);
      else if (e.isFile()) archivos.push(r);
    }
  }
  return { archivos, completo: pila.length === 0 };
}

/** Las entradas indexables de un directorio; uno ilegible no tiene ninguna. */
function entradasDe(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).filter((e) => !NO_INDEXAR.has(e.name));
  } catch {
    return [];
  }
}

const dentro = (abs, base) => abs === base || abs.startsWith(base + path.sep);

/**
 * El archivo en `abs`, si es un archivo común del proyecto. Se compara el
 * destino REAL: un symlink dentro del proyecto que apunta afuera no se lee.
 * `{ ok }`, `{ estado: 'no existe' }` o `{ estado: 'sin verificar' }` (fuera del
 * proyecto, especial —FIFO, dispositivo—, o ilegible).
 */
function archivoDelProyecto(abs, baseReal) {
  try {
    fs.lstatSync(abs);
  } catch (e) {
    return { estado: e.code === 'ENOENT' ? 'no existe' : 'sin verificar' };
  }
  try {
    if (!dentro(fs.realpathSync(abs), baseReal)) return { estado: 'sin verificar' };
    return fs.statSync(abs).isFile() ? { ok: true } : { estado: 'sin verificar' };
  } catch {
    return { estado: 'sin verificar' };
  }
}

/**
 * Dónde está el archivo citado: `{ rels: [...] }` (uno, o varios si es ambiguo),
 * o `{ estado: 'no existe' | 'sin verificar' }`.
 */
function resolver(ruta, base, baseReal, indice) {
  const abs = path.resolve(base, ruta);
  if (!dentro(abs, base)) return { estado: 'sin verificar' };
  const exacto = archivoDelProyecto(abs, baseReal);
  if (exacto.ok) return { rels: [path.relative(base, abs)] };
  if (exacto.estado === 'sin verificar' || path.isAbsolute(ruta)) return exacto;
  const idx = indice();
  const sufijo = `/${ruta.replace(/^\.\//, '')}`;
  const candidatos = idx.archivos.filter((a) => `/${a}`.endsWith(sufijo));
  if (candidatos.length) return { rels: candidatos };
  return { estado: idx.completo ? 'no existe' : 'sin verificar' };
}

/** Líneas de un archivo, contadas por bloques: un archivo grande no se carga entero. */
function contarLineas(abs) {
  const { size } = fs.statSync(abs);
  if (size > MAX_BYTES) return null;
  if (size === 0) return 0;
  const buf = Buffer.allocUnsafe(1 << 20);
  const fd = fs.openSync(abs, 'r');
  let saltos = 0;
  let ultimo = 0;
  try {
    for (let n = fs.readSync(fd, buf); n > 0; n = fs.readSync(fd, buf)) {
      for (let i = 0; i < n; i += 1) if (buf[i] === 10) saltos += 1;
      ultimo = buf[n - 1];
    }
  } finally {
    fs.closeSync(fd);
  }
  return ultimo === 10 ? saltos : saltos + 1;
}

/**
 * Verifica UNA cita: `'ok'`, `'sin verificar'`, o el motivo por el que está
 * rota. Una cita ambigua (varios archivos terminan igual) sólo se afirma rota
 * si NINGUNO de los candidatos tiene esa línea.
 */
function verificarUna(c, base, baseReal, indice) {
  if (c.desde < 1 || c.hasta < c.desde) return 'el rango está mal escrito';
  const donde = resolver(c.ruta, base, baseReal, indice);
  if (donde.estado === 'no existe') return 'el archivo no existe';
  if (donde.estado) return 'sin verificar';
  const lineas = donde.rels.map((rel) => contarLineas(path.join(base, rel)));
  if (lineas.some((l) => l === null)) return 'sin verificar';
  if (lineas.some((l) => c.hasta <= l)) return 'ok';
  if (donde.rels.length === 1) return `${donde.rels[0]} tiene ${lineas[0]} línea${lineas[0] === 1 ? '' : 's'}`;
  return `ninguno de los ${donde.rels.length} archivos que terminan en ${c.ruta} llega a la línea ${c.hasta}`;
}

/**
 * Verifica las citas contra el proyecto en `raiz`. Devuelve `{ total, ok,
 * sinVerificar, malas: [{ texto, motivo }] }`. Sólo es "mala" una cita que se
 * puede afirmar rota.
 */
export function verificarCitas(citas, raiz = process.cwd()) {
  const base = path.resolve(raiz);
  let baseReal = base;
  try { baseReal = fs.realpathSync(base); } catch { /* se compara con la ruta tal cual */ }
  let idx = null;
  const indice = () => { idx ??= indiceDe(base); return idx; };
  const r = { total: citas.length, ok: 0, sinVerificar: 0, malas: [] };
  for (const c of citas) {
    let v;
    try { v = verificarUna(c, base, baseReal, indice); } catch { v = 'sin verificar'; }
    if (v === 'ok') r.ok += 1;
    else if (v === 'sin verificar') r.sinVerificar += 1;
    else r.malas.push({ texto: c.texto, motivo: v });
  }
  return r;
}

/** El aviso para el orquestador, o '' si todas las citas resuelven o no se pudieron juzgar. */
export function informeCitas({ total, malas }) {
  if (!malas.length) return '';
  const lista = malas.slice(0, 10).map((m) => `\`${m.texto}\` (${m.motivo})`).join(' · ');
  const mas = malas.length > 10 ? ` y ${malas.length - 10} más` : '';
  return `[citas] El subagente citó ${total} ubicación(es) y ${malas.length} no resuelve(n): ${lista}${mas}. `
    + 'No las uses como evidencia —ni para aprobar un hallazgo ni para sellar una entrega— hasta confirmarlas: '
    + 'una cita que no apunta a nada es una afirmación sin respaldo.';
}

// ─── Fuentes externas por ID (F2 sobre el catálogo de F5) ───────────────────
//
// Una fuente oficial SAP no tiene `archivo:línea`: se cita por su ID del
// catálogo, `[fuente:abap.rap]`. Lo que se verifica es que el ID exista —que la
// fuente sea una de las que el stack reconoce como autoritativas—, no que diga
// lo que se le atribuye.

/**
 * `[fuente:abap.rap]`, con o sin espacios. El contenido está acotado y no
 * admite corchetes: un `[fuente:` sin cerrar repetido miles de veces hacía
 * retroceder la búsqueda desde cada comienzo (13 s sobre 256 KB).
 */
const RE_FUENTE = /\[\s*fuente\s*:([^[\]\n]{0,200})\]/giu;
/** Lo que se muestra de un ID en el aviso: uno de 25 KB no se repite entero. */
const MAX_ID_AVISO = 80;

/**
 * Los IDs de fuente que cita un mensaje, sin repetir y en el orden en que
 * aparecen. Dentro del corchete, el ID es la primera palabra: lo que sigue es
 * detalle (`[fuente:sap.notes 3456789]`, `[fuente:abap.rap §3]`), y varias
 * fuentes van separadas por coma (`[fuente:abap.rap, abap.cloud]`). Antes, todo
 * lo que no fuera un ID pelado hacía desaparecer la cita sin aviso.
 *
 * No cuentan los bloques de código ni el código en línea: ahí `[fuente:<ID>]`
 * es la sintaxis explicada, no una cita. Tampoco un molde (`<ID>`, `{id}`, `…`).
 */
export function fuentesDe(mensaje) {
  const texto = normalizar(mensaje).replace(/(`{1,8})[^`\n]*?\1/g, '');
  const ids = new Set();
  for (const m of texto.matchAll(RE_FUENTE)) {
    for (const parte of m[1].split(/[,;]/)) {
      const id = parte.trim().split(/\s+/)[0];
      if (id && !/[<>{}…]|\.\.\./.test(id)) ids.add(id.toLowerCase());
    }
  }
  return [...ids];
}

/** Los IDs que no están en el catálogo. */
export function fuentesDesconocidas(ids, catalogo) {
  return ids.filter((id) => !Object.hasOwn(catalogo, id));
}

/** El aviso para el orquestador, o '' si todas las fuentes están en el catálogo. */
export function informeFuentes({ total, desconocidas }) {
  if (!desconocidas.length) return '';
  const corto = (id) => (id.length > MAX_ID_AVISO ? `${id.slice(0, MAX_ID_AVISO)}…` : id);
  const lista = desconocidas.slice(0, 10).map((id) => `\`[fuente:${corto(id)}]\``).join(' · ');
  const mas = desconocidas.length > 10 ? ` y ${desconocidas.length - 10} más` : '';
  return `[fuentes] El subagente citó ${total} fuente(s) oficial(es) y ${desconocidas.length} no está(n) en el catálogo: ${lista}${mas}. `
    + 'Una fuente fuera del catálogo no es verificable: pedí que cite por su ID de '
    + '`sap-fuentes-de-verdad` o que marque el dato [NO VERIFICADO].';
}
