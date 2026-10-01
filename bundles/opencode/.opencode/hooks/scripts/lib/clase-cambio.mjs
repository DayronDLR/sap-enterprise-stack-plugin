/**
 * clase-cambio.mjs — ¿el cambio que se entrega es un ajuste chico de configuración?
 *
 * Un cambio de dos líneas en `package.json` pasaba por el flujo completo: un
 * subagente reviewer con ocho dimensiones y un subagente de QA respondiendo unos
 * cuarenta ítems de ABAP, CAP y HANA con «N/A». Media hora para nada.
 *
 * La clase `config-trivial` la decide ESTE script, no el agente:
 *
 *   - todos los archivos del cambio son configuración del proyecto
 *     (`package.json`, `manifest.json`, `mta*.yaml`, `ui5*.yaml`,
 *     `i18n*.properties`, y los lockfiles que acompañan una dependencia);
 *   - CADA CLAVE QUE CAMBIA está en una lista de lo seguro: la versión, la
 *     descripción, metadatos del paquete, versiones de dependencias del
 *     registro, títulos de la app, textos de i18n. Cualquier otra —una ruta, un
 *     host, un scope, un script, una librería— saca el cambio de la clase;
 *   - suman 30 líneas cambiadas o menos (sin contar los lockfiles), sin
 *     renombres ni borrados;
 *   - el scan de riesgo de configuración no encuentra nada (ni CRITICAL ni WARN).
 *
 * POR QUÉ UNA LISTA DE LO SEGURO. La primera versión miraba lo peligroso —auth,
 * scopes, xsuaa, tareas del build, URIs— y la revisión encontró enseguida lo que
 * faltaba: cambiar el `source` de la ruta pública de `xs-app.json` a `^(.*)$`
 * dejaba la app entera sin login, y salía «ajuste chico». Una lista de lo
 * peligroso no converge; una de lo seguro, sí. Por eso `xs-app.json`,
 * `xs-security.json` y `.cdsrc.json` ni siquiera entran: definen la seguridad.
 *
 * Con la clase, el Gate 3 no aplica: no hay concurrencia, volumen ni locking que
 * revisar en una versión o un texto. `sellar-gate.sh qa --config-trivial` vuelve
 * a calcularla y se niega a sellar si no se cumple, así que no se puede declarar.
 *
 * Uso: `node clase-cambio.mjs` en la raíz del repo → una línea JSON
 * `{"clase":"config-trivial"|"completa","motivo":"…","archivos":[…],"lineas":N}`.
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { scanArchivo, fueraDelRegistro } from '../config-risk-scan.mjs';

export const MAX_LINEAS = 30;
export const CONFIG_TRIVIAL = /(^|\/)(package\.json|manifest\.json|mta(-[^/]*)?\.ya?ml|ui5[^/]*\.ya?ml|i18n[^/]*\.properties|package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$/;
const LOCKFILE = /(^|\/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$/;

// ── Lo que se puede cambiar por el camino corto, por archivo ────────────────
// `private` no está: pasarlo a false habilita publicar el paquete.
const SEGURAS_PACKAGE = /^(version|description|keywords( > \d+)?|author( > \w+)?|contributors( > \d+( > \w+)?)?|license|homepage|bugs( > \w+)?|repository( > \w+)?)$/;
const DEPENDENCIAS = /^(dependencies|devDependencies|peerDependencies|optionalDependencies) > [^>]+$/;
const SEGURAS_MANIFEST = /^(_version|sap\.app > (applicationVersion > version|title|subTitle|description|tags > keywords( > \d+)?))$/;
// Una versión concreta: `1.2.3`, `^1.2.3`, `~1.2`. Nada de `*`, `latest`, `>=0`
// ni rangos abiertos, que dejan entrar cualquier versión futura, ni alias `npm:`,
// que cambian de paquete.
const VERSION_CONCRETA = /^[\^~]?\d+(\.\d+){1,2}(-[\w.]+)?$/;

/**
 * `{a: {b: 1}, c: {}}` → `[["a > b", 1], ["c", "{}"]]`. A diferencia de `aplanar`
 * del scan, un objeto o un array VACÍO cuenta como hoja: agregar
 * `"libs": {"evil.lib": {}}` es un cambio, aunque no traiga valores adentro.
 */
const hojas = (o, pre = '') => Object.entries(o || {}).flatMap(([k, v]) => {
  if (v && typeof v === 'object' && Object.keys(v).length) return hojas(v, `${pre}${k} > `);
  return [[`${pre}${k}`, v && typeof v === 'object' ? JSON.stringify(v) : v]];
});

