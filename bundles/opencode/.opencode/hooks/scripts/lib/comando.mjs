/**
 * comando.mjs — qué parte de un comando de shell se EJECUTA y qué parte es DATO
 * (roadmap F8-a).
 *
 * POR QUE EXISTE. `delivery-gate.sh` decide si un comando es una entrega
 * buscando `git commit`, `git push` o `gh pr create` en su texto. El texto no es
 * el hecho: `cat > adr.md <<'EOF'` con un procedimiento de git adentro, un
 * `echo "git push"` o un `# git commit` en un comentario deniegan igual que la
 * entrega. Un control que bloquea trabajo legítimo enseña a apagarlo.
 *
 * QUE HACE. `sinDatos(cmd)` devuelve el mismo comando con las regiones que con
 * seguridad son DATO reemplazadas por espacios. Todo lo demás queda intacto, y
 * el matcher de siempre corre sobre el resultado:
 *
 *   - comentarios;
 *   - el cuerpo de un heredoc cuyo comando NO es un shell;
 *   - los argumentos CITADOS de un comando que sólo lee o imprime (`echo`,
 *     `printf`, `cat`, `grep`…) o de un intérprete que no es shell (`python -c`,
 *     `node -e`: la DoD ya los documenta como punto ciego del nivel 1).
 *
 * LO QUE NUNCA SE BORRA, porque se ejecuta:
 *
 *   - `$( … )`, backticks y `<( … )`, aunque estén dentro de comillas o de un
 *     heredoc sin citar: bash los ejecuta igual;
 *   - todo lo que lee un shell: los argumentos de `sh -c`, `eval`, `source`, un
 *     heredoc hacia `bash`, un pipeline con `| sh` o `| xargs`;
 *   - la palabra que ocupa el lugar del comando, y los argumentos de cualquier
 *     comando que no esté en la lista de «sólo datos» —`git`, `gh`, `find`,
 *     `ssh`, uno desconocido—.
 *
 * Y NADA SE BORRA si en el comando, a cualquier profundidad, hay algo fuera de la
 * lista CERRADA de los que no ejecutan texto (`NO_EJECUTAN`, más los
 * intérpretes): un shell, `make`, `npm`, un envoltorio como `env`, un ejecutable
 * por ruta o del PATH. Cualquiera de esos puede ejecutar lo que otro segmento
 * citó o escribió (`echo … > f; bash f`, `env -u X sh -c …`). La lista es de lo
 * seguro y no de lo peligroso porque la de peligrosos no converge.
 *
 * La decisión es POR SEGMENTO: `echo hola; git commit` sigue siendo una entrega,
 * porque `git commit` es otro comando. Y ante cualquier cosa que no se entiende
 * (una comilla sin cerrar) se devuelve el comando entero: el lado seguro es mirar
 * de más.
 *
 * Sigue siendo el nivel 1, best-effort: la garantía está en git
 * (`.husky/pre-commit`) y en CI.
 */

import path from 'node:path';

/** Comandos que sólo leen, filtran o imprimen: sus argumentos citados son datos. */
// Sin los que ejecutan un programa por opción o por entorno, aunque parezcan de
// lectura: `rg --pre`, `sort --compress-program`, `ag --pager`, `less`/`more`
// con LESSOPEN. Esta lista se amplía sólo con algo que se sabe que no ejecuta.
const DATOS = new Set([
  'echo', 'printf', 'cat', 'tac', 'grep', 'egrep', 'fgrep', 'jq',
  'tee', 'head', 'tail', 'wc', 'uniq', 'cut', 'tr', 'diff', 'cmp', 'ls',
  'touch', 'mkdir', 'rmdir', 'cp', 'mv', 'rm', 'ln', 'test', '[', 'true', 'false',
  'basename', 'dirname', 'realpath', 'readlink', 'stat', 'file',
  'column', 'fold', 'nl', 'pbcopy', 'base64', 'md5', 'md5sum', 'shasum', 'sha256sum',
]);

/** Intérpretes que no son shell: su código es dato para el nivel 1 (punto ciego documentado). */
const RE_INTERPRETE = /^(python[0-9.]*|node|nodejs|deno|bun|perl|ruby|php)$/;

