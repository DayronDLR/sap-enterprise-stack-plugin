/**
 * El proyecto SDD en disco: dónde vive y cómo nace (ADR-014, fase P1).
 *
 * Un proyecto SDD es la carpeta que se presenta ANTES de abrir el repo de código
 * del cliente: requerimiento, escenarios, diseño y plan. Por eso vive fuera de
 * todo work tree de git, bajo `SES_SDD_HOME` (por defecto `~/sdd-projects`).
 *
 * Cero dependencias y sin binarios externos: la detección de git camina los
 * directorios buscando `.git` en vez de llamar a `git`, así corre con `node` a
 * secas en BAS y Cloud Foundry, igual que el motor de `sap-diagrams`.
 */
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/** Las cuatro fases del ciclo, en orden. El orden ES la dependencia. */
export const FASES = [
  { id: 'C1', dir: 'C1-captura', titulo: 'Captura' },
  { id: 'C2', dir: 'C2-escenarios', titulo: 'Escenarios' },
  { id: 'C3', dir: 'C3-diseno', titulo: 'Diseño' },
  { id: 'C4', dir: 'C4-plan', titulo: 'Plan' },
];

export const VERSION_ESTADO = 1;

/**
 * Minúsculas, dígitos y guiones, empezando por letra o dígito.
 *
 * No es estética: el nombre se concatena a una ruta. Con `..`, `/` o un nombre
 * que empieza con `-` (y se lee como flag) el proyecto nacería fuera de la raíz.
 */
const RE_NOMBRE = /^[a-z0-9][a-z0-9-]{0,62}$/;

/**
 * Un error de USO (exit 2 en el CLI), a diferencia de uno de ejecución (exit 1):
 * el pedido estaba mal formado y reintentarlo igual no sirve.
 */
export function errorDeUso(mensaje) {
  const e = new Error(mensaje);
  e.uso = true;
  return e;
}

export function validarNombre(nombre) {
  if (typeof nombre !== 'string' || !RE_NOMBRE.test(nombre)) {
    return `nombre de proyecto inválido: ${JSON.stringify(nombre)} — usá minúsculas, dígitos y guiones (máx. 63), p. ej. "aging-ar-mx"`;
  }
  return null;
}

/**
 * Recorta espacios y expande un `~` inicial.
 *
 * Una ruta que llega por una variable de entorno o entre comillas no pasa por
 * la expansión del shell: `SES_SDD_HOME='~/sdd'` creaba un directorio llamado
 * `~` en el cwd, que es justo el que un `rm -rf ~` descuidado confunde con el home.
 */
export function normalizarRuta(valor, home = os.homedir()) {
  const v = valor.trim();
  if (v === '~') return home;
  return v.startsWith('~/') ? path.join(home, v.slice(2)) : v;
}

/**
 * La raíz de los proyectos SDD. `SES_SDD_HOME` vacía cuenta como ausente.
 *
 * Tiene que ser absoluta: una raíz relativa depende del cwd, y los proyectos
 * aparecen y desaparecen según desde dónde se corra el comando.
 *
 * Se lee con el acceso directo por nombre, no con un alias del entorno: el
 * escaneo de `env-allowlist.test.js` sólo ve las lecturas escritas así.
 */
export function raizSdd(pedida = process.env.SES_SDD_HOME, home = os.homedir()) {
  if (!pedida || !pedida.trim()) return path.join(home, 'sdd-projects');
  const r = normalizarRuta(pedida, home);
  if (!path.isAbsolute(r)) {
    throw errorDeUso(`SES_SDD_HOME tiene que ser una ruta absoluta (vale ${JSON.stringify(pedida)})`);
  }
  return path.resolve(r);
}

/**
 * El work tree de git que contiene `dir`, o `null`.
 *
 * Camina hacia arriba desde el primer ancestro que existe: la raíz del proyecto
 * todavía no existe cuando se pregunta. `.git` puede ser un directorio o un
 * ARCHIVO (worktrees y submódulos); los dos cuentan.
 */