/** Las claves que cambian entre dos JSON: `[clave, valor nuevo, valor anterior]`. */
function clavesCambiadas(antes, ahora) {
  const a = new Map(hojas(antes)); const b = new Map(hojas(ahora));
  return [...new Set([...a.keys(), ...b.keys()])].filter((k) => a.get(k) !== b.get(k)).map((k) => [k, b.get(k), a.get(k)]);
}

const json = (t) => { try { return JSON.parse(String(t).replace(/^\uFEFF/, '')); } catch { return null; } };
/** ¿La clave `k` de `nombre` se puede cambiar por el camino corto? */
function claveSegura(nombre, k, nuevo, anterior) {
  if (nombre === 'manifest.json') return SEGURAS_MANIFEST.test(k);
  if (SEGURAS_PACKAGE.test(k)) return true;
  // Sólo la VERSIÓN de una dependencia que ya estaba, o quitarla. Una
  // dependencia nueva es código de terceros nuevo: el review completo.
  return DEPENDENCIAS.test(k) && anterior !== undefined
    && (nuevo === undefined || (typeof nuevo === 'string' && VERSION_CONCRETA.test(nuevo) && !fueraDelRegistro(nuevo)));
}

function jsonFueraDeLoSeguro(ruta, nombre, antes, ahora) {
  const [a, b] = [json(antes || '{}'), json(ahora)];
  if (!a || !b) return `${ruta} no es JSON válido`;
  const k = clavesCambiadas(a, b).find(([clave, nuevo, anterior]) => !claveSegura(nombre, clave, nuevo, anterior));
  return k ? `${ruta}: «${k[0]}» no es un ajuste chico` : null;
}

// ── YAML: se compara lo que SIGNIFICA, no las líneas ─────────────────────────
//
// Cinco rondas de revisión encontraron cinco formas de reestructurar un YAML con
// líneas «seguras» —líneas movidas de bloque, un escalar entre comillas que se
// tragaba el bloque del medio, un `version: 1` que convertía una lista en la
// continuación de un texto, un `description: !!map` que adoptaba el bloque de
// abajo (y el `.env` dejaba de ignorarse en el .mtar)—. Comparar texto contra
// regex no converge. Se parsean las dos versiones, se sacan SOLO las claves
// permitidas, y el resto tiene que ser idéntico.
//
// Sin un parser de YAML disponible (en el plugin o en el proyecto), un YAML no es
// nunca un ajuste chico: se falla cerrado.
const VERSION_VALOR = /^\d+(\.\d+){0,2}([-+][\w.]+)?$/;
const YAML_PERMITIDAS = [
  // ui5*.yaml: la versión de UI5 y la de cada librería.
  [/^ui5[^/]*\.ya?ml$/, (doc) => [
    ['framework', 'version'],
    ...(Array.isArray(doc?.framework?.libraries) ? doc.framework.libraries.map((_, i) => ['framework', 'libraries', i, 'version']) : []),
  ]],
  // mta*.yaml: la versión y la descripción de la raíz.
  [/^mta(-[^/]*)?\.ya?ml$/, () => [['version'], ['description']]],
];

let parserYaml;
/** `js-yaml` o `yaml`, desde el stack o desde el proyecto; `null` si no hay. */
function cargarParserYaml() {
  if (parserYaml !== undefined) return parserYaml;
  parserYaml = null;
  for (const desde of [import.meta.url, path.join(process.cwd(), 'package.json')]) {
    const req = createRequire(desde);
    // js-yaml 3 carga por defecto el schema completo (`!!js/function`): se pide el
    // seguro, que en js-yaml 4 ya es el de por defecto.
    try { const m = req('js-yaml'); parserYaml = (t) => m.load(t, { schema: m.DEFAULT_SAFE_SCHEMA ?? m.DEFAULT_SCHEMA }); return parserYaml; } catch { /* sigue */ }
    try { const m = req('yaml'); parserYaml = (t) => m.parse(t); return parserYaml; } catch { /* sigue */ }
  }
  return parserYaml;
}

const leerRuta = (doc, ruta) => ruta.reduce((o, k) => (o == null ? undefined : o[k]), doc);
function quitarRuta(doc, ruta) {
  const padre = leerRuta(doc, ruta.slice(0, -1));
  if (padre && typeof padre === 'object') delete padre[ruta.at(-1)];
}
// Igualdad estructural sin depender del orden de las claves de un objeto.
const canonico = (v) => {
  if (Array.isArray(v)) return `[${v.map(canonico).join(',')}]`;
  if (v && typeof v === 'object') return `{${Object.keys(v).sort((x, y) => x.localeCompare(y)).map((k) => `${JSON.stringify(k)}:${canonico(v[k])}`).join(',')}}`;
  // JSON.stringify da "null" para NaN e Infinity: se distinguen de null.
  if (typeof v === 'number' && !Number.isFinite(v)) return String(v);
  return JSON.stringify(v);
};

