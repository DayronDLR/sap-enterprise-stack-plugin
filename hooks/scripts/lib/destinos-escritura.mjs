/**
 * destinos-escritura.mjs — a qué archivos ESCRIBE (o borra) un comando de shell.
 *
 * `protect-sensitive-files.sh` necesita saber si un comando escribe sobre un
 * secreto, no si lo menciona. La versión anterior buscaba una intención de
 * escritura en CUALQUIER parte del comando y un nombre protegido en CUALQUIER
 * otra, y las combinaba: `cat package.json > /tmp/x` quedaba bloqueado (lee el
 * protegido, escribe otro archivo), y `node -e "[1].map(x => x)"` también,
 * porque el `>` de la flecha contaba como redirección.
 *
 * Acá se sigue cada destino hasta su comando:
 *
 *   - redirecciones (`>`, `>>`, `>|`, `N>`, `&>`), pegadas o separadas;
 *   - `tee`, `truncate`: todos sus argumentos;
 *   - `cp`, `mv`, `install`, `ln`: el último argumento (y, si es un directorio,
 *     el nombre de cada origen dentro de él);
 *   - `sed -i` y `perl -i`: los archivos, no el script;
 *   - `dd of=…`;
 *   - `rm`, `unlink`, `shred`: como BORRADO, que el hook sólo frena sobre secretos;
 *   - `sh -c`, `bash -c`, `eval`: el texto que ejecutan se analiza como otro comando;
 *   - `find -exec`, `xargs`, `parallel`: el comando que delegan también, con `{}`
 *     (o el argumento que agregan al final) como destino dinámico.
 *
 * Un destino que no se puede resolver sin ejecutar —lleva `$` o un backtick:
 * `> "$F"`, `> $'.env'`, el `"$1"` de una función— sale como DINAMICO, y el hook
 * decide con su heurística cerrada para secretos en vez de dejarlo pasar.
 *
 * Es best-effort a propósito, igual que el nivel 1 del gate de entrega: bash no
 * se analiza por completo. Lo que no ve —un `python -c` o un `node -e` que
 * escriben— lo cubre el Edit/Write del host y, para los secretos, que el archivo
 * no se commitea (`.gitignore`) y gitleaks en CI.
 *
 * Uso: `printf '%s' "$CMD" | node destinos-escritura.mjs` → líneas
 * `<tipo>\t<ruta>`, con tipo `escribe`, `borra`, `dinamico-escribe` o `dinamico-borra`.
 */

const OPERADORES = new Set([';', '&', '|', '\n', '(', ')']);
const OPERADORES_DOBLES = new Set(['&&', '||', '|&']);
const ENVOLTORIOS = new Set(['sudo', 'env', 'command', 'nohup', 'time', 'exec', 'builtin',
  'nice', 'ionice', 'stdbuf', 'timeout', 'watch']);