export function repoQueContiene(dir) {
  let d = path.resolve(dir);
  while (!fs.existsSync(d)) {
    const padre = path.dirname(d);
    if (padre === d) return null;
    d = padre;
  }
  d = fs.realpathSync(d);
  for (;;) {
    if (fs.existsSync(path.join(d, '.git'))) return d;
    const padre = path.dirname(d);
    if (padre === d) return null;
    d = padre;
  }
}

/** El `estado.json` de un proyecto recién creado: todas las fases pendientes. */
export function estadoInicial(nombre, ahora) {
  const fases = {};
  for (const f of FASES) fases[f.id] = { estado: 'pendiente', aprobacion: null, consumio: {}, artefactos: {} };
  return { version: VERSION_ESTADO, proyecto: nombre, creado: ahora.toISOString(), fases };
}

/** AAAA-MM-DD en la hora LOCAL: una aprobación a las 22 h no es del día siguiente. */
export function fecha(ahora) {
  const p = (n) => String(n).padStart(2, '0');
  return `${ahora.getFullYear()}-${p(ahora.getMonth() + 1)}-${p(ahora.getDate())}`;
}

/**
 * El bloque de estado de la portada. Va entre marcadores para que
 * `ses sdd estado` (P2) lo pueda reescribir sin tocar lo que el arquitecto
 * agregue alrededor.
 */
export function bloqueEstado(estado, calculado = {}) {
  const filas = FASES.map((f) => {
    const e = estado.fases[f.id];
    const aprob = e.aprobacion ? `${e.aprobacion.dec} (${e.aprobacion.fecha})` : '—';
    // El estado GUARDADO dice "aprobada" aunque una edición posterior la haya
    // dejado vieja; si hay uno calculado, manda ése.
    return `| ${f.id} | [${f.titulo}](${f.dir}/) | ${calculado[f.id] ?? e.estado} | ${aprob} |`;
  });
  return [
    '<!-- sdd:estado -->',
    '| Fase | Carpeta | Estado | Última aprobación |',
    '|---|---|---|---|',
    ...filas,
    '<!-- /sdd:estado -->',
  ].join('\n');
}

function portada(nombre, estado, ahora) {
  return `# ${nombre} — SDD

Especificación previa al desarrollo: requerimiento, escenarios, diseño y plan.
Cada fase se lee sola; el orden importa porque cada una se apoya en la anterior.

- **Creado:** ${fecha(ahora)}
- **Decisiones:** [decisiones.md](decisiones.md)

${bloqueEstado(estado)}

## Cómo leer esta carpeta

| Carpeta | Qué contiene |
|---|---|
| \`C1-captura/\` | El requerimiento normalizado, la especificación funcional y el gap analysis |
| \`C2-escenarios/\` | Escenarios y criterios de aceptación, cada uno con cita al requerimiento |
| \`C3-diseno/\` | Arquitectura de la solución y objetos por capa |
| \`C4-plan/\` | Plan de trabajo, dependencias, transportes, riesgos y estimación |

\`entradas/\` guarda la documentación original del cliente y no se incluye en el
paquete de presentación.
`;
}

function plantillaDecisiones(nombre, ahora) {
  return `# Decisiones — ${nombre}

Registro de decisiones del proyecto. Cada entrada es inmutable: si una decisión
cambia, se agrega una nueva que la reemplaza y se la nombra.

Avanzar de fase exige una entrada de tipo **Aprobación de gate**, con el hash de
los artefactos aprobados.

<!-- Formato de cada entrada:

## DEC-001 — <título>

- **Fecha:** ${fecha(ahora)}
- **Tipo:** Funcional | Técnica | Aprobación de gate
- **Fase:** C1 | C2 | C3 | C4
- **Decide:** <nombre>

<qué se decidió y por qué>
-->
`;
}

/**
 * Lo que `init` escribe, como lista de rutas relativas y contenidos. Separado de
 * la escritura para poder mirarlo en un test sin tocar el disco.
 */
export function planDeProyecto(nombre, ahora) {
  const estado = estadoInicial(nombre, ahora);
  return {
    dirs: ['entradas', ...FASES.map((f) => f.dir)],
    archivos: [
      { rel: 'README.md', contenido: portada(nombre, estado, ahora) },
      { rel: 'decisiones.md', contenido: plantillaDecisiones(nombre, ahora) },
      { rel: 'estado.json', contenido: `${JSON.stringify(estado, null, 2)}\n` },
      // Por si alguien versiona la carpeta después: la documentación del cliente
      // no entra a un repo aunque el proyecto sí lo haga (ADR-014 §3).
      { rel: '.gitignore', contenido: '# Documentación original del cliente: nunca se versiona.\nentradas/\n' },
    ],
  };
}