/** ¿El valor de una clave permitida es lo que dice ser? */
function valorPermitido(ruta, v) {
  if (v === undefined) return true;
  if (ruta.at(-1) === 'description') return typeof v === 'string' && !v.includes('\n');
  return (typeof v === 'string' || typeof v === 'number') && VERSION_VALOR.test(String(v));
}

function yamlFueraDeLoSeguro(ruta, nombre, antes, ahora) {
  const permitidas = YAML_PERMITIDAS.find(([archivo]) => archivo.test(nombre))?.[1];
  if (!permitidas) return `${ruta}: no hay lista de lo seguro para este archivo`;
  const parsear = cargarParserYaml();
  if (!parsear) return `${ruta}: no hay un parser de YAML disponible para comprobar el cambio`;
  let a; let b;
  try { a = parsear(String(antes || '')); b = parsear(String(ahora || '')); } catch (e) {
    return `${ruta}: no se pudo leer como YAML (${String(e.message).split('\n')[0]})`;
  }
  const rutas = [...permitidas(a), ...permitidas(b)];
  const malo = rutas.find((r) => !valorPermitido(r, leerRuta(b, r)));
  if (malo) return `${ruta}: «${malo.join(' > ')}» no tiene un valor de ajuste chico`;
  for (const r of rutas) { quitarRuta(a, r); quitarRuta(b, r); }
  try {
    return canonico(a) === canonico(b) ? null : `${ruta}: cambia algo más que la versión o la descripción`;
  } catch {
    // Un alias que se contiene a sí mismo (`a: &x\n  b: *x`) no tiene forma canónica.
    return `${ruta}: estructura con ciclo o demasiado profunda, no se puede comparar`;
  }
}

/** `null` si todo lo que cambia en `ruta` está en la lista de lo seguro; si no, el motivo. */
export function fueraDeLoSeguro(ruta, antes, ahora) {
  const nombre = path.basename(ruta);
  if (LOCKFILE.test(ruta) || /^i18n[^/]*\.properties$/.test(nombre)) return null;
  if (nombre === 'package.json' || nombre === 'manifest.json') return jsonFueraDeLoSeguro(ruta, nombre, antes, ahora);
  return yamlFueraDeLoSeguro(ruta, nombre, antes, ahora);
}

/** `git` por ruta absoluta, no resuelto por el PATH en cada spawn (SonarJS S4036). */
function resolverBinario(nombre) {
  for (const dir of String(process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const candidato = path.join(dir, nombre);
    try { fs.accessSync(candidato, fs.constants.X_OK); return candidato; } catch { /* sigue */ }
  }
  return null;
}
const GIT = resolverBinario('git');
const git = (...args) => execFileSync(GIT, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });

/** `numstat` → Map ruta → líneas cambiadas (un binario cuenta como fuera de umbral). */
function numstat(salida, acumulado) {
  for (const l of salida.split('\n').filter(Boolean)) {
    const [a, b, ruta] = l.split('\t');
    const n = a === '-' || b === '-' ? Infinity : Number(a) + Number(b);
    acumulado.set(ruta, Math.max(acumulado.get(ruta) ?? 0, n));
  }
}

/** Lo que se entrega: índice y working tree contra HEAD, más lo nuevo sin trackear. */
export function cambioActual() {
  if (!GIT) throw new Error('git no está disponible');
  const porArchivo = new Map();
  // Sin renombres: `{a => b}/package.json` no es una ruta, y el scan no la leía.
  numstat(git('-c', 'core.quotePath=false', 'diff', '--numstat', '--no-renames', '--cached', 'HEAD'), porArchivo);
  numstat(git('-c', 'core.quotePath=false', 'diff', '--numstat', '--no-renames', 'HEAD'), porArchivo);
  // Un borrado no pasa por ningún scan: queda fuera de la clase.
  const borrados = [
    ...git('-c', 'core.quotePath=false', 'diff', '--name-only', '--no-renames', '--diff-filter=D', '--cached', 'HEAD').split('\n'),
    ...git('-c', 'core.quotePath=false', 'diff', '--name-only', '--no-renames', '--diff-filter=D', 'HEAD').split('\n'),
  ].filter(Boolean);
  for (const ruta of borrados) porArchivo.set(ruta, Infinity);
  const nuevos = git('-c', 'core.quotePath=false', 'ls-files', '-o', '--exclude-standard', '--', '.', ':!tmp/', ':!logs/')
    .split('\n').filter(Boolean);
  for (const ruta of nuevos) {
    let n = Infinity;
    try { n = fs.readFileSync(ruta, 'utf8').split('\n').length; } catch { /* ilegible: fuera */ }
    porArchivo.set(ruta, n);
  }
  return porArchivo;
}