// Opciones que llevan un valor aparte, POR envoltorio. Una tabla común fallaba
// abierto: `-i` lleva valor en `stdbuf` pero es un flag en `sudo` y en `env`, y
// `env -i cp x .env` se salteaba `cp` como si fuera el valor de `-i`.
// Las largas también: `sudo --user root` con el valor aparte se comía el comando.
const OPCIONES_CON_VALOR = {
  sudo: new Set(['-u', '-g', '-h', '-p', '-C', '-U', '-r', '-t', '-D', '-T',
    '--user', '--group', '--host', '--prompt', '--close-from', '--other-user', '--role', '--type', '--chdir',
    '--command-timeout']),
  env: new Set(['-u', '-C', '-a', '-P', '--unset', '--chdir', '--argv0']),
  nice: new Set(['-n', '--adjustment']),
  timeout: new Set(['-s', '-k', '--signal', '--kill-after']),
  stdbuf: new Set(['-i', '-o', '-e', '--input', '--output', '--error']),
  ionice: new Set(['-c', '-n', '-p', '--class', '--classdata', '--pid']),
  time: new Set(['-o', '-f', '--output', '--format']),
  exec: new Set(['-a']),
};
// Valores sueltos que no son el comando (`timeout 5`, `nice 10`).
const VALOR_SUELTO = /^\d+(\.\d+)?[smhd]?$/;
const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh']);
// Se resuelve al ejecutar: una expansión, `{}` de find/xargs, un glob, o una
// expansión de llaves (`tee x{.env,y}` escribe `x.env`).
const DINAMICO = /[$`*?[]|\{[^}]*\}/;
const ASIGNACION = /^[A-Za-z_][A-Za-z0-9_]*=/;
const HEREDOC = /^<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/;
const REDIRECCION = /^(\d*|&)(>>|>\||>)/;

// ── Lectores: cada uno consume desde `i` y devuelve el índice siguiente ──────

function leerComillaSimple(cmd, i) {
  const fin = cmd.indexOf("'", i + 1);
  const hasta = fin === -1 ? cmd.length : fin;
  return { texto: cmd.slice(i + 1, hasta), sig: hasta + 1 };
}

function leerComillaDoble(cmd, i) {
  let texto = '';
  let j = i + 1;
  while (j < cmd.length && cmd[j] !== '"') {
    if (cmd[j] === '\\' && j + 1 < cmd.length) { texto += cmd[j + 1]; j += 2; continue; }
    texto += cmd[j++];
  }
  return { texto, sig: j + 1 };
}

/** Un heredoc: lo que sigue al marcador en su línea se analiza; el cuerpo, no. */
function leerHeredoc(cmd, i, marcador) {
  const finLinea = cmd.indexOf('\n', i);
  if (finLinea === -1) return { resto: cmd.slice(i + marcador[0].length), sig: cmd.length };
  const re = new RegExp(`\\n\\s*${marcador[1]}\\s*(\\n|$)`, 'g');
  re.lastIndex = finLinea;
  const cierre = re.exec(cmd);
  return {
    resto: cmd.slice(i + marcador[0].length, finLinea),
    sig: cierre ? cierre.index + cierre[0].length : cmd.length,
  };
}

// ── Pasos del tokenizador: cada uno reconoce una forma y avanza, o no toca nada ──

function cerrarPalabra(st) {
  if (st.hay) st.tokens.push({ t: 'palabra', v: st.actual });
  st.actual = '';
  st.hay = false;
}

const emitir = (st, t, v, avance) => { cerrarPalabra(st); st.tokens.push({ t, v }); st.i += avance; return true; };

const PASOS = [
  function escape(st, c) {
    if (c !== '\\' || st.i + 1 >= st.cmd.length) return false;
    st.actual += st.cmd[st.i + 1]; st.hay = true; st.i += 2; return true;
  },
  function comillas(st, c) {
    if (c !== "'" && c !== '"') return false;
    const { texto, sig } = c === "'" ? leerComillaSimple(st.cmd, st.i) : leerComillaDoble(st.cmd, st.i);
    st.actual += texto; st.hay = true; st.i = sig; return true;
  },
  function comentario(st, c) {
    if (c !== '#' || st.hay) return false;
    const nl = st.cmd.indexOf('\n', st.i);
    st.i = nl === -1 ? st.cmd.length : nl; return true;
  },
  function espacio(st, c) {
    if (c !== ' ' && c !== '\t') return false;
    cerrarPalabra(st); st.i++; return true;
  },
  function operadorDoble(st) {
    const dos = st.cmd.slice(st.i, st.i + 2);
    return OPERADORES_DOBLES.has(dos) && emitir(st, 'op', dos, 2);
  },
  function redireccion(st) {
    const redir = REDIRECCION.exec(st.cmd.slice(st.i));
    // `2>` es un fd pegado a la redirección; `a>b` corta la palabra `a`.
    const fdPegado = /^\d+$/.test(st.actual);
    if (!redir || !(redir[1] === '' || !st.hay || fdPegado)) return false;
    if (fdPegado) { st.actual = ''; st.hay = false; }
    return emitir(st, 'redir', redir[0], redir[0].length);
  },
  function heredoc(st, c) {
    const m = c === '<' ? HEREDOC.exec(st.cmd.slice(st.i)) : null;
    if (!m) return false;
    cerrarPalabra(st);
    const h = leerHeredoc(st.cmd, st.i, m);
    st.tokens.push(...tokenizar(h.resto), { t: 'op', v: '\n' });
    st.i = h.sig; return true;
  },
  (st, c) => c === '<' && emitir(st, 'entrada', '<', 1),
  (st, c) => OPERADORES.has(c) && emitir(st, 'op', c, 1),
];

/** Palabras y operadores, respetando comillas, escapes, comentarios y heredocs. */
export function tokenizar(cmd) {
  const st = { cmd, i: 0, actual: '', hay: false, tokens: [] };
  while (st.i < cmd.length) {
    const c = cmd[st.i];
    if (!PASOS.some((paso) => paso(st, c))) { st.actual += c; st.hay = true; st.i++; }
  }
  cerrarPalabra(st);
  return st.tokens;
}

/** Los segmentos del comando: palabras sueltas y destinos de redirección. */
function segmentos(tokens) {
  const segs = [];
  let s = { palabras: [], redirs: [] };
  for (let i = 0; i < tokens.length; i++) {
    const k = tokens[i];
    const sig = tokens[i + 1];
    if (k.t === 'op') { segs.push(s); s = { palabras: [], redirs: [] }; continue; }
    if (k.t === 'redir' || k.t === 'entrada') {
      if (sig?.t === 'palabra') { if (k.t === 'redir') s.redirs.push(sig.v); i++; }
      continue;
    }
    s.palabras.push(k.v);
  }
  segs.push(s);
  return segs;
}

const noOpcion = (args) => args.filter((a) => !a.startsWith('-'));
const esDirectorio = (r) => r === '.' || r === '..' || r.endsWith('/');
const base = (r) => r.replace(/\/+$/, '').split('/').pop();

/** El comando real del segmento, salteando asignaciones y envoltorios. */
function comandoYArgs(palabras) {
  let i = 0;
  while (i < palabras.length && ASIGNACION.test(palabras[i])) i++;
  while (i < palabras.length && ENVOLTORIOS.has(base(palabras[i]))) {
    const envoltorio = base(palabras[i]);
    const conValor = OPCIONES_CON_VALOR[envoltorio] ?? new Set();
    i++;
    while (i < palabras.length && (palabras[i].startsWith('-') || ASIGNACION.test(palabras[i]) || VALOR_SUELTO.test(palabras[i]))) {
      // `env -S "cp x .env"`: la cadena se parte y se ejecuta, como un eval.
      if (envoltorio === 'env' && /^(-S|--split-string)$/.test(palabras[i])) {
        return { cmd: 'eval', args: palabras.slice(i + 1) };
      }
      i += conValor.has(palabras[i]) ? 2 : 1;
    }
  }
  return { cmd: palabras[i] ? base(palabras[i]) : '', args: palabras.slice(i + 1) };
}

// ── Destinos por comando ────────────────────────────────────────────────────

const todos = (args) => noOpcion(args).filter((a) => !/^\d+[KMG]?$/.test(a)).map((a) => ['escribe', a]);

function copiaOMueve(args, cmd) {
  const t = args.findIndex((a) => a === '-t' || a === '--target-directory');
  if (t !== -1 && args[t + 1]) {
    const origenes = noOpcion(args.filter((_, j) => j !== t + 1));
    return origenes.map((o) => ['escribe', `${args[t + 1]}/${base(o)}`]);
  }
  const libres = noOpcion(args);
  const destino = libres.at(-1);
  if (!destino) return [];
  const origenes = libres.slice(0, -1);
  const out = [['escribe', destino]];
  if (esDirectorio(destino)) out.push(...origenes.map((o) => ['escribe', `${destino}/${base(o)}`]));
  if (cmd === 'mv') out.push(...origenes.map((o) => ['borra', o]));
  return out;
}

const OPCION_SCRIPT = /^-[a-zA-Z]*[ef]$/;

function enSitio(args) {
  const inPlace = args.some((a) => /^-[a-zA-Z]*i/.test(a) || a.startsWith('--in-place'));
  if (!inPlace) return [];
  // BSD/macOS: `sed -i '' …` lleva el sufijo de backup como argumento aparte.
  const iVacio = args.indexOf('-i');
  if (iVacio !== -1 && args[iVacio + 1] === '') args = args.filter((_, j) => j !== iVacio + 1);
  // El script va en `-e`/`-f` o es el primer argumento libre.
  const conScript = args.some((a) => OPCION_SCRIPT.test(a) || /^--(expression|file)/.test(a));
  const libres = [];
  for (let j = 0; j < args.length; j++) {
    if (OPCION_SCRIPT.test(args[j])) { j++; continue; }
    if (!args[j].startsWith('-')) libres.push(args[j]);
  }
  return (conScript ? libres : libres.slice(1)).map((a) => ['escribe', a]);
}

const POR_COMANDO = {
  tee: todos,
  truncate: todos,
  cp: copiaOMueve,
  mv: copiaOMueve,
  install: copiaOMueve,
  ln: copiaOMueve,
  sed: enSitio,
  gsed: enSitio,
  perl: enSitio,
  dd: (args) => args.filter((a) => a.startsWith('of=')).map((a) => ['escribe', a.slice(3)]),
  rm: (args) => noOpcion(args).map((a) => ['borra', a]),
  unlink: (args) => noOpcion(args).map((a) => ['borra', a]),
  shred: (args) => noOpcion(args).map((a) => ['borra', a]),
};

/** El texto que un shell ejecuta: `sh -c "…"`, `bash -lc "…"`, `eval …`. */
function textoAnidado(cmd, args) {
  if (cmd === 'eval') return args.join(' ');
  if (!SHELLS.has(cmd)) return null;
  const c = args.findIndex((a) => /^-[a-zA-Z]*c$/.test(a));
  if (c === -1) return null;
  const j = args[c + 1] === '--' ? c + 2 : c + 1;
  return args[j] !== undefined ? args[j] : null;
}

// Opciones de xargs/parallel que llevan un valor aparte.
const XARGS_CON_VALOR = new Set(['-I', '-i', '-n', '-P', '-L', '-l', '-d', '-s', '-E', '-e', '-a', '-j', '--delimiter', '--max-args']);

/**
 * El comando que delegan `find -exec` y `xargs`: `find . -exec cp {} .env \;` corre
 * `cp {} .env`; `xargs cp f` corre `cp f <cada entrada>`. La entrada es `{}`, un
 * destino que sólo se conoce al ejecutar.
 */
function delegadosDeFind(args) {
  const out = [];
  for (let k = 0; k < args.length; k++) {
    if (!/^-(exec|execdir|ok|okdir)$/.test(args[k])) continue;
    const fin = args.findIndex((a, j) => j > k && (a === ';' || a === '+'));
    out.push(args.slice(k + 1, fin === -1 ? args.length : fin));
    if (fin !== -1) k = fin;
  }
  return out;
}

function delegadosDeXargs(args) {
  let k = 0;
  let conLugar = false;
  while (k < args.length && args[k].startsWith('-')) {
    if (/^-(I|i)/.test(args[k]) || args[k] === '--replace') conLugar = true;
    k += XARGS_CON_VALOR.has(args[k]) ? 2 : 1;
  }
  const delegado = args.slice(k);
  if (!delegado.length) return [];
  // Sin `-I`, xargs agrega cada entrada al final.
  return [conLugar ? delegado : [...delegado, '{}']];
}

function comandosDelegados(cmd, args) {
  if (cmd === 'find') return delegadosDeFind(args);
  if (cmd === 'xargs' || cmd === 'parallel') return delegadosDeXargs(args);
  return [];
}

// Un destino dinámico conserva si escribía o borraba: borrar salida generada
// (`rm -rf "$PWD/node_modules"`) sigue siendo legítimo.
const conTipo = ([tipo, ruta]) => [DINAMICO.test(ruta) ? `dinamico-${tipo}` : tipo, ruta];

/** Los destinos del comando en sí: el que ejecuta un shell, el que delega, o el propio. */
function destinosDelComando(cmd, args) {
  const anidado = textoAnidado(cmd, args);
  if (anidado !== null) return destinosDeEscritura(anidado);
  const delegados = comandosDelegados(cmd, args);
  if (delegados.length) return delegados.flatMap((p) => destinosDelSegmento({ palabras: p, redirs: [] }));
  return Object.hasOwn(POR_COMANDO, cmd) ? POR_COMANDO[cmd](args, cmd) : [];
}

function destinosDelSegmento({ palabras, redirs }) {
  // `>&2` duplica un descriptor: no es un archivo.
  const out = redirs.filter((r) => !r.startsWith('&') && r !== '-').map((r) => ['escribe', r]);
  const { cmd, args } = comandoYArgs(palabras);
  return [...out, ...destinosDelComando(cmd, args)].map(conTipo);
}

export function destinosDeEscritura(cmd) {
  return segmentos(tokenizar(String(cmd))).flatMap(destinosDelSegmento);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  let raw = '';
  process.stdin.on('data', (d) => (raw += d)).on('end', () => {
    for (const [tipo, ruta] of destinosDeEscritura(raw)) process.stdout.write(`${tipo}\t${ruta}\n`);
  });
}
