/**
 * artefactos.mjs — comprueba que los archivos que un subagente DICE haber
 * producido existan de verdad.
 *
 * POR QUE EXISTE. `/sap-techlead` hace que cada subagente cierre con
 * `ESTADO: COMPLETADO | Artefactos producidos: [lista]`. Esa linea esta en el
 * contrato desde siempre y **nadie la comprueba**: un agente que devuelve los
 * hallazgos como texto, o que nombra un archivo que no llego a escribir, cierra
 * igual con COMPLETADO y el orquestador lo da por bueno.
 *
 * Es el mismo principio que el guard de produccion: no se aprueba una
 * afirmacion, se resuelve el hecho. La verificacion corre en el hook de
 * `SubagentStop`, no dentro del agente — pedirle al agente que verifique lo que
 * el mismo declaro es volver a confiar en una afirmacion.
 *
 * LOS DOS MODOS DE FALLA QUE IMPORTAN, y son opuestos:
 *
 *   - Falso NEGATIVO: una ruta declarada que el parser no reconoce sale de la
 *     lista, `verificarArtefactos` no recibe nada que chequear y el hook aprueba
 *     EN SILENCIO. Es el peor: parece cobertura y no la hay.
 *   - Falso POSITIVO: reportar "no existe" sobre un archivo que si se creo
 *     entrena al orquestador a ignorar el aviso, y entonces el control deja de
 *     servir aunque siga corriendo.
 *
 * Cada regla de abajo esta escrita contra uno de los dos.
 */
import fs from 'node:fs';
import path from 'node:path';

/**
 * Extensiones largas: SAP tiene varias que pasan los 8 caracteres
 * (`.hdbcalculationview` son 18). Con el limite viejo, un agente HANA que
 * declaraba `salesReport.hdbcalculationview` sin directorio delante producia
 * lista vacia y el hook aprobaba sin comprobar nada.
 */
const EXTENSION = /\.[A-Za-z][A-Za-z0-9]{0,19}$/;

/**
 * Archivos reales sin extension. Sin esto, `Makefile` se descartaba.
 *
 * Se compara en MINUSCULAS: un modelo escribe `makefile` o `dockerfile` tan
 * seguido como la forma canonica, y un Set case-sensitive los dejaba afuera —
 * falso negativo silencioso, que es el peor de los dos modos de falla.
 */
const SIN_EXTENSION = new Set([
  'makefile', 'dockerfile', 'jenkinsfile', 'procfile', 'vagrantfile',
  'rakefile', 'gemfile', 'berksfile', 'podfile', 'fastfile', 'brewfile',
  'license', 'notice', 'readme', 'changelog', 'codeowners', 'authors',
]);

/**
 * Formas de decir "ninguno". `N/A` es la que mas aparece y la que mas engania:
 * lleva `/`, asi que cualquier heuristica basada en "parece ruta" la acepta y el
 * hook reporta que falta un archivo llamado `N/A`.
 */
const NO_ES_RUTA = new Set([
  'n/a', 'na', 'ninguno', 'ninguna', 'nada', 'none', 'n/d', 'tbd', '-', '—',
]);

/**
 * Extrae las rutas declaradas del mensaje final de un subagente.
 *
 * El formato que pide el contrato es una lista despues de
 * `Artefactos producidos:`. Se aceptan las formas que un modelo produce de
 * verdad —numerada, con guiones, en una linea separada por comas, con backticks,
 * en negrita, como link markdown— porque endurecer el formato solo mueve el
 * problema: el agente escribe lo que escribe, y un parser estricto devuelve cero
 * rutas y aprueba por omision.
 */
