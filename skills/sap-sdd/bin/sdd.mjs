#!/usr/bin/env node
// CLI del ciclo SDD (ADR-014). Cero dependencias: corre con `node` a secas.
//
//   node bin/sdd.mjs init <proyecto> [--raiz <dir>]
//   node bin/sdd.mjs raiz
//
// Contrato: exit 0 si hizo lo pedido, exit 1 si no pudo, exit 2 por error de uso.

import path from 'node:path';
import { crearProyecto, raizSdd, normalizarRuta, errorDeUso } from '../lib/proyecto.mjs';

function uso() {
  console.error(`uso: sdd init <proyecto> [--raiz <dir>]
     sdd raiz

  La raíz por defecto es ~/sdd-projects; SES_SDD_HOME (absoluta) o --raiz la cambian.`);
}

/**
 * Parseo estricto: una flag desconocida, una repetida o un argumento de más son
 * error de uso. Ignorarlos en silencio mandaba un proyecto a la carpeta
 * equivocada (`--raiz /a --raiz /b` usaba `/a`) o descartaba un nombre
 * (`init a b` creaba `a`).
 */
function parsear(args, flagsValidas, maxPosicionales) {
  const flags = {};
  const posicionales = [];
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (!a.startsWith('--')) { posicionales.push(a); continue; }
    if (!flagsValidas.includes(a)) throw errorDeUso(`flag desconocida: ${a}`);
    if (a in flags) throw errorDeUso(`${a} aparece más de una vez`);
    const v = args[i + 1];
    if (v === undefined || v.startsWith('--')) throw errorDeUso(`${a} necesita un valor`);
    flags[a] = v;
    i += 1;
  }
  if (posicionales.length > maxPosicionales) {
    throw errorDeUso(`argumentos de más: ${posicionales.slice(maxPosicionales).join(' ')}`);
  }
  return { flags, posicionales };
}

/** Los errores de E/S de Node dicen qué syscall falló, no qué hacer. */
const ERRORES_DE_ESCRITURA = new Set(['EACCES', 'EPERM', 'EROFS', 'ENOTDIR', 'ENOSPC']);
/** La escritura publica con `link`: hay filesystems (FUSE, 9P, algunos SMB) que no lo tienen. */
const SIN_HARD_LINKS = new Set(['ENOTSUP', 'EOPNOTSUPP', 'EXDEV']);

function explicar(e) {
  if (SIN_HARD_LINKS.has(e.code)) {
    return `el filesystem de ${e.path ?? 'la raíz SDD'} no soporta hard links (${e.code}), y sin ellos no puedo escribir de forma atómica. Usá una raíz en un disco local con --raiz <ruta>`;
  }
  if (ERRORES_DE_ESCRITURA.has(e.code)) {
    return `no puedo escribir en ${e.path ?? 'la raíz SDD'} (${e.code}). Revisá permisos y espacio, o usá otra raíz con --raiz <ruta>`;
  }
  return e.message;
}

function init(args) {
  const { flags, posicionales } = parsear(args, ['--raiz'], 1);
  const [nombre] = posicionales;
  if (!nombre) throw errorDeUso('falta el nombre del proyecto');
  // `--raiz` puede ser relativa: la escribió quien corre el comando, desde su
  // cwd. SES_SDD_HOME no, porque no se sabe desde dónde se la va a leer.
  // Un `--raiz ""` —el `--raiz "$DIR"` de un script con la variable sin
  // definir— resolvía al cwd y el proyecto aparecía en cualquier carpeta.
  if (flags['--raiz'] !== undefined && !flags['--raiz'].trim()) throw errorDeUso('--raiz necesita una ruta');
  const raiz = flags['--raiz'] === undefined ? raizSdd() : path.resolve(normalizarRuta(flags['--raiz']));
  const r = crearProyecto({ nombre, raiz });

  if (r.creados.length) console.log(`  creado:    ${r.creados.join(', ')}`);
  if (r.huerfanos.length) console.log(`  limpiado:  ${r.huerfanos.join(', ')} (temporales de una corrida interrumpida)`);
  if (r.existentes.length) console.log(`  ya estaba: ${r.existentes.join(', ')} (no se tocó)`);
  if (r.danados.length) {
    console.error(`✗ ${r.dir}: hay archivos que no sirven y no los piso: ${r.danados.join(', ')}.`);
    console.error('  Revisalos, o borralos y volvé a correr init para regenerarlos.');
    return 1;
  }
  console.log(`${r.creados.length ? '✓ proyecto listo' : '✓ el proyecto ya estaba completo'}: ${r.dir}`);
  console.log(`  la documentación del cliente va en ${path.join(r.dir, 'entradas')}/`);
  return 0;
}

function main(argv) {
  const [cmd, ...resto] = argv;
  try {
    switch (cmd) {
      case 'raiz':
        parsear(resto, [], 0);
        console.log(raizSdd());
        return 0;
      case 'init':
        return init(resto);
      case '-h': case '--help': case 'help':
        uso();
        return 0;
      case undefined:
        throw errorDeUso('falta el comando');
      default:
        throw errorDeUso(`comando desconocido: ${cmd}`);
    }
  } catch (e) {
    console.error(`✗ ${explicar(e)}`);
    if (e.uso) { uso(); return 2; }
    return 1;
  }
}

process.exitCode = main(process.argv.slice(2));
