#!/usr/bin/env node
/**
 * config-risk-scan.mjs — el Gate 1 sobre la configuración que EJECUTA código.
 *
 * `package.json`, los lockfiles y `mta.yaml` no son "sólo configuración": un
 * `postinstall` corre en la máquina de cada dev y en CI con sólo hacer
 * `npm install`, y una dependencia que apunta a un repo o a una URL se baja sin
 * pasar por el registro. Hasta ahora eso dependía de que el reviewer (un LLM) lo
 * notara, y el hook de archivos sensibles tapaba el problema bloqueando la
 * edición entera, lo que empujaba al agente a editar por el shell.
 *
 * Este scan es determinístico y compara lo que se entrega con `HEAD`:
 *
 *   CRITICAL (bloquea):
 *     - `package.json`: un script de ciclo de vida (`preinstall`, `install`,
 *       `postinstall`, `prepare`, `prepack`, `postpack`, `prepublish*`,
 *       `*uninstall`) agregado o cambiado;
 *     - `package.json`: una dependencia (o override) nueva o cambiada que no sale
 *       del registro: `git+`, `github:`, `http(s):`, `file:`, `link:`, `usuario/repo`;
 *     - lockfiles: un `resolved`/`tarball` nuevo fuera de los registros conocidos,
 *       o una entrada nueva sin `integrity`;
 *     - `mta.yaml`, `package.json` (cualquier script): un comando nuevo que baja y
 *       ejecuta (`curl … | sh`, `wget … | bash`, `bash -c "$(curl …)"`).
 *   WARN (se muestra, no bloquea; saca el cambio de la clase `config-trivial`):
 *     - `publishConfig.registry`, `bin` cambiados;
 *     - autenticación o autorización tocadas: claves de `cds` con auth en
 *       `package.json`, roles y scopes de xsuaa en `mta.yaml`, `scope` o
 *       `authenticationType` en `xs-app.json`;
 *     - código que corre en el build o en el navegador: `customTasks` y
 *       `customMiddleware` en `ui5*.yaml`, URIs y recursos en `manifest.json`.
 *
 * Un cambio legítimo de esa lista (agregar `"prepare": "husky"`) no se hace pasar:
 * se muestra, y la persona lo aprueba exportando `SES_CONFIG_RISK=allow` en SU
 * shell para esa entrega. Queda en `logs/config-risk-overrides.log`.
 *
 * Uso: node config-risk-scan.mjs <ruta>... (rutas relativas a la raíz del repo).
 * Sale 1 si hay CRITICAL, 0 si no. Imprime los hallazgos con `[CRITICAL]`/`[WARN]`.
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const CICLO_DE_VIDA = new Set([
  'preinstall', 'install', 'postinstall', 'prepare', 'prepack', 'postpack',
  'prepublish', 'prepublishOnly', 'publish', 'postpublish',
  'preuninstall', 'uninstall', 'postuninstall',
  // No es una sección: npm 8+ corre el script `dependencies` después de cualquier
  // operación que cambie node_modules.
  'dependencies',
]);
// `bundledDependencies` es el nombre de la documentación de npm; `bundleDependencies`,
// el alias. npm honra los dos.
const SECCIONES_DEP = ['dependencies', 'devDependencies', 'optionalDependencies',
  'peerDependencies', 'bundledDependencies', 'bundleDependencies', 'overrides', 'resolutions'];
const REGISTROS = new Set(['registry.npmjs.org', 'registry.npmjs.com', 'registry.yarnpkg.com',
  'npm.pkg.github.com',
  ...String(process.env.SES_NPM_REGISTRIES || '').split(/[,\s]+/).filter(Boolean)]);
// Baja algo de la red y se lo pasa a un intérprete, en sus formas habituales:
// `curl … | sh`, `bash -c "$(curl …)"`, `bash <(curl …)`, `eval "$(curl …)"`,
// `curl -o f … && sh f`, y `npx` de un paquete que no sale del registro.
const BAJA_Y_EJECUTA = new RegExp([
  String.raw`(curl|wget|iwr|Invoke-WebRequest)\b[^\n|]{0,500}\|\s*(sudo\s+)?(sh|bash|zsh|node|python3?)\b`,
  String.raw`\b(sh|bash|zsh)\s+(-c\s+["']?\$\(|<\s*\()\s*(curl|wget)`,
  String.raw`\beval\s+["']?\$\(\s*(curl|wget)`,
  String.raw`(curl|wget)\b[^\n&;|]{0,300}(\s-[oO]\s*|>\s*)\S+[^\n&;|]{0,300}(&&|;)\s*(sudo\s+)?(sh|bash|zsh|python3?|chmod\s+\+x)\b`,
  String.raw`\bnpx\s+(-y\s+|--yes\s+)?(github:|gitlab:|git\+|https?:)`,
].join('|'), 'i');
// `curl -o x.js … && node x.js`: baja un archivo y lo corre con un intérprete. Se
// exige que sea EL MISMO archivo: `curl -o data.json … && node build.js` es un build.
// `./x.js` y `x.js` son el mismo archivo: el `./` opcional va de los dos lados.
const BAJA_Y_CORRE = /(curl|wget)\b[^\n&;|]{0,300}?(?:\s-[oO]\s*|>\s*)(?:\.\/)?(\S+)[^\n&;|]{0,300}(?:&&|;)\s*(?:sudo\s+)?(?:node|python3?|bun|deno|tsx|ts-node|perl|ruby)\s+(?:-\S*\s+)*(?:\.\/)?\2(?:\s|$)/i;
const bajaYEjecuta = (texto) => BAJA_Y_EJECUTA.test(texto) || BAJA_Y_CORRE.test(texto);

/**
 * `git` por ruta absoluta, no resuelto por el PATH en cada spawn (SonarJS S4036).
 * Es la técnica de `scripts/lib/resolve-bin.js`, que el plugin no trae: el hook
 * tiene que andar en el proyecto del cliente.
 */