export function rutasDeclaradas(mensaje) {
  const texto = String(mensaje || '');
  const m = /Artefactos\s+producidos\s*:?\s*([\s\S]*)/i.exec(texto);
  if (!m) return [];

  const rutas = [];
  for (const linea of m[1].split('\n')) {
    // Se corta en la primera linea que claramente ya no es la lista.
    if (/^\s*(##|ESTADO\s*:)/i.test(linea)) break;
    const limpia = linea
      .replace(/^\s*(?:[-*•]|\d+[.)])\s*/, '')   // vinetas y numeracion
      .trim();
    if (!limpia) continue;
    for (const trozo of limpia.split(/\s*[,;]\s*/)) {
      const ruta = extraerRuta(trozo);
      if (ruta) rutas.push(ruta);
    }
  }
  return [...new Set(rutas)];
}

/**
 * Saca el adorno markdown que un modelo pone alrededor de una ruta.
 *
 * El `_` NO se pela, aunque sea marca de italica. Pelarlo rompia rutas
 * legitimas y frecuentes —`_helpers.js`, `__init__.py`, `_layouts/x.html`— y las
 * reportaba como inexistentes con el nombre cambiado. Un aviso que se equivoca
 * asi entrena al orquestador a ignorarlo, que es el modo de falla que este
 * modulo existe para no producir. La italica sobre una ruta es mucho menos
 * frecuente que un modulo con guion bajo adelante.
 */
function desadornar(s) {
  return String(s)
    .trim()
    .replace(/^\[([^\]]+)\]\([^)]*\)$/, '$1')   // [texto](link) -> texto
    .replace(/^\*\*|\*\*$/g, '')                 // **negrita**
    .replace(/^[`'"*]+|[`'"*]+$/g, '')           // comillas, backticks, enfasis
    .replace(/[.,;:]+$/, '')                     // puntuacion de cierre
    .trim();
}

/**
 * ¿Este token puede ser una ruta de archivo?
 *
 * Se exige extension, separador de ruta, o ser un nombre conocido sin extension.
 * Sin este filtro, cualquier palabra suelta de la prosa posterior a la lista se
 * reporta como artefacto faltante — y un aviso que se equivoca seguido deja de
 * leerse.
 */
/**
 * Verbos de shell. Un comando entre backticks no es un artefacto por mucho que
 * nombre un archivo: aceptar espacios dentro de backticks —necesario para las
 * rutas con espacio— hacia que `bash scripts/deploy.sh` entrara como un
 * artefacto que falta, que es el falso positivo mas ruidoso posible porque el
 * contrato pide justamente backticks.
 */
const VERBO_SHELL = new RegExp(
  '^(?:'
  // Runtimes y gestores
  + 'npm|npx|pnpm|yarn|node|deno|bun|bash|sh|zsh|python3?|pip|poetry|ruby|perl'
  + '|java|mvn|gradle|go|cargo|rustc|dotnet|flutter'
  // La caja de herramientas SAP, que es la que aparece de verdad en este stack:
  // `cds serve db/schema.cds` es literalmente lo que cierra un subagente de CAP.
  + '|cds|ui5|abaplint|hdbsql|hdbcli|cf|btp'
  // Infra y datos
  + '|docker|kubectl|helm|terraform|ansible|psql|mysql|sqlite3'
  // Utilidades de shell
  + '|make|cmake|git|cd|ls|cp|mv|rm|mkdir|touch|echo|cat|grep|sed|awk|find|curl|wget'
  // Y como el modelo escribe en espanol
  + '|corr[eé]|ejecut[aá]|run'
  + ')\\s', 'i');

function esRutaPlausible(t, entreBackticks = false) {
  if (!t) return false;
  // Los espacios solo se aceptan DENTRO de backticks. Fuera, un token con
  // espacios es prosa, y aceptarlo convierte cualquier frase en un artefacto que
  // falta. Adentro, el backtick ya es la senial de "esto es una ruta": sin esta
  // excepcion, `mi dir/mi archivo.js` se descartaba en silencio aunque el
  // contrato de `/sap-techlead` pide justamente backticks.
  if (!entreBackticks && /\s/.test(t)) return false;
  if (entreBackticks && VERBO_SHELL.test(t)) return false;
  if (NO_ES_RUTA.has(t.toLowerCase())) return false;
  // `./` y `.` resuelven a la raiz del proyecto: no son un artefacto producido.
  if (/^\.{1,2}\/?$/.test(t)) return false;
  return EXTENSION.test(t) || t.includes('/') || SIN_EXTENSION.has(t.toLowerCase());
}

/** Una ruta plausible dentro de un trozo de texto, o `''`. */
function extraerRuta(trozo) {
  const directo = desadornar(trozo);
  if (esRutaPlausible(directo)) return directo;

  // `- srv/app.js (nuevo)` y `- srv/app.js — creado` son de las formas mas
  // frecuentes que produce un modelo, y caian en el falso negativo SILENCIOSO:
  // cero rutas, el hook aprueba sin decir nada.
  //
  // Se mira SOLO EL PRIMER token, no cualquiera. Una linea de la lista empieza
  // con la ruta; la prosa empieza con una palabra. Buscar en todos los tokens
  // convertia `Cubre AS-IS/TO-BE en DEV/QAS` en un artefacto que falta —la barra
  // de la jerga SAP alcanza para parecer ruta— que es el falso positivo que este
  // modulo tiene que evitar tanto como el negativo.
  const t = String(trozo).trim();
  if (!VERBO_SHELL.test(t)) {
    const primero = desadornar(t.split(/\s+/)[0] || '');
    // En este camino se exige EXTENSION (o nombre conocido sin ella), no basta
    // con la barra. `S/4HANA integration`, `AS-IS/TO-BE mapping` y
    // `DEV/QAS/PRD landscape` abren un item de lista y la barra sola alcanzaba
    // para tomarlos por ruta: el aviso decia "no existe: S/4HANA" sobre algo que
    // nadie dijo producir. Repetido dos o tres veces, el orquestador aprende a
    // ignorar el aviso — y ahi el control sigue corriendo y ya no sirve.
    if ((EXTENSION.test(primero) || SIN_EXTENSION.has(primero.toLowerCase()))
        && esRutaPlausible(primero)) return primero;
  }

  // Con espacios alrededor, solo vale lo que venga entre backticks: el resto es
  // prosa. El contenido del backtick pasa por el MISMO filtro de plausibilidad —
  // sin eso, un `Corre \`npm test\`` despues de la lista se reportaba como un
  // artefacto que falta.
  const enBackticks = /`([^`]+)`/.exec(trozo);
  if (enBackticks) {
    const dentro = desadornar(enBackticks[1]);
    if (esRutaPlausible(dentro, true)) return dentro;
  }
  return '';
}

/**
 * Verifica cada ruta contra el disco.
 *
 * Un archivo VACIO cuenta como faltante: declarar un artefacto y dejar el
 * archivo en cero bytes es el mismo modo de falla que no escribirlo, y es el que
 * mas cuesta detectar despues. Un directorio vacio cuenta igual, por simetria:
 * declarar `db/` y no escribir nada adentro no produjo nada.
 *
 * Una ruta que cae FUERA de la raiz —absoluta, o con `..`— no cumple el
 * contrato: se puede satisfacer nombrando cualquier archivo que exista en la
 * maquina (`/etc/hosts` pasaba). Se reporta aparte, porque el motivo es
 * distinto y la correccion tambien.
 */
/** En qué estado está UNA ruta: `ok`, `faltan`, `vacios` o `fuera`. */
function estadoDe(ruta, base) {
  const abs = path.resolve(base, ruta);
  if (abs !== base && !abs.startsWith(base + path.sep)) return 'fuera';
  let st;
  try {
    st = fs.statSync(abs);
  } catch {
    return 'faltan';
  }
  // `path.resolve` NO resuelve symlinks y `statSync` SI los sigue: un enlace
  // dentro del proyecto apuntando afuera (`srv/enlace.js -> /etc/hosts`) pasaba
  // el control de arriba y contaba como producido. Se compara el destino real.
  try {
    const real = fs.realpathSync(abs);
    const raizReal = fs.realpathSync(base);
    if (real !== raizReal && !real.startsWith(raizReal + path.sep)) return 'fuera';
  } catch { /* si no se puede resolver, decide lo que ya vio `statSync` */ }
  if (st.isDirectory()) {
    let vacio = true;
    try { vacio = fs.readdirSync(abs).length === 0; } catch { vacio = false; }
    return vacio ? 'vacios' : 'ok';
  }
  return st.size === 0 ? 'vacios' : 'ok';
}

export function verificarArtefactos(rutas, raiz = process.cwd()) {
  const base = path.resolve(raiz);
  const r = { ok: [], faltan: [], vacios: [], fuera: [], total: rutas.length };
  for (const ruta of rutas) r[estadoDe(ruta, base)].push(ruta);
  return r;
}

/**
 * Cuantas rutas se nombran por categoria antes de resumir.
 *
 * El aviso entra al CONTEXTO del orquestador via `additionalContext`. Una tarea
 * que declara miles de artefactos produciria un aviso de megabytes que desplaza
 * del contexto justo lo que hay que revisar. Con nombrar las primeras alcanza
 * para diagnosticar; el total va en el encabezado.
 */
const MAX_LISTADAS = 20;

function listar(rutas) {
  if (rutas.length <= MAX_LISTADAS) return rutas.join(', ');
  return `${rutas.slice(0, MAX_LISTADAS).join(', ')} … y ${rutas.length - MAX_LISTADAS} más`;
}

/** El aviso para el orquestador, o `''` si no hay nada que decir. */
export function informe({ ok, faltan, vacios, fuera, total }) {
  const sinRuta = fuera || [];
  if (!total || (!faltan.length && !vacios.length && !sinRuta.length)) return '';
  const partes = [];
  if (faltan.length) partes.push(`no existen: ${listar(faltan)}`);
  if (vacios.length) partes.push(`vacíos: ${listar(vacios)}`);
  if (sinRuta.length) partes.push(`fuera del proyecto: ${listar(sinRuta)}`);
  return `[artefactos] El subagente declaró ${total} artefacto(s) y ${partes.join(' · ')}. `
    + `${ok.length} sí está(n). Verificá antes de darlo por terminado: una tarea que `
    + 'declara lo que no produjo se propaga como hecha.';
}
