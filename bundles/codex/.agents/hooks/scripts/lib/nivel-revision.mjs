#!/usr/bin/env node
/**
 * nivel-revision.mjs — qué profundidad de revisión exige el cambio actual.
 *
 * Medido al construir el stack: cada ronda del Gate 2 o del Gate 3 costaba entre
 * 150k y 290k tokens, siempre con el modelo más grande y las ocho dimensiones,
 * aunque el cambio fuera un párrafo de un skill. El camino corto del lote 2 sólo
 * cubría los ajustes de configuración. Este clasificador extiende la idea a todo
 * cambio: la profundidad la decide el riesgo, y la decide un script —no la sesión,
 * que tiene incentivo a elegir la más barata—. `sellar-gate.sh` lo vuelve a correr
 * y se niega a sellar una revisión más liviana que la que corresponde.
 *
 * Niveles, de más liviano a más profundo:
 *   config-trivial  ajuste chico de configuración (clase-cambio.mjs, lote 2)
 *   liviana         sólo contenido que no se ejecuta, sin bloques de código
 *   estandar        el resto
 *   completa        seguridad, ejecución, datos, borrados, volumen o algo ilegible
 *
 * Falla cerrado: si algo no se puede calcular, el nivel es `completa`.
 *
 *   node nivel-revision.mjs        → JSON { nivel, motivos, archivos, lineas, plan }
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { cambioActual, clasificar } from './clase-cambio.mjs';

export const NIVELES = ['config-trivial', 'liviana', 'estandar', 'completa'];
export const MAX_LINEAS_LIVIANA = 300;
export const MAX_LINEAS_ESTANDAR = 400;

/** Rutas que siempre piden la revisión completa: ejecutan, definen seguridad o tocan datos. */
const RIESGO = [
  [/(^|\/)(xs-security|xs-app)\.json$|(^|\/)\.cdsrc(-private)?\.(json|ya?ml)$/, 'define seguridad o enrutamiento'],
  [/\.(asdcls|acinf)$|\.(sicf|suso|susc|srvb|enho|enhs)\.xml$/i, 'seguridad o exposición ABAP (DCL, ICF, autorizaciones, service binding)'],
  // abapGit: el resto de los metadatos también define el objeto (tabla, elemento, clase, vista).
  [/\.(tabl|dtel|doma|ttyp|clas|intf|ddls|bdef|fugr|prog|msag|tran|devc)\.xml$|(^|\/)\.abapgit\.xml$/i, 'objeto ABAP (metadatos abapGit)'],
  // CPI: el iFlow y sus recursos se ejecutan en el tenant.
  [/\.(iflw|mmap|xsl|xslt|wsdl|xsd|propdef)$|(^|\/)(parameters\.prop|MANIFEST\.MF)$|(^|\/)src\/main\/resources\/script\//i, 'integración (iFlow y sus recursos)'],
  [/(^|\/)(requirements[^/]*\.txt|constraints\.txt|\.npmrc|\.yarnrc(\.yml)?|pip\.conf)$/i, 'configuración que instala'],
  [/(^|\/)(package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|mta[^/]*\.ya?ml|ui5[^/]*\.ya?ml|manifest\.json|manifest\.appdescr(_variant)?)$/, 'configuración que instala, construye o despliega'],
  [/(^|\/)(settings(\.local)?\.json|\.mcp\.json|hooks\.json)$/, 'configuración del agente o de sus hooks'],
  [/(^|\/)(hooks|\.husky)\//, 'hooks o ganchos de git'],
  // De `.github/` sólo lo que ejecuta o decide permisos: ahí también viven agentes
  // de Copilot y plantillas de issues, que son contenido.
  [/(^|\/)(?:\.github\/(workflows|actions)\/|CODEOWNERS$)/, 'CI o permisos de revisión'],
  [/\.(sh|bash|zsh|ps1|py|mjs|cjs|groovy)$/, 'scripts'],
  [/(?:(^|\/)(srv[^/]*|db|approuter|scripts|tools)\/)|(?:(^|\/)server\.(js|ts)$)|(?:\.java$)/, 'backend, router, scripts o modelo de datos'],
  [/\.(cds|hdb[a-z]*|abap|asddls|asbdef|asddlxs|srvdsrv|sql)$/i, 'modelo, persistencia, ABAP o SQL'],
  [/(^|\/)(Dockerfile[^/]*|Jenkinsfile|Makefile|\.gitlab-ci\.ya?ml|azure-pipelines\.ya?ml|docker-compose[^/]*\.ya?ml|manifest\.ya?ml|pom\.xml|build\.gradle(\.kts)?|settings\.gradle(\.kts)?)$|(^|\/)(\.pipeline|helm|k8s|kubernetes|charts?)\/|\.(tf|bicep|mtaext)$/, 'infraestructura, build o despliegue'],
  [/(^|\/)\.env($|\.)|secret|credential|service-key|default-env/i, 'credenciales'],
];

/**
 * Contenido que no se ejecuta: el único que puede ir por la revisión liviana.
 * Una lista de lo seguro, no de lo peligroso: `.svg` puede traer `<script>`, `.mdx`
 * ejecuta JSX, un `.txt` puede ser `requirements.txt` y un `.properties` que no es
 * i18n puede ser configuración de seguridad.
 */
const SIN_EJECUCION = /\.md$|(^|\/)i18n[^/]*\.properties$|\.(png|jpe?g|gif|webp)$/i;
const IMAGEN = /\.(png|jpe?g|gif|webp)$/i;

/** Tecnologías que toca el diff: el QA lee sólo esas secciones del checklist NFR. */
const TECNOLOGIAS = [
  [/\.(abap|asddls|asbdef|asddlxs|srvdsrv|asdcls)$|\.(tabl|dtel|doma|ttyp|sicf|suso|srvb)\.xml$/i, 'ABAP / RAP'],
  [/\.cds$|(^|\/)srv\//, 'CAP'],
  [/\.(hdb[a-z]*|sql)$/i, 'HANA'],
  [/(^|\/)webapp\/|\.view\.xml$|\.fragment\.xml$/, 'Fiori / UI5'],
  [/\.(iflw|groovy)$|(^|\/)iflows?\//i, 'Integration / CPI'],
  [/\.py$|(^|\/)migra/i, 'Migración / scripts de carga'],
];

/**
 * Una ruta que git citó (`"srv/we\"ird.js"`, con core.quotePath=false igual cita
 * comillas, barras y caracteres de control) se descita antes de compararla: si no,
 * ninguna regla la reconoce.
 */
export function desCitar(ruta) {
  const r = String(ruta);
  if (!(r.startsWith('"') && r.endsWith('"'))) return r;
  try { return JSON.parse(r); } catch { return r.slice(1, -1); }
}

/** Qué hace cada nivel. El modelo es el del subagente; un host sin elección lo ignora. */
export const PLAN = {
  'config-trivial': {
    review: { subagente: false, dimensiones: 'los seis checks de /sap-gates', ejecutar: false },
    qa: { aplica: false, sello: 'qa --config-trivial' },
  },
  liviana: {
    review: { subagente: true, modelo: 'sonnet', dimensiones: [1, 2, 3, 8], ejecutar: false },
    qa: { aplica: false, sello: 'qa --nivel=liviana' },
  },
  estandar: {
    review: { subagente: true, modelo: 'sonnet', dimensiones: [1, 2, 3, 4, 5, 6, 7, 8], ejecutar: 'sólo lo barato y decisivo' },
    qa: { aplica: true, modelo: 'sonnet', ejecutar: 'sólo lo barato y decisivo' },
  },
  completa: {
    review: { subagente: true, modelo: 'opus', dimensiones: [1, 2, 3, 4, 5, 6, 7, 8], ejecutar: true },
    qa: { aplica: true, modelo: 'opus', ejecutar: true },
  },
};

function resolverBinario(nombre) {
  for (const dir of String(process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const c = path.join(dir, nombre);
    try { fs.accessSync(c, fs.constants.X_OK); return c; } catch { /* sigue */ }
  }
  return null;
}
const GIT = resolverBinario('git');

/**
 * El archivo ENTERO, en sus dos versiones: la del índice (lo que publica
 * `git commit`) y la del working tree (`git commit -a`). Mirar sólo las líneas
 * agregadas dejaba pasar una edición dentro de un bloque de código que ya estaba,
 * y mirar sólo el disco, un bloque que existe sólo en el índice.
 */
function versionesCompletas(ruta) {
  const out = [];
  try { out.push(...execFileSync(GIT, ['show', `:${ruta}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n')); } catch { /* no está en el índice */ }
  try { out.push(...fs.readFileSync(ruta, 'utf8').split('\n')); } catch { /* no está en disco */ }
  return out.length ? out : null;
}

/**
 * Un markdown que trae código enseña un patrón: no es «contenido que no se
 * ejecuta». Bloques con fence, código indentado y HTML que ejecuta o lo muestra.
 */
const traeCodigo = (lineas) => lineas.some((l) => /^\s*(```|~~~)|^( {4}|\t)\S|<(pre|script|code|iframe)\b/i.test(l));

/** Por qué el cambio exige la revisión completa (vacío: no la exige). */
function motivosCompleta(porArchivo, lineas) {
  const motivos = [];
  for (const [ruta, n] of porArchivo) {
    if (!Number.isFinite(n) && !IMAGEN.test(ruta)) motivos.push(`${ruta}: borrado, binario o ilegible`);
    const r = RIESGO.find(([re]) => re.test(ruta));
    if (r) motivos.push(`${ruta}: ${r[1]}`);
  }
  if (Number.isFinite(lineas) && lineas > MAX_LINEAS_ESTANDAR) motivos.push(`${lineas} líneas (más de ${MAX_LINEAS_ESTANDAR})`);
  return motivos;
}

/** Por qué no alcanza la revisión liviana (vacío: alcanza). */
function motivosEstandar(archivos, lineas, leerAgregadas) {
  const motivos = [];
  for (const ruta of archivos) {
    if (!SIN_EJECUCION.test(ruta)) { motivos.push(`${ruta}: código o configuración`); continue; }
    if (!/\.mdx?$/i.test(ruta)) continue;
    const agregadas = leerAgregadas(ruta);
    if (agregadas === null) motivos.push(`${ruta}: no se pudo leer`);
    else if (traeCodigo(agregadas)) motivos.push(`${ruta}: trae bloques de código (puede enseñar un patrón)`);
  }
  if (lineas > MAX_LINEAS_LIVIANA) motivos.push(`${lineas} líneas (más de ${MAX_LINEAS_LIVIANA})`);
  return motivos;
}

/**
 * @param {Map<string, number>} porArchivo  ruta → líneas cambiadas (Infinity = borrado o ilegible)
 * @param {{ claseConfig?: string, leerAgregadas?: (ruta: string) => string[] | null }} [deps]
 */
export function nivelDe(porArchivoCrudo, { claseConfig, leerAgregadas = versionesCompletas } = {}) {
  const porArchivo = new Map([...porArchivoCrudo].map(([r, n]) => [desCitar(r), n]));
  const archivos = [...porArchivo.keys()];
  // Una imagen binaria no tiene líneas (numstat da `-`): no cuenta para el volumen.
  const lineas = [...porArchivo].reduce((a, [r, n]) => a + (Number.isFinite(n) ? n : (IMAGEN.test(r) ? 0 : n)), 0);
  const salida = (nivel, motivos) => ({ nivel, motivos, archivos, lineas, plan: PLAN[nivel] });
  if (!archivos.length) return salida('completa', ['no hay cambios que revisar: no se sella un diff vacío']);
  if (claseConfig === 'config-trivial') return salida('config-trivial', ['ajuste chico de configuración (clase-cambio.mjs)']);
  const completa = motivosCompleta(porArchivo, lineas);
  if (completa.length) return salida('completa', completa);
  const estandar = motivosEstandar(archivos, lineas, leerAgregadas);
  if (estandar.length) return salida('estandar', estandar);
  return salida('liviana', [`${archivos.length} archivo(s), ${lineas} línea(s) de contenido que no se ejecuta, sin código`]);
}

/** Tecnologías del diff, para acotar el checklist NFR. Vacía = todas las secciones. */
export const tecnologias = (archivos) =>
  [...new Set(archivos.flatMap((r) => TECNOLOGIAS.filter(([re]) => re.test(r)).map(([, t]) => t)))];

/** ¿`pedido` es al menos tan profundo como `exigido`? */
export const alcanza = (pedido, exigido) => NIVELES.indexOf(pedido) >= NIVELES.indexOf(exigido) && NIVELES.includes(pedido);

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  let r;
  try {
    // Desde la raíz del repo: `git ls-files -o` devuelve rutas relativas al cwd, y
    // desde un subdirectorio los archivos sin trackear de afuera no aparecían.
    process.chdir(execFileSync(GIT, ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim());
    const porArchivo = cambioActual();
    let claseConfig;
    try { claseConfig = clasificar(porArchivo).clase; } catch { claseConfig = 'completa'; }
    r = nivelDe(porArchivo, { claseConfig });
    r.tecnologias = tecnologias(r.archivos);
  } catch (e) {
    r = { nivel: 'completa', motivos: [`no se pudo calcular: ${e.message}`], plan: PLAN.completa };
  }
  process.stdout.write(`${JSON.stringify(r)}\n`);
}