function resolverBinario(nombre) {
  for (const dir of String(process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const candidato = path.join(dir, nombre);
    try { fs.accessSync(candidato, fs.constants.X_OK); return candidato; } catch { /* sigue buscando */ }
  }
  return null;
}
const GIT = resolverBinario('git');

// Sin git no hay base: cada versión se compara contra vacío, que es lo más estricto.
const git = (...args) => {
  if (!GIT) return null;
  try { return execFileSync(GIT, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch { return null; }
};

/** Las versiones que se entregan: la del índice y la del working tree, si difieren. */
function versiones(ruta) {
  const out = new Set();
  const indice = git('show', `:${ruta}`);
  if (indice !== null) out.add(indice);
  try { out.add(fs.readFileSync(ruta, 'utf8')); } catch { /* borrado */ }
  return [...out];
}

// npm acepta un BOM al principio de `package.json`; `JSON.parse`, no. Sin
// quitarlo, el scan veía "no parsea", devolvía cero hallazgos y el Gate 1 daba ✓
// mientras npm corría el `postinstall`.
const sinBom = (t) => String(t).replace(/^\uFEFF/, '');
const json = (t) => { try { return JSON.parse(sinBom(t)); } catch { return null; } };

/** Una especificación de dependencia que no sale del registro. */
export function fueraDelRegistro(spec) {
  if (typeof spec !== 'string') return false;
  const s = spec.replace(/^npm:[^@]*@?/, '');
  if (/^(git\+|git:|github:|gitlab:|bitbucket:|gist:|https?:|file:|link:|portal:)/i.test(s)) return true;
  // `usuario/repo` o `usuario/repo#rama`: GitHub implícito. `@scope/pkg@1` no.
  return /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(#.*)?$/.test(s);
}

const esCicloDeVida = (k) => CICLO_DE_VIDA.has(k) || CICLO_DE_VIDA.has(k.replace(/^(pre|post)/, ''));

function scanScripts(ruta, antes, ahora, hallazgos) {
  const previos = antes.scripts || {};
  for (const [k, v] of Object.entries(ahora.scripts || {})) {
    if (previos[k] === v) continue;
    if (esCicloDeVida(k)) {
      hallazgos.push(['CRITICAL', `${ruta}: script de ciclo de vida "${k}" ${k in previos ? 'cambiado' : 'agregado'} (corre solo con npm install): ${JSON.stringify(v)}`]);
    } else if (bajaYEjecuta(String(v))) {
      hallazgos.push(['CRITICAL', `${ruta}: el script "${k}" baja y ejecuta código de la red: ${JSON.stringify(v)}`]);
    }
  }
}

/** `{a: {b: "x"}}` → `[["a > b", "x"]]`: los overrides pueden anidar. */
const aplanar = (o, pre = '') => Object.entries(o || {}).flatMap(([k, v]) =>
  v && typeof v === 'object' ? aplanar(v, `${pre}${k} > `) : [[`${pre}${k}`, v]]);

function scanDependencias(ruta, seccion, antes, ahora, hallazgos) {
  const previo = new Map(aplanar(antes));
  for (const [nombre, spec] of aplanar(ahora)) {
    if (previo.get(nombre) !== spec && fueraDelRegistro(spec)) {
      hallazgos.push(['CRITICAL', `${ruta}: ${seccion} "${nombre}" apunta fuera del registro: ${JSON.stringify(spec)}`]);
    }
  }
}

function scanPackageJson(ruta, base, nuevo, hallazgos) {
  const antes = json(base) || {};
  const ahora = json(nuevo);
  // Lo que no se puede leer no se puede aprobar.
  if (!ahora) { noParsea(ruta, nuevo, hallazgos); return; }
  scanScripts(ruta, antes, ahora, hallazgos);
  for (const sec of SECCIONES_DEP) scanDependencias(ruta, sec, antes[sec], ahora[sec], hallazgos);
  scanDependencias(ruta, 'pnpm.overrides', antes.pnpm?.overrides, ahora.pnpm?.overrides, hallazgos);
  // Autenticación de CAP: `cds.requires.auth` de `xsuaa` a `dummy` apaga el login.
  const authCds = (o) => new Map(aplanar(o?.cds).filter(([k]) => /auth|roles?\b|restrict|xsuaa|\bias\b|cors|security/i.test(k)));
  const [a0, a1] = [authCds(antes), authCds(ahora)];
  for (const k of new Set([...a0.keys(), ...a1.keys()])) {
    if (a0.get(k) !== a1.get(k)) {
      hallazgos.push(['WARN', `${ruta}: cambia la autenticación o autorización de CAP (cds > ${k}): ${JSON.stringify(a0.get(k))} → ${JSON.stringify(a1.get(k))}`]);
    }
  }
  if (JSON.stringify(antes.publishConfig?.registry) !== JSON.stringify(ahora.publishConfig?.registry)) {
    hallazgos.push(['WARN', `${ruta}: publishConfig.registry cambió a ${JSON.stringify(ahora.publishConfig?.registry)}`]);
  }
  if (JSON.stringify(antes.bin) !== JSON.stringify(ahora.bin)) {
    hallazgos.push(['WARN', `${ruta}: "bin" cambió: los comandos que instala el paquete son otros`]);
  }
}

/** Líneas agregadas respecto de la base (multiconjunto: una línea repetida cuenta). */
function agregadas(base, nuevo) {
  const cuenta = new Map();
  for (const l of base.split('\n')) cuenta.set(l, (cuenta.get(l) || 0) + 1);
  const out = [];
  for (const l of nuevo.split('\n')) {
    const n = cuenta.get(l) || 0;
    if (n > 0) cuenta.set(l, n - 1); else out.push(l);
  }
  return out;
}

function hostFueraDeRegistro(url) {
  try {
    const u = new URL(url);
    return !REGISTROS.has(u.hostname) ? u.hostname : null;
  } catch { return 'url inválida'; }
}

const DESDE_REPO = /^(git\+|git:|file:)/;

/** Los hallazgos de UNA entrada del lockfile que cambió. */
function hallazgosDeEntrada(ruta, k, p) {
  if (!p.resolved) return [];
  const out = [];
  const host = DESDE_REPO.test(p.resolved) ? p.resolved.split(':')[0] : hostFueraDeRegistro(p.resolved);
  if (host) out.push(['CRITICAL', `${ruta}: "${k}" se resuelve fuera del registro (${host}): ${p.resolved}`]);
  if (!p.integrity && !DESDE_REPO.test(p.resolved)) {
    out.push(['CRITICAL', `${ruta}: "${k}" no tiene integrity: no se puede verificar lo que se baja`]);
  }
  return out;
}

function scanNpmLock(ruta, base, nuevo, hallazgos) {
  const antes = json(base)?.packages || {};
  const nuevoJson = json(nuevo);
  if (!nuevoJson) { noParsea(ruta, nuevo, hallazgos); return; }
  const ahora = nuevoJson.packages;
  if (!ahora) return;
  for (const [k, p] of Object.entries(ahora)) {
    const previo = antes[k];
    const igual = previo && previo.resolved === p.resolved && previo.integrity === p.integrity;
    if (k && !p.link && !igual) hallazgos.push(...hallazgosDeEntrada(ruta, k, p));
  }
}

/** Una entrada de pnpm o yarn que se baja sin hash no se puede verificar. */
function sinIntegrity(ruta, base, nuevo, hallazgos) {
  const nuevas = new Set(agregadas(base, nuevo));
  const lineas = nuevo.split('\n');
  lineas.forEach((l, i) => {
    if (!nuevas.has(l)) return;
    // pnpm: `resolution: {tarball: …}` sin `integrity` en el mismo objeto.
    if (/^\s*resolution:\s*\{[^}]*tarball:/.test(l) && !/integrity:/.test(l)) {
      hallazgos.push(['CRITICAL', `${ruta}: dependencia con tarball y sin integrity: ${l.trim()}`]);
    }
    // yarn v1: `resolved "…"` y, en las líneas siguientes de la misma entrada, `integrity`.
    if (/^\s+resolved\s+"https?:/.test(l)) {
      const entrada = lineas.slice(i + 1, i + 4).join('\n');
      if (!/^\s+integrity\s/m.test(entrada)) {
        hallazgos.push(['CRITICAL', `${ruta}: dependencia resuelta sin integrity: ${l.trim()}`]);
      }
    }
  });
}

function scanTextoLock(ruta, base, nuevo, hallazgos) {
  sinIntegrity(ruta, base, nuevo, hallazgos);
  for (const l of agregadas(base, nuevo)) {
    const url = /(tarball|resolved)["']?:?\s*["']?(\S+?)["']?\s*[,}]?$/.exec(l.trim());
    if (url && /^https?:|^git/.test(url[2])) {
      const host = url[2].startsWith('git') ? 'git' : hostFueraDeRegistro(url[2]);
      if (host) hallazgos.push(['CRITICAL', `${ruta}: dependencia resuelta fuera del registro (${host}): ${url[2]}`]);
    }
    if (/^\s*resolution:\s*\{\s*(repo|type:\s*git)/.test(l)) {
      hallazgos.push(['CRITICAL', `${ruta}: dependencia resuelta desde un repo git: ${l.trim()}`]);
    }
  }
}

/** Líneas agregadas o quitadas que cumplen `re`: un WARN por la primera. */
function tocaLineas(ruta, base, nuevo, re, que, hallazgos) {
  const cambiadas = [...agregadas(base, nuevo), ...agregadas(nuevo, base)].filter((l) => re.test(l));
  if (cambiadas.length) hallazgos.push(['WARN', `${ruta}: ${que}: ${cambiadas[0].trim()}`]);
}

const MTA_SEGURIDAD = /role-templates|role-collections|scope|xsappname|oauth2-configuration|redirect-uris|tenant-mode|authorities|xs-security|service-plan/i;

function scanMta(ruta, base, nuevo, hallazgos) {
  for (const l of agregadas(base, nuevo)) {
    if (bajaYEjecuta(l)) hallazgos.push(['CRITICAL', `${ruta}: comando de build que baja y ejecuta código: ${l.trim()}`]);
  }
  tocaLineas(ruta, base, nuevo, MTA_SEGURIDAD, 'cambia la configuración de seguridad (xsuaa, roles o scopes)', hallazgos);
}

function scanXsApp(ruta, base, nuevo, hallazgos) {
  const cuenta = (t) => (t.match(/"authenticationType"\s*:\s*"none"/g) || []).length;
  if (cuenta(nuevo) > cuenta(base)) {
    hallazgos.push(['WARN', `${ruta}: una ruta nueva con authenticationType "none" — confirmá que es un recurso público`]);
    return;
  }
  tocaLineas(ruta, base, nuevo, /"(scope|authenticationType|authenticationMethod|csrfProtection|identityProvider)"/,
    'cambia la autenticación o autorización de una ruta', hallazgos);
}

function scanUi5Yaml(ruta, base, nuevo, hallazgos) {
  tocaLineas(ruta, base, nuevo, /customTasks|customMiddleware|beforeTask|afterTask|beforeMiddleware|afterMiddleware/,
    'cambia código que corre en el build o en el servidor de desarrollo', hallazgos);
}

function scanManifest(ruta, base, nuevo, hallazgos) {
  tocaLineas(ruta, base, nuevo, /"(uri|url|js|css|libs|resources|componentUsages|resourceRoots|destinations?)"\s*:/,
    'cambia una URI o un recurso que carga la app', hallazgos);
}

function noParsea(ruta, texto, hallazgos) {
  if (!String(texto).trim()) return;
  hallazgos.push(['CRITICAL', `${ruta}: no es JSON válido, así que no se puede revisar lo que ejecuta. Corregilo antes de entregar.`]);
}

export function scanArchivo(ruta, base, nuevo) {
  const hallazgos = [];
  const nombre = path.basename(ruta);
  if (nombre === 'package.json') scanPackageJson(ruta, base, nuevo, hallazgos);
  else if (nombre === 'package-lock.json' || nombre === 'npm-shrinkwrap.json') scanNpmLock(ruta, base, nuevo, hallazgos);
  else if (nombre === 'pnpm-lock.yaml' || nombre === 'yarn.lock') scanTextoLock(ruta, base, nuevo, hallazgos);
  else if (/^mta(-.*)?\.ya?ml$|\.mtaext$/.test(nombre)) scanMta(ruta, base, nuevo, hallazgos);
  else if (nombre === 'xs-app.json') scanXsApp(ruta, base, nuevo, hallazgos);
  else if (/^ui5[^/]*\.ya?ml$/.test(nombre)) scanUi5Yaml(ruta, base, nuevo, hallazgos);
  else if (nombre === 'manifest.json') scanManifest(ruta, base, nuevo, hallazgos);
  return hallazgos;
}

export const ES_CONFIG_RIESGO = /(^|\/)(package\.json|package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|mta(-[^/]*)?\.ya?ml|[^/]*\.mtaext|xs-app\.json|ui5[^/]*\.ya?ml|manifest\.json)$/;

if (import.meta.url === `file://${process.argv[1]}`) {
  const hallazgos = [];
  for (const ruta of process.argv.slice(2)) {
    if (!ES_CONFIG_RIESGO.test(ruta)) continue;
    const base = git('show', `HEAD:${ruta}`) ?? '';
    for (const v of versiones(ruta)) {
      for (const h of scanArchivo(ruta, base, v)) {
        if (!hallazgos.some(([s, m]) => s === h[0] && m === h[1])) hallazgos.push(h);
      }
    }
  }
  for (const [sev, msg] of hallazgos) console.log(`[${sev}] ${msg}`);
  process.exit(hallazgos.some(([s]) => s === 'CRITICAL') ? 1 : 0);
}