/** Lanza si la raíz está dentro de un work tree de git. */
export function exigirFueraDeGit(raizAbs) {
  const repo = repoQueContiene(raizAbs);
  if (!repo) return;
  throw new Error(
    `la raíz SDD ${raizAbs} está dentro del repo git ${repo}. Un proyecto SDD vive ` +
    'fuera de todo repo de código (ADR-014). Usá otra raíz: SES_SDD_HOME=<ruta> o --raiz <ruta>',
  );
}

/**
 * Lanza si en el lugar del proyecto hay algo que no es un directorio.
 *
 * lstat, no stat: un symlink en el lugar del proyecto llevaría la escritura a
 * otro lado, y un archivo común con ese nombre no es un proyecto.
 */
function exigirLugarLibre(dir) {
  let st;
  try { st = fs.lstatSync(dir); } catch (e) {
    if (e.code === 'ENOENT') return;
    throw e;
  }
  if (!st.isDirectory()) {
    throw new Error(`${dir} existe y no es un directorio (${st.isSymbolicLink() ? 'symlink' : 'archivo'}); no lo toco`);
  }
}

/**
 * Crea `p` en exclusiva y devuelve true, o false si ya existía con el tipo
 * esperado. Crear primero y mirar después —en vez de mirar y crear— es lo que
 * hace segura la concurrencia: entre un `existsSync` y un `mkdirSync` otro
 * `init` puede haber creado la carpeta, y el segundo moría con EEXIST.
 *
 * EEXIST no basta para decir "ya estaba": también lo da un objeto de OTRO tipo
 * (un directorio donde va `estado.json`), y contarlo como existente dejaría un
 * proyecto roto que init da por completo.
 */
function crearEnExclusiva(p, crear, esDelTipo, tipo) {
  try {
    crear();
    return true;
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    if (!esDelTipo(fs.lstatSync(p))) throw new Error(`${p} existe y no es un ${tipo}; no lo toco`);
    return false;
  }
}

/**
 * Escribe `p` entero o no lo escribe: nunca deja un archivo a medias.
 *
 * `writeFileSync` con `wx` crea el archivo y DESPUÉS escribe. Un SIGKILL o un
 * disco lleno en el medio dejaba un `estado.json` o un `.gitignore` de 0 bytes
 * que la corrida siguiente daba por bueno para siempre, y un `.gitignore` vacío
 * deja de proteger `entradas/`. Acá el contenido va primero a un temporal y se
 * publica con `link`, que es atómico y exclusivo: falla con EEXIST si `p` ya
 * existe, igual que `wx`.
 *
 * Una caída deja a lo sumo un `.<nombre>.<uuid>.tmp` huérfano, nunca un archivo
 * canónico incompleto.
 *
 * El temporal lleva un UUID, no pid + milisegundos: la corrida que sigue a una
 * caída puede tener el mismo pid en el mismo milisegundo, y su EEXIST sobre el
 * TEMPORAL se leía como "el archivo canónico ya existe". Por la misma razón un
 * error del temporal nunca sale con el código EEXIST.
 */