/** Lo que ejecuta texto como comandos de shell. */
const SHELLS = new Set([
  'sh', 'bash', 'zsh', 'dash', 'ksh', 'mksh', 'fish', 'eval', 'source', '.',
  'xargs', 'su', 'sudo', 'doas', 'ssh', 'script', 'parallel', 'watch', 'nohup',
  'env', 'exec', 'command', 'builtin', 'time', 'nice', 'timeout', 'stdbuf',
]);

/** Prefijos que no son el comando: se saltean para encontrarlo. */
const RE_ASIGNACION = /^[A-Za-z_][A-Za-z0-9_]*=/;

const esDatos = (nombre) => DATOS.has(nombre) || RE_INTERPRETE.test(nombre);

/**
 * La lista CERRADA de comandos que no ejecutan texto de otro lado. Sólo si el
 * comando entero está hecho de estos se borra algo como dato. Es una lista de lo
 * que se sabe seguro, no de lo que se sabe peligroso: la lista de peligrosos no
 * converge (`make`, `npm run`, `env -u X sh`, un script sin barra en el PATH…).
 * Los intérpretes que no son shell quedan afuera de esta lista pero también
 * permiten borrar: su código es un punto ciego documentado del nivel 1.
 */
// `git` y `gh` NO: ejecutan texto de su configuración (un alias `!…`,
// `core.editor`, `core.fsmonitor`, una extensión de gh), y otro segmento puede
// haberla escrito. Una entrega se ve igual: no hace falta borrar nada para eso.
const NO_EJECUTAN = new Set([...DATOS, 'cd']);

/** Los de DATOS que no tocan el sistema de archivos: F8-b sigue el directorio a través de ellos. */
const SOLO_LECTURA = new Set([...DATOS].filter((n) => !['tee', 'touch', 'mkdir', 'rmdir', 'cp', 'mv', 'rm', 'ln', 'pbcopy'].includes(n)));

class NoEntiendo extends Error {}

/**
 * El valor de una palabra para reconocer el NOMBRE de un comando: sin comillas,
 * sin barras, con `$'…'` resuelto a lo simple. `"ec"ho` → `echo`. Sólo para
 * decidir si es de la lista; nunca afecta qué se borra.
 */