const base = (ruta) => { try { return git('show', `HEAD:${ruta}`); } catch { return ''; } };
const versiones = (ruta) => {
  const out = [];
  try { out.push(git('show', `:${ruta}`)); } catch { /* no está en el índice */ }
  try { out.push(fs.readFileSync(ruta, 'utf8')); } catch { /* borrado */ }
  return out;
};

/** Lo que saca al cambio de la clase sin mirar el contenido; `null` si nada. */
function motivoDeForma(porArchivo, archivos, lineas) {
  if (!archivos.length) return 'no hay cambios';
  const ajenos = archivos.filter((a) => !CONFIG_TRIVIAL.test(a));
  if (ajenos.length) return `hay archivos que no son configuración: ${ajenos.slice(0, 5).join(', ')}`;
  // Incluye los lockfiles, que no cuentan para el umbral pero sí se borran.
  if ([...porArchivo.values()].some((n) => !Number.isFinite(n))) {
    return 'hay un borrado, un binario o un archivo ilegible: nada de eso pasa por el scan';
  }
  if (lineas > MAX_LINEAS) return `${lineas} líneas cambiadas; el máximo es ${MAX_LINEAS}`;
  // Un lockfile sólo acompaña: sin un `package.json` en el mismo cambio, es una
  // dependencia que nadie pidió.
  if (archivos.some((a) => LOCKFILE.test(a)) && !archivos.some((a) => path.basename(a) === 'package.json')) {
    return 'un lockfile cambia sin un package.json que lo explique';
  }
  return null;
}

/**
 * Un lockfile sólo se acepta si el `package.json` de SU directorio cambia una
 * dependencia en el mismo cambio. Bastaba con que hubiera un `package.json`
 * cualquiera —uno que sólo subía la versión, o el de otro paquete del
 * monorepo— para colar un lockfile arbitrario.
 */
function lockfileSinMotivo(archivos, leerBase, leerVersiones) {
  for (const lock of archivos.filter((a) => LOCKFILE.test(a))) {
    const pkg = path.join(path.dirname(lock), 'package.json').replace(/^\.\//, '');
    const antes = json(leerBase(pkg) || '{}') || {};
    const cambiaDeps = archivos.includes(pkg) && leerVersiones(pkg).some((v) =>
      clavesCambiadas(antes, json(v) || {}).some(([k]) => DEPENDENCIAS.test(k)));
    if (!cambiaDeps) return `${lock} cambia sin que ${pkg} cambie una dependencia`;
  }
  return null;
}

/** La clase del cambio. `leerBase` y `leerVersiones` se inyectan en los tests. */
export function clasificar(porArchivo, { leerBase = base, leerVersiones = versiones } = {}) {
  const archivos = [...porArchivo.keys()];
  // Los lockfiles no cuentan para el umbral: los escribe la herramienta.
  const lineas = [...porArchivo].filter(([r]) => !LOCKFILE.test(r)).reduce((a, [, n]) => a + n, 0);
  const completa = (motivo) => ({ clase: 'completa', motivo, archivos, lineas: Number.isFinite(lineas) ? lineas : null });
  const forma = motivoDeForma(porArchivo, archivos, lineas) ?? lockfileSinMotivo(archivos, leerBase, leerVersiones);
  if (forma) return completa(forma);
  for (const ruta of archivos) {
    const antes = leerBase(ruta);
    for (const v of leerVersiones(ruta)) {
      const fuera = fueraDeLoSeguro(ruta, antes, v);
      if (fuera) return completa(fuera);
      const h = scanArchivo(ruta, antes, v);
      if (h.length) return completa(`el scan de configuración encontró: ${h[0][1]}`);
    }
  }
  return {
    clase: 'config-trivial',
    motivo: `${archivos.length} archivo(s), ${lineas} línea(s): sólo versiones, descripciones, metadatos o textos`,
    archivos,
    lineas,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  try {
    process.stdout.write(`${JSON.stringify(clasificar(cambioActual()))}\n`);
  } catch (e) {
    // Si no se puede calcular, la clase es la completa: nunca se asume la chica.
    process.stdout.write(`${JSON.stringify({ clase: 'completa', motivo: `no se pudo calcular: ${e.message}` })}\n`);
  }
}
