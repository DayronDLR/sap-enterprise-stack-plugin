/**
 * `sdd empaquetar`: la carpeta del proyecto como el `.zip` que se presenta
 * (ADR-014 §3, fase P2).
 *
 * Sin dependencias: el formato zip es un encabezado por archivo, un directorio
 * central y un cierre, y `zlib` ya trae el deflate. Lo que NO hace: zip64 (más
 * de 65.535 archivos o 4 GB) ni cifrado. Si alguna vez pasa esos límites, se
 * rechaza en vez de escribir un zip que ningún lector abre.
 *
 * Memoria acotada: el zip se escribe a disco a medida que se arma, y un archivo
 * de más de `MAX_COMPRIMIR` va guardado sin comprimir y copiado por bloques. Un
 * `entradas/` con un PDF de 600 MB costaba 2,4 GB de RSS con todo en memoria.
 */
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

import { errorDeUso, FASES, EDAD_HUERFANO_MS } from './proyecto.mjs';
import { calcularEstado, actualizarPortada, archivosBajo, conLock, abrirProyecto } from './verificacion.mjs';

const TABLA_CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

/** crc32 en JS, incremental: `previo` es el crc de lo anterior. */
export function crc32Js(buf, previo = 0) {
  let c = (previo ^ 0xffffffff) >>> 0;
  for (const b of buf) c = TABLA_CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** `zlib.crc32` (Node ≥ 22.2) es ~250 veces más rápido; el de JS queda de respaldo. */
export const crc32 = typeof zlib.crc32 === 'function' ? (buf, previo = 0) => zlib.crc32(buf, previo) : crc32Js;

/** Fecha y hora en el formato DOS del zip (resolución de 2 s, desde 1980). */
function fechaDos(d) {
  const anio = Math.max(d.getFullYear(), 1980);
  return {
    hora: (d.getHours() << 11) | (d.getMinutes() << 5) | Math.floor(d.getSeconds() / 2),
    fecha: ((anio - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate(),
  };
}

const LIMITE = 0xffffffff;
export const MAX_COMPRIMIR = 32 * 1024 * 1024;
const BLOQUE = 1 << 20;

/**
 * Escribe un zip con `entradas` = [{ nombre, datos? , ruta? }] a través de
 * `escribir(buf)`. Cada entrada trae sus datos en memoria (`datos`) o una ruta
 * (`ruta`) que se lee por bloques si es grande. Un `nombre` que termina en `/`
 * es un directorio vacío. El bit 11 marca los nombres como UTF-8, y se
 * normalizan a NFC: macOS guarda "diseño" descompuesto y Windows lo mostraría
 * con el acento suelto.
 */
export function escribirZip(entradas, escribir, ahora = new Date()) {
  if (entradas.length >= 0xffff) throw new Error(`demasiados archivos para un zip sin zip64 (${entradas.length})`);
  const { hora, fecha } = fechaDos(ahora);
  const centrales = [];
  let offset = 0;
  const emitir = (buf) => { escribir(buf); offset += buf.length; };

  for (const e of entradas) {
    const n = Buffer.from(e.nombre.normalize('NFC'), 'utf8');
    const esDir = e.nombre.endsWith('/');
    const { crc, tam, metodo, cuerpo } = prepararCuerpo(e, esDir);
    if (tam >= LIMITE || offset >= LIMITE) throw new Error('el paquete supera 4 GB: no se arma sin zip64');
    const inicio = offset;

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(metodo, 8);
    local.writeUInt16LE(hora, 10);
    local.writeUInt16LE(fecha, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(cuerpo ? cuerpo.length : tam, 18);
    local.writeUInt32LE(tam, 22);
    local.writeUInt16LE(n.length, 26);
    emitir(local);
    emitir(n);
    emitirCuerpo(e, cuerpo, { tam, crc }, emitir);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE((3 << 8) | 20, 4);          // hecho en unix, versión 2.0
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(metodo, 10);
    central.writeUInt16LE(hora, 12);
    central.writeUInt16LE(fecha, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(cuerpo ? cuerpo.length : tam, 20);
    central.writeUInt32LE(tam, 24);
    central.writeUInt16LE(n.length, 28);
    // Atributos unix en los 16 bits altos: archivo rw-r--r-- o directorio
    // rwxr-xr-x (este último con el bit de directorio de MS-DOS, 0x10).
    central.writeUInt32LE(esDir ? ((0o40755 << 16) | 0x10) >>> 0 : (0o100644 << 16) >>> 0, 38);
    central.writeUInt32LE(inicio, 42);
    centrales.push(central, n);
  }
  const dirCentral = Buffer.concat(centrales);
  const inicioCentral = offset;
  emitir(dirCentral);
  const fin = Buffer.alloc(22);
  fin.writeUInt32LE(0x06054b50, 0);
  fin.writeUInt16LE(entradas.length, 8);
  fin.writeUInt16LE(entradas.length, 10);
  fin.writeUInt32LE(dirCentral.length, 12);
  fin.writeUInt32LE(inicioCentral, 16);
  emitir(fin);
}

/**
 * crc, tamaño y cuerpo de una entrada. Un archivo grande no se carga: se le
 * calcula el crc por bloques y va guardado (método 0) para copiarlo después
 * también por bloques. `cuerpo: null` significa eso.
 */
function prepararCuerpo(e, esDir) {
  if (esDir) return { crc: 0, tam: 0, metodo: 0, cuerpo: Buffer.alloc(0) };
  const tam = e.datos ? e.datos.length : fs.statSync(e.ruta).size;
  if (!e.datos && tam > MAX_COMPRIMIR) {
    const { crc } = copiarPorBloques(e.ruta, () => {});
    return { crc, tam, metodo: 0, cuerpo: null };
  }
  const datos = e.datos ?? fs.readFileSync(e.ruta);
  const comprimido = zlib.deflateRawSync(datos);
  const guardar = comprimido.length >= datos.length;
  return { crc: crc32(datos), tam, metodo: guardar ? 0 : 8, cuerpo: guardar ? datos : comprimido };
}

/**
 * Emite el cuerpo de una entrada. Uno grande se lee dos veces (crc primero,
 * copia después): si el archivo cambió en el medio, el zip saldría con un crc
 * que no corresponde, y se corta acá.
 */
function emitirCuerpo(e, cuerpo, esperado, emitir) {
  if (cuerpo) { emitir(cuerpo); return; }
  const copia = copiarPorBloques(e.ruta, emitir);
  if (copia.bytes !== esperado.tam || copia.crc !== esperado.crc) {
    throw new Error(`${e.ruta} cambió mientras se empaquetaba; volvé a correr empaquetar`);
  }
}

/** Emite `ruta` por bloques y devuelve cuántos bytes emitió y su crc. */
function copiarPorBloques(ruta, emitir) {
  const buf = Buffer.allocUnsafe(BLOQUE);
  const fd = fs.openSync(ruta, 'r');
  let bytes = 0;
  let crc = 0;
  try {
    for (let n = fs.readSync(fd, buf); n > 0; n = fs.readSync(fd, buf)) {
      const b = Buffer.from(buf.subarray(0, n));
      bytes += n;
      crc = crc32(b, crc);
      emitir(b);
    }
  } finally {
    fs.closeSync(fd);
  }
  return { bytes, crc };
}

/** El zip entero en memoria. Para tests y para entradas chicas. */
export function armarZip(entradas, ahora = new Date()) {
  const partes = [];
  escribirZip(entradas, (b) => partes.push(b), ahora);
  return Buffer.concat(partes);
}

function sello(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

/** Lo que va en la raíz del paquete. Nada más: ni `.git/`, ni un `.env`, ni notas sueltas. */
const RAIZ_PERMITIDA = new Set(['README.md', 'decisiones.md', 'estado.json', '.gitignore']);

/**
 * Qué archivos del proyecto van al paquete, y cuáles de la raíz se dejan fuera.
 * Adentro de las carpetas de fase y de `entradas/` va todo lo que no empieza con
 * punto; en la raíz, sólo lo de `RAIZ_PERMITIDA`. Un symlink no se sigue.
 */
function seleccionar(dir, conEntradas) {
  const carpetas = FASES.map((f) => f.dir);
  if (conEntradas) carpetas.push('entradas');
  const symlinks = [];
  const archivos = [];
  const omitidos = [];
  for (const n of fs.readdirSync(dir).sort()) {
    const st = fs.lstatSync(path.join(dir, n));
    if (carpetas.includes(n) && st.isDirectory()) {
      archivos.push(...archivosBajo(dir, n, symlinks).filter((r) => !r.split('/').some((s) => s.startsWith('.'))));
    } else if (RAIZ_PERMITIDA.has(n) && st.isFile()) {
      archivos.push(n);
    } else if (n !== 'entradas' && n !== '.sdd.lock' && n !== '.importado.json' && !n.endsWith('.tmp')) {
      omitidos.push(st.isDirectory() ? `${n}/` : n);
    }
  }
  return { archivos, omitidos, symlinks };
}

/** Borra los zips a medio escribir que dejó una corrida matada (más de un minuto). */
function limpiarZipsHuerfanos(destino, nombre, ahoraMs) {
  const re = new RegExp(`^\\.${nombre}-[0-9-]+\\.zip\\.[0-9a-f-]{36}\\.tmp$`);
  for (const n of fs.readdirSync(destino)) {
    if (!re.test(n)) continue;
    try {
      const st = fs.lstatSync(path.join(destino, n));
      if (st.isFile() && ahoraMs - st.mtimeMs > EDAD_HUERFANO_MS) fs.rmSync(path.join(destino, n), { force: true });
    } catch { /* lo borró su dueño */ }
  }
}

/**
 * Escribe el zip a un temporal y lo publica con `link` (exclusivo y atómico):
 * nunca queda un `.zip` a medias con el nombre final. Si ya existe uno del mismo
 * segundo, prueba `-2`, `-3`…
 */
function publicar(destino, base, entradas, ahora) {
  const tmp = path.join(destino, `.${base}.zip.${randomUUID()}.tmp`);
  const fd = fs.openSync(tmp, 'wx');
  try {
    try {
      escribirZip(entradas, (b) => fs.writeSync(fd, b), ahora);
    } finally {
      fs.closeSync(fd);
    }
    for (let i = 1; i <= 20; i += 1) {
      const archivo = path.join(destino, `${base}${i === 1 ? '' : `-${i}`}.zip`);
      try {
        fs.linkSync(tmp, archivo);
        return archivo;
      } catch (e) {
        if (e.code !== 'EEXIST') throw e;
      }
    }
    throw new Error(`ya hay 20 paquetes de ${base} en ${destino}; usá --salida <dir>`);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

/**
 * Empaqueta el proyecto. Se niega si alguna fase aprobada quedó vieja: un
 * paquete presenta lo aprobado, y una fase vieja ya no es lo que se aprobó.
 * Las pendientes sí pueden ir: presentar sólo la estimación es un caso normal.
 *
 * `entradas/` queda afuera salvo `conEntradas`: el cliente ya tiene sus
 * documentos, y un zip que viaja por mail no debería llevarlos.
 */
export function empaquetar(proyecto, { conEntradas = false, salida, ahora = new Date() } = {}) {
  const destinoDir = path.resolve(salida ?? path.dirname(proyecto.dir));
  const rel = path.relative(proyecto.dir, destinoDir);
  if (rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel))) {
    throw errorDeUso(`--salida no puede estar dentro del proyecto (${destinoDir}): el paquete siguiente se incluiría a sí mismo`);
  }
  return conLock(proyecto.dir, () => {
    const p = abrirProyecto(path.dirname(proyecto.dir), proyecto.nombre);
    const calc = calcularEstado(p);
    const viejas = Object.entries(calc).filter(([, e]) => e.estado === 'vieja');
    if (viejas.length) {
      throw new Error(`no empaqueto con fases viejas: ${viejas.map(([id, e]) => `${id} (${e.motivos.join('; ')})`).join(' · ')}. Reaprobalas primero`);
    }
    actualizarPortada(p);

    const { archivos, omitidos, symlinks } = seleccionar(p.dir, conEntradas);
    if (symlinks.length) throw new Error(`hay symlinks en el proyecto y no los sigo: ${symlinks.join(', ')}`);

    // Las carpetas de fase van aunque estén vacías: la portada las enlaza, y
    // un paquete de sólo C1 tiene que mostrar que C2–C4 existen y faltan.
    const entradas = [
      ...FASES.map((f) => ({ nombre: `${p.nombre}/${f.dir}/` })),
      ...archivos.map((r) => ({ nombre: `${p.nombre}/${r}`, ruta: path.join(p.dir, r) })),
    ];
    fs.mkdirSync(destinoDir, { recursive: true });
    limpiarZipsHuerfanos(destinoDir, p.nombre, Date.now());
    const archivo = publicar(destinoDir, `${p.nombre}-${sello(ahora)}`, entradas, ahora);
    return {
      archivo,
      archivos: archivos.length,
      conEntradas,
      omitidos,
      pendientes: Object.entries(calc).filter(([, e]) => e.estado === 'pendiente').map(([id]) => id),
    };
  });
}