function nombreDe(texto) {
  const plano = texto
    .replace(/\$'((?:[^'\\]|\\.)*)'/g, (_, c) => c.replace(/\\x([0-9a-fA-F]{2})/g, (__, h) => String.fromCharCode(parseInt(h, 16))))
    .replace(/["'\\]/g, '');
  return plano.split('/').pop();
}

/** Envoltorios: el comando real viene después (`env X=1 git …`, `sudo git …`). */
const ENVOLTORIOS = new Set(['env', 'command', 'builtin', 'exec', 'nohup', 'time', 'nice', 'timeout', 'stdbuf', 'sudo', 'doas']);

/** Caracteres que terminan una palabra sin comillas (el backtick no: abre una sustitución). */
const FIN_DE_PALABRA = ' \t\n;&|()';

/**
 * El analizador. Recorre el comando una vez y marca en `mascara` los caracteres
 * que son dato. `codigo` = estamos dentro de algo que un shell va a ejecutar como
 * texto: ahí nada se marca.
 */
class Analizador {
  constructor(s) {
    this.s = s;
    this.mascara = new Uint8Array(s.length);
    /** Los comandos simples de PRIMER nivel, en orden: la base de F8-b. */
    this.registros = [];
    /** Heredocs cuyo cuerpo todavía no se leyó: llega en la línea siguiente, pase lo que pase en el medio. */
    this.pendientes = [];
    /**
     * ¿Hay, en cualquier nivel, un comando fuera de la lista cerrada de los que
     * no ejecutan texto? Un shell, `make`, `npm`, un ejecutable por ruta o un
     * envoltorio (`env -u X sh -c …`) pueden ejecutar lo que un comando «de
     * datos» escribió o citó. Entonces nada se trata como dato.
     */
    this.ejecutaTexto = false;
    /** ¿Hay alguna sustitución (`$( )`, backticks, `<( )`)? F8-b no exime entonces. */
    this.haySustitucion = false;
  }

  marcar(a, b) {
    for (let k = a; k < b; k += 1) if (this.s[k] !== '\n') this.mascara[k] = 1;
  }

  // ── Listas de comandos ──────────────────────────────────────────────────

  /** Una lista de comandos hasta `)` o `` ` `` (si `fin`) o el final del texto. */
  lista(i, fin, codigo) {
    const ctx = { fin, codigo, cmd: this.nuevo(codigo), pipeline: [] };
    while (i < this.s.length) {
      const r = this.pasoDeLista(i, ctx);
      if (r.cierra) return r.i;
      i = r.i;
    }
    if (fin) throw new NoEntiendo('lista sin cerrar');
    this.cerrarPipeline(ctx);
    return i;
  }

  pasoDeLista(i, ctx) {
    const s = this.s;
    const c = s[i];
    if (c === ')' || c === '`') { this.cerrarPipeline(ctx); return { i: i + 1, cierra: true }; }
    if (c === ' ' || c === '\t') return { i: i + 1 };
    if (c === '\\' && s[i + 1] === '\n') return { i: i + 2 };
    if (c === '\n') return { i: this.saltoDeLinea(i, ctx) };
    if (c === '#') return { i: this.comentario(i) };
    if (c === '|' || c === ';' || c === '&') return { i: this.operador(i, ctx) };
    if (c === '(') { this.cerrarPipeline(ctx); return { i: this.lista(i + 1, ')', ctx.codigo) }; }
    return { i: this.palabra(i, ctx.cmd) };
  }

  nuevo(codigo) {
    return {
      codigo, nombre: null, envoltorio: false, palabras: [], citados: [], heredocs: [],
      asignaciones: [], inicio: null, fin: null, op: ';',
    };
  }

  cerrarComando(ctx, op = ';') {
    const cmd = ctx.cmd;
    if (cmd.nombre != null || cmd.palabras.length || cmd.heredocs.length) {
      cmd.op = op;
      ctx.pipeline.push(cmd);
      if (ctx.fin == null) this.registros.push(cmd);
    }
    ctx.cmd = this.nuevo(ctx.codigo);
  }

  cerrarPipeline(ctx, op = ';') {
    this.cerrarComando(ctx, op);
    this.resolver(ctx.pipeline);
    ctx.pipeline = [];
  }

  /** Un salto de línea cierra el comando; después vienen los cuerpos de sus heredocs. */
  saltoDeLinea(i, ctx) {
    this.cerrarComando(ctx);
    const pendientes = this.pendientes;
    this.pendientes = [];
    const j = this.cuerpos(i + 1, pendientes);
    this.cerrarPipeline(ctx);
    return j;
  }

  comentario(i) {
    const nl = this.s.indexOf('\n', i);
    const hasta = nl === -1 ? this.s.length : nl;
    this.marcar(i, hasta);
    return hasta;
  }

  /** `|` (y `|&`) une comandos en un pipeline; `;`, `&`, `&&`, `||` cierran el pipeline. */
  operador(i, ctx) {
    const s = this.s;
    const c = s[i];
    if (c === '|' && s[i + 1] !== '|') {
      this.cerrarComando(ctx, '|');
      return i + (s[i + 1] === '&' ? 2 : 1);
    }
    const doble = s[i + 1] === c;
    this.cerrarPipeline(ctx, doble ? c + c : c);
    return i + (doble ? 2 : 1);
  }

  /**
   * Decide un pipeline entero: si alguno de sus comandos es un shell, lo que
   * fluye por el pipe es código y no se marca nada. Si no, cada comando marca
   * sus argumentos citados y sus heredocs según su propio nombre.
   */
  resolver(pipeline) {
    const conShell = pipeline.some((c) => SHELLS.has(c.nombre) && !c.envoltorio);
    for (const c of pipeline) {
      const dato = !(c.codigo || conShell || !esDatos(c.nombre));
      // El cuerpo de un heredoc puede llegar DESPUÉS de cerrar el pipeline
      // (`cat <<EOF && …`): la decisión queda en el heredoc y se aplica al leerlo.
      for (const h of c.heredocs) {
        h.esDato = dato;
        if (dato) for (const [a, b] of h.literal) this.marcar(a, b);
      }
      if (dato) for (const [a, b] of c.citados) this.marcar(a, b);
    }
  }

  // ── Palabras ────────────────────────────────────────────────────────────

  /** Una palabra: literales, citados, sustituciones. Registra su rol en `cmd`. */
  palabra(i, cmd) {
    const s = this.s;
    if (s.startsWith('<<<', i)) return this.hereString(i + 3, cmd);
    if (s.startsWith('<<', i)) return this.operadorHeredoc(i + 2, cmd);
    const citados = [];
    const fin = this.leerPalabra(i, cmd, citados);
    this.registrarPalabra(cmd, i, fin, citados);
    return fin;
  }

  saltarBlancos(i) {
    while (this.s[i] === ' ' || this.s[i] === '\t') i += 1;
    return i;
  }

  /**
   * `<<< palabra`: el texto del here-string es dato del comando, citado o no;
   * sus `$( )` y backticks se ejecutan y no se marcan.
   */
  hereString(i, cmd) {
    const a = this.saltarBlancos(i);
    const b = this.leerPalabra(a, cmd, []);
    cmd.citados.push(...this.tramosLiterales(a, b));
    return b;
  }

  /** `<< DELIM` o `<<- DELIM`: el cuerpo se lee al terminar la línea. */
  operadorHeredoc(i, cmd) {
    const quitaTabs = this.s[i] === '-';
    const d0 = this.saltarBlancos(quitaTabs ? i + 1 : i);
    const fin = this.leerPalabra(d0, cmd, []);
    const delim = this.s.slice(d0, fin);
    const h = {
      delim: delim.replace(/["'\\]/g, ''), citado: /["'\\]/.test(delim), quitaTabs, literal: [], cuerpo: null, esDato: null,
    };
    cmd.heredocs.push(h);
    this.pendientes.push(h);
    return fin;
  }

  /** Decide el rol de una palabra: asignación, envoltorio, nombre del comando o argumento. */
  registrarPalabra(cmd, inicio, fin, citados) {
    const texto = this.s.slice(inicio, fin);
    if (cmd.inicio == null) cmd.inicio = inicio;
    cmd.fin = fin;
    if (!this.enNombre(cmd)) {
      cmd.palabras.push([inicio, fin]);
      cmd.citados.push(...citados);
      return;
    }
    if (RE_ASIGNACION.test(texto)) { cmd.asignaciones.push(texto); return; }
    if (texto === '!' || texto === '{' || texto === '}') return;
    if (cmd.envoltorio && texto.startsWith('-')) return;
    const nombre = nombreDe(texto);
    // Envoltorios encadenados (`sudo env git …`): el comando real es el primero
    // que no es un envoltorio.
    cmd.envoltorio = ENVOLTORIOS.has(nombre);
    cmd.nombre = nombre;
    // Una asignación delante (`LESSOPEN=… cmd`, `GIT_…=… cmd`) puede cambiar lo
    // que el comando ejecuta: tampoco se borra nada.
    if (texto.includes('/') || cmd.asignaciones.length > 0
        || (!NO_EJECUTAN.has(nombre) && !RE_INTERPRETE.test(nombre))) {
      this.ejecutaTexto = true;
    }
  }

  enNombre(cmd) {
    return cmd.nombre == null || cmd.envoltorio;
  }

  /** ¿La salida de una sustitución en esta posición es código? */
  sustEsCodigo(cmd) {
    return cmd.codigo || this.enNombre(cmd) || SHELLS.has(cmd.nombre);
  }

  terminaPalabra(i) {
    const s = this.s;
    const c = s[i];
    if (!FIN_DE_PALABRA.includes(c)) return false;
    // `$(`, `<(`, `>(` abren una sustitución dentro de la palabra.
    return !(c === '(' && '$<>'.includes(s[i - 1]));
  }

  /**
   * Avanza sobre una palabra y devuelve dónde termina. Anota en `citados` los
   * tramos de texto literal entre comillas; las sustituciones que haya adentro se
   * recorren aparte y nunca se marcan como dato.
   */
  leerPalabra(i, cmd, citados) {
    while (i < this.s.length && !this.terminaPalabra(i)) i = this.pasoDePalabra(i, cmd, citados);
    return i;
  }

  pasoDePalabra(i, cmd, citados) {
    const s = this.s;
    const c = s[i];
    if (c === '\\') return i + 2;
    if (c === "'") return this.comillaSimple(i, citados);
    if (c === '"') return this.dobles(i + 1, cmd, citados);
    if (c === '$' && s[i + 1] === "'") return this.ansiC(i, citados);
    if (c === '$' && s[i + 1] === '{') return this.llave(i);
    if (c === '`' || ('$<>'.includes(c) && s[i + 1] === '(')) return this.sustitucion(i, this.sustEsCodigo(cmd));
    return i + 1;
  }

  comillaSimple(i, citados) {
    const f = this.s.indexOf("'", i + 1);
    if (f === -1) throw new NoEntiendo('comilla simple sin cerrar');
    citados.push([i, f + 1]);
    return f + 1;
  }

  ansiC(i, citados) {
    const s = this.s;
    let k = i + 2;
    while (k < s.length && s[k] !== "'") k += s[k] === '\\' ? 2 : 1;
    if (k >= s.length) throw new NoEntiendo('$\' sin cerrar');
    citados.push([i, k + 1]);
    return k + 1;
  }

  llave(i) {
    const f = this.s.indexOf('}', i + 2);
    if (f === -1) throw new NoEntiendo('${ sin cerrar');
    return f + 1;
  }

  /**
   * `$( … )`, `<( … )`, `>( … )`, backticks o `$(( … ))` en `i`: se recorre como
   * lista de comandos —se ejecuta siempre— y se devuelve dónde termina.
   */
  sustitucion(i, codigo) {
    const s = this.s;
    this.haySustitucion = true;
    if (s[i] === '`') return this.lista(i + 1, '`', codigo);
    if (s[i] === '$' && s[i + 2] === '(') return this.aritmetica(i + 3);
    return this.lista(i + 2, ')', codigo);
  }

  /** Comillas dobles: el literal es dato; `$( )` y backticks adentro, no. */
  dobles(i, cmd, citados) {
    const s = this.s;
    let tramo = i - 1;
    while (i < s.length) {
      const c = s[i];
      if (c === '"') { citados.push([tramo, i + 1]); return i + 1; }
      if ((c === '$' && s[i + 1] === '(') || c === '`') {
        citados.push([tramo, i]);
        i = this.sustitucion(i, this.sustEsCodigo(cmd));
        tramo = i;
      } else {
        i += c === '\\' ? 2 : 1;
      }
    }
    throw new NoEntiendo('comilla doble sin cerrar');
  }

  aritmetica(i) {
    const f = this.s.indexOf('))', i);
    if (f === -1) throw new NoEntiendo('$(( sin cerrar');
    return f + 2;
  }

  // ── Heredocs ────────────────────────────────────────────────────────────

  /**
   * Los cuerpos de los heredocs pendientes, en orden, a partir de la línea `i`.
   * Un cuerpo con delimitador citado es literal entero; uno sin citar se expande,
   * así que sus `$( )` y backticks se ejecutan y no se marcan.
   */
  cuerpos(i, pendientes) {
    for (const h of pendientes) {
      const { fin, siguiente } = this.finDeHeredoc(i, h);
      h.cuerpo = [i, fin];
      h.literal.push(...(h.citado ? [[i, fin]] : this.tramosLiterales(i, fin)));
      if (h.esDato) for (const [a, b] of h.literal) this.marcar(a, b);
      i = siguiente;
    }
    return Math.min(i, this.s.length);
  }

  /** Dónde termina el cuerpo (la línea del delimitador) y dónde sigue el comando. */
  finDeHeredoc(i, h) {
    const s = this.s;
    while (i < s.length) {
      const nl = s.indexOf('\n', i);
      const hasta = nl === -1 ? s.length : nl;
      const linea = h.quitaTabs ? s.slice(i, hasta).replace(/^\t+/, '') : s.slice(i, hasta);
      if (linea === h.delim) return { fin: i, siguiente: nl === -1 ? s.length : nl + 1 };
      if (nl === -1) break;
      i = nl + 1;
    }
    throw new NoEntiendo('heredoc sin cerrar');
  }

  /** Los tramos literales de un texto que se expande: todo menos sus sustituciones. */
  tramosLiterales(a, b) {
    const s = this.s;
    const tramos = [];
    let tramo = a;
    let i = a;
    while (i < b) {
      if ((s[i] === '$' && s[i + 1] === '(') || s[i] === '`') {
        tramos.push([tramo, i]);
        // Lo que se ejecuta adentro se analiza como cualquier comando.
        i = this.sustitucion(i, false);
        tramo = i;
      } else {
        i += s[i] === '\\' ? 2 : 1;
      }
    }
    tramos.push([tramo, b]);
    return tramos;
  }
}

/** El texto con las regiones marcadas reemplazadas por espacios. */
function marcado(a, s) {
  let out = '';
  for (let k = 0; k < s.length; k += 1) out += a.mascara[k] ? ' ' : s[k];
  return out;
}

/**
 * El comando con sus regiones de DATO reemplazadas por espacios (los saltos de
 * línea se conservan). Si algo no se entiende, el comando tal cual.
 */
export function sinDatos(cmd) {
  const s = String(cmd ?? '');
  try {
    const a = new Analizador(s);
    a.lista(0, null, false);
    return a.ejecutaTexto ? s : marcado(a, s);
  } catch (e) {
    if (e instanceof NoEntiendo) return s;
    throw e;
  }
}

// ─── F8-b: ¿en qué repo cae la entrega? ─────────────────────────────────────

/**
 * El valor literal de una palabra, o `null` si depende de algo que sólo se sabe
 * al ejecutar (una variable, una sustitución, un glob). `"a b"` → `a b`.
 */
function valorLiteral(texto) {
  if (/[$`*?[\n]/.test(texto.replace(/'[^']*'/g, ''))) return null;
  return texto.replace(/'([^']*)'|"([^"]*)"|\\(.)/g, (_, a, b, c) => a ?? b ?? c);
}

const MAX_LARGO_DIR = 4096;

/** ¿Este comando de primer nivel deja el directorio donde lo sigue `destinos`? */
function comandoSeguible(r) {
  if (r.nombre == null || r.envoltorio) return false;
  // Los que cambian a qué apunta una ruta (`ln -sfn`, `mv`) no: el hook resuelve
  // el destino ANTES de que corran.
  return r.nombre === 'cd' || r.nombre === 'git' || r.nombre === 'gh' || SOLO_LECTURA.has(r.nombre);
}

/** `-C x` sobre `d`; null si cualquiera de los dos es desconocido. */
const conC = (d, x) => (x == null || d == null ? null : path.resolve(d, x));

/** `-C <dir>` acumulados sobre `dir`; `null` si el repo no es el directorio. */
function dirDeGit(vals, dir) {
  let d = dir;
  for (let k = 0; k < vals.length; k += 1) {
    const v = vals[k];
    if (v == null || /^--(git-dir|work-tree|namespace)/.test(v)) return { dir: null };
    if (!v.startsWith('-')) return ['commit', 'push'].includes(v) ? { dir: d } : null;
    if (v === '-C') d = conC(d, vals[k + 1]);
    if (v === '-C' || v === '-c') k += 1;
  }
  return null;
}

/** La entrega de un comando de primer nivel: `{ dir }` (dir null = no se sabe), o null si no es una. */
function entregaDe(r, s, dir) {
  if (r.envoltorio) return null;
  const vals = r.palabras.map(([a, b]) => valorLiteral(s.slice(a, b)));
  if (r.nombre === 'gh') {
    if (vals[0] !== 'pr' || !['create', 'new'].includes(vals[1])) return null;
    // `--repo` apunta a otro repositorio de GitHub: no se resuelve localmente.
    return { dir: vals.some((v) => v == null || v === '-R' || /^--repo(=|$)/.test(v)) ? null : dir };
  }
  if (r.nombre !== 'git') return null;
  // `GIT_DIR=… git commit`: el repo no es el directorio.
  if (r.asignaciones.some((x) => /^GIT_/.test(x))) return { dir: null };
  return dirDeGit(vals, dir);
}

/**
 * El directorio después de un `cd`, o `null` si no se puede saber. Un `cd` cambia
 * el directorio sólo si se encadena con `;`, `&&` o un salto de línea: detrás de
 * `||`, en un pipe o en segundo plano puede fallar o correr en un subshell.
 */
function trasCd(r, s, dir, opPrevio, home) {
  if (opPrevio === '|' || ['|', '||', '&'].includes(r.op) || dir == null) return null;
  const args = r.palabras.map(([x, y]) => valorLiteral(s.slice(x, y)));
  // Sólo `cd` o `cd <dir>`: `cd -` vuelve a OLDPWD, y las opciones o un segundo
  // argumento no se interpretan acá.
  if (args.length > 1 || args.some((v) => v == null || v.startsWith('-'))) return null;
  let destino = args.length ? args[0] : (home || null);
  // Un nombre sin barra adelante (`cd sub`) lo busca bash en CDPATH antes que en
  // el directorio actual, y CDPATH puede venir del entorno o de una asignación
  // delante (`CDPATH=… cd sub`): no se sigue. Sí una
  // ruta absoluta, `./`, `../` o `~`, que bash nunca busca en CDPATH.
  if (args.length && !/^(\/|\.\.?(\/|$)|~(\/|$))/.test(destino)) return null;
  if (destino === '~') destino = home || null;
  else if (destino?.startsWith('~/')) destino = home ? path.join(home, destino.slice(2)) : null;
  return destino == null ? null : path.resolve(dir, destino);
}

/**
 * El directorio de cada entrega de primer nivel, en orden, y las marca en la
 * máscara para que no queden en el resto.
 */
function directoriosDeEntrega(a, s, cwd, home) {
  let dir = cwd ? path.resolve(cwd) : null;
  let opPrevio = ';';
  const dirs = [];
  for (const r of a.registros) {
    // Sólo se sigue el directorio a través de comandos que no lo pueden mover
    // por otra vía: `cd <literal>`, git, gh y los de datos. `pushd`, `eval`,
    // `source`, `if`/`for`, `export GIT_DIR=…` o una asignación suelta dejan el
    // destino desconocido.
    if (!comandoSeguible(r)) dir = null;
    if (r.nombre === 'cd' && !r.envoltorio) dir = trasCd(r, s, dir, opPrevio, home);
    // Miles de `cd` encadenados hacían crecer `dir` y cada `path.resolve` lo
    // recorría entero: cuadrático, y con 90.000 pasaba el timeout del hook. Un
    // directorio más largo que esto no es un destino real: se deja de eximir.
    if (dir != null && dir.length > MAX_LARGO_DIR) dir = null;
    const ent = entregaDe(r, s, dir);
    if (ent) {
      dirs.push(ent.dir);
      a.marcar(r.inicio, r.fin);
    }
    opPrevio = r.op;
  }
  return dirs;
}

/**
 * Dónde caen las entregas de primer nivel de `cmd`, ejecutado desde `cwd`:
 *
 *   - `dirs`: el directorio de cada una, o `null` si alguna no se pudo resolver;
 *   - `resto`: el comando con los datos borrados Y esas entregas borradas. Si el
 *     matcher todavía ve una entrega en `resto`, hay una que este análisis no
 *     atribuyó —en un subshell, en un `sh -c`, detrás de un `find -exec`— y la
 *     exención no aplica.
 */
export function destinos(cmd, cwd, home) {
  const s = String(cmd ?? '');
  let a;
  try {
    a = new Analizador(s);
    a.lista(0, null, false);
  } catch (e) {
    if (e instanceof NoEntiendo) return { dirs: null, resto: s };
    throw e;
  }
  if (a.ejecutaTexto) a.mascara.fill(0);
  const dirs = directoriosDeEntrega(a, s, cwd, home);
  // Una sustitución corre ANTES que el comando que la contiene: un `ln -sfn`
  // adentro de `$( )` cambia a qué apunta la ruta del `cd` que viene después, y
  // el análisis la resolvió antes. Con una sustitución en el comando, no se exime.
  if (a.haySustitucion) return { dirs: null, resto: marcado(a, s) };
  return { dirs: dirs.some((d) => d == null) ? null : dirs, resto: marcado(a, s) };
}