export function escribirEntero(p, contenido) {
  const tmp = path.join(path.dirname(p), `.${path.basename(p)}.${randomUUID()}.tmp`);
  try {
    try {
      fs.writeFileSync(tmp, contenido, { flag: 'wx' });
    } catch (e) {
      if (e.code === 'EEXIST') throw new Error(`colisión improbable con el temporal ${tmp}; reintentá`);
      throw e;
    }
    fs.linkSync(tmp, p);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

/** Antigüedad a partir de la cual un temporal es de una corrida muerta. */
export const EDAD_HUERFANO_MS = 60_000;

/**
 * Borra los temporales que dejó una corrida matada (un SIGKILL no corre el
 * `finally` de `escribirEntero`). Sólo los de NUESTRO patrón y con más de
 * `EDAD_HUERFANO_MS`: un `init` vivo termina en milisegundos, y borrar el
 * temporal de uno que está corriendo en paralelo le haría fallar el `link`.
 */
function limpiarHuerfanos(dir, nombres, ahoraMs) {
  // Escape completo, no sólo del punto: un nombre con `(` o `+` agregado al
  // plan armaría un patrón que matchea de más y borra lo que no es suyo.
  const canon = nombres.map((n) => n.replace(/[.*+?^${}()|[\]\\/-]/g, '\\$&')).join('|');
  const re = new RegExp(`^\\.(?:${canon})\\.[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\\.tmp$`);
  const borrados = [];
  for (const n of fs.readdirSync(dir)) {
    if (!re.test(n)) continue;
    const p = path.join(dir, n);
    // Entre el readdir y el lstat, el `init` dueño de un temporal vivo lo borra.
    // Que ya no esté es el caso normal con corridas en paralelo, no un error.
    let st;
    try { st = fs.lstatSync(p); } catch (e) {
      if (e.code === 'ENOENT') continue;
      throw e;
    }
    if (st.isFile() && ahoraMs - st.mtimeMs > EDAD_HUERFANO_MS) {
      fs.rmSync(p, { force: true });
      borrados.push(n);
    }
  }
  return borrados;
}

/**
 * Los archivos que ya estaban pero no sirven: vacíos, o un `estado.json` que no
 * parsea. `init` no los pisa —nunca pisa—, pero tampoco puede decir "completo".
 */
function danados(dir, existentes) {
  const malos = [];
  for (const rel of existentes) {
    if (rel.endsWith('/')) continue;
    const p = path.join(dir, rel);
    if (fs.statSync(p).size === 0) {
      malos.push(`${rel} (vacío)`);
    } else if (rel === 'estado.json') {
      try { JSON.parse(fs.readFileSync(p, 'utf8')); } catch { malos.push(`${rel} (no es JSON válido)`); }
    }
  }
  return malos;
}

/**
 * Crea el proyecto, o completa lo que le falte. NUNCA pisa un archivo.
 *
 * Idempotente y seguro ante `init` concurrentes: cada carpeta y cada archivo se
 * crean en exclusiva (`mkdir` sin `recursive`, `wx`), así que de dos corridas
 * simultáneas una crea y la otra lo cuenta como existente.
 *
 * Devuelve `{ dir, creados, existentes, danados, huerfanos }`, o lanza con un mensaje
 * accionable.
 */
export function crearProyecto({ nombre, raiz, ahora = new Date() }) {
  const malo = validarNombre(nombre);
  if (malo) throw errorDeUso(malo);

  const raizAbs = path.resolve(raiz);
  exigirFueraDeGit(raizAbs);
  const dir = path.join(raizAbs, nombre);
  exigirLugarLibre(dir);

  const plan = planDeProyecto(nombre, ahora);
  const creados = [];
  const existentes = [];
  const anotar = (nuevo, rel) => (nuevo ? creados : existentes).push(rel);

  // La raíz puede crearse recursiva; el proyecto NO. Con `recursive`, un symlink
  // plantado entre `exigirLugarLibre` y este mkdir se seguía en silencio. En
  // exclusiva, ese caso cae en EEXIST y el lstat lo rechaza.
  fs.mkdirSync(raizAbs, { recursive: true });
  crearEnExclusiva(dir, () => fs.mkdirSync(dir), (st) => st.isDirectory(), 'directorio');
  for (const rel of plan.dirs) {
    const p = path.join(dir, rel);
    anotar(crearEnExclusiva(p, () => fs.mkdirSync(p), (st) => st.isDirectory(), 'directorio'), `${rel}/`);
  }
  for (const { rel, contenido } of plan.archivos) {
    const p = path.join(dir, rel);
    anotar(crearEnExclusiva(p, () => escribirEntero(p, contenido), (st) => st.isFile(), 'archivo'), rel);
  }
  const huerfanos = limpiarHuerfanos(dir, plan.archivos.map((a) => a.rel), Date.now());
  return { dir, creados, existentes, danados: danados(dir, existentes), huerfanos };
}
