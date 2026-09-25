/**
 * Del SDD aprobado a la implementación (ADR-014, fase P5).
 *
 * El SDD se arma donde corre el stack y el código se escribe después en BAS,
 * sobre el repo del cliente. Entre los dos viaja el paquete que se presentó:
 *
 *   sdd empaquetar  →  <proyecto>-AAAAMMDD-HHMMSS.zip  →  sdd importar  →  sdd traspaso
 *
 * `importar` recrea el proyecto a partir del zip, fuera de todo repo. Como las
 * aprobaciones están ancladas al contenido (sha256), un proyecto que llegó
 * intacto sigue aprobado, y uno al que se le cambió un artefacto en el camino
 * queda viejo. Es detección de accidentes, no una firma: quien edite a mano
 * también `estado.json` puede rehacer los hashes.
 *
 * `traspaso` es la puerta a `/sap-techlead`: exige C1–C4 aprobadas y al día, y
 * arma el brief con el que se planifica la implementación.
 */
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

import { FASES, validarNombre, errorDeUso, exigirFueraDeGit, fecha } from './proyecto.mjs';
import { calcularEstado, gate, estimacionDe, formaInvalida, MARCA_IMPORTADO } from './verificacion.mjs';
import { crc32 } from './paquete.mjs';
import { leerInventario, riesgosDe, tablaBajo, leerSi } from './estimacion.mjs';

/**
 * Techo de lo que un paquete puede descomprimir. Un SDD son decenas de `.md`;
 * con `entradas/` puede traer PDFs, que no comprimen. Se descomprime en memoria,
 * así que el techo es también el techo de RAM: con 2 GB, un zip de 2 MB tiraba
 * una máquina de BAS.
 */
export const MAX_DESCOMPRIMIDO = 512 * 1024 ** 2;
/** Una entrada de más de 1 MB que comprime más que esto no es un documento: es una bomba. */
export const MAX_RAZON = 100;

// ── Lectura de un zip ───────────────────────────────────────────────────────

/**
 * El fin del directorio central. No alcanza con buscar la última firma: un zip
 * puede traer una firma falsa dentro de su comentario. El verdadero es el que,
 * con su comentario, termina exactamente donde termina el archivo.
 */
function finDeDirectorio(buf) {
  const firma = Buffer.from([0x50, 0x4b, 0x05, 0x06]);
  const desde = Math.max(0, buf.length - 22 - 0xffff);
  // Puede haber más de un candidato válido: uno falso al final del comentario
  // también "termina donde termina el archivo". Gana el más externo —el de
  // índice más bajo—, cuyo comentario contiene a los otros.
  let hallado = -1;
  for (let i = buf.lastIndexOf(firma); i >= desde; i = buf.lastIndexOf(firma, i - 1)) {
    if (i + 22 <= buf.length && i + 22 + buf.readUInt16LE(i + 20) === buf.length) hallado = i;
    if (i === 0) break;
  }
  if (hallado === -1) throw new Error('no es un zip (falta el directorio central)');
  return hallado;
}

/**
 * Las entradas de un zip como `[{ nombre, esDir, datos }]`, verificadas: crc,
 * métodos soportados (guardado y deflate), techo de tamaño y de razón de
 * compresión, nombres que no escapan de la carpeta ni traen caracteres de
 * control, y ninguna colisión. Un zip que no pasa se rechaza entero: importar a
 * medias es peor que no importar.
 */
export function leerZip(buf) {
  const fin = finDeDirectorio(buf);
  const n = buf.readUInt16LE(fin + 10);
  let p = buf.readUInt32LE(fin + 16);
  const entradas = [];
  let total = 0;
  for (let i = 0; i < n; i += 1) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) throw new Error('zip corrupto: directorio central ilegible');
    const e = {
      metodo: buf.readUInt16LE(p + 10), crc: buf.readUInt32LE(p + 16),
      comprimido: buf.readUInt32LE(p + 20), tam: buf.readUInt32LE(p + 24), offset: buf.readUInt32LE(p + 42),
    };
    const largo = buf.readUInt16LE(p + 28);
    const nombre = buf.subarray(p + 46, p + 46 + largo).toString('utf8');
    p += 46 + largo + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32);

    exigirNombreSeguro(nombre);
    if (nombre.endsWith('/')) { entradas.push({ nombre, esDir: true, datos: null }); continue; }
    total += e.tam;
    if (total >= MAX_DESCOMPRIMIDO) throw new Error(`el paquete descomprime ${MAX_DESCOMPRIMIDO / 1024 ** 2} MB o más: no es un proyecto SDD`);
    entradas.push({ nombre, esDir: false, datos: descomprimir(buf, nombre, e) });
  }
  exigirSinColisiones(entradas);
  return entradas;
}

function descomprimir(buf, nombre, { metodo, crc, comprimido, tam, offset }) {
  if (metodo !== 0 && metodo !== 8) throw new Error(`${nombre}: método de compresión ${metodo} no soportado`);
  if (tam > 1024 ** 2 && tam / Math.max(comprimido, 1) > MAX_RAZON) {
    throw new Error(`${nombre}: comprime ${Math.round(tam / Math.max(comprimido, 1))} a 1; no es un documento, es una bomba`);
  }
  if (offset + 30 > buf.length) throw new Error(`${nombre}: el paquete está dañado (encabezado fuera del archivo)`);
  const inicio = offset + 30 + buf.readUInt16LE(offset + 26) + buf.readUInt16LE(offset + 28);
  const crudo = buf.subarray(inicio, inicio + comprimido);
  let datos;
  try {
    datos = metodo === 8 ? zlib.inflateRawSync(crudo, { maxOutputLength: Math.max(tam, 1) }) : crudo;
  } catch (err) {
    throw new Error(`${nombre}: el paquete está dañado (${err.message})`);
  }
  if (datos.length !== tam || crc32(datos) !== crc) throw new Error(`${nombre}: el contenido no coincide con su crc; el paquete está dañado`);
  return datos;
}

function exigirNombreSeguro(nombre) {
  const partes = nombre.replace(/\/$/, '').split('/');
  const control = /[\u0000-\u001f\u007f]/.test(nombre);
  if (!nombre || control || nombre.startsWith('/') || /^[A-Za-z]:/.test(nombre) || nombre.includes('\\')
      || partes.some((x) => x === '..' || x === '.' || x === '')) {
    throw new Error(`el paquete trae una ruta insegura: ${JSON.stringify(nombre)}`);
  }
}

/**
 * Dos entradas que caerían en el mismo archivo: repetidas, iguales salvo
 * mayúsculas o normalización Unicode (en macOS son el mismo archivo), o un
 * archivo con el nombre de un directorio de otra entrada.
 */
function exigirSinColisiones(entradas) {
  const clave = (n) => n.replace(/\/$/, '').normalize('NFC').toLowerCase();
  const vistas = new Map();
  for (const e of entradas) {
    const k = clave(e.nombre);
    const previa = vistas.get(k);
    if (previa && !(previa.esDir && e.esDir)) throw new Error(`el paquete trae dos entradas para el mismo archivo: ${JSON.stringify(previa.nombre)} y ${JSON.stringify(e.nombre)}`);
    vistas.set(k, e);
  }
  for (const e of entradas) {
    if (e.esDir) continue;
    const partes = clave(e.nombre).split('/');
    for (let i = 1; i < partes.length; i += 1) {
      const padre = vistas.get(partes.slice(0, i).join('/'));
      if (padre && !padre.esDir) throw new Error(`el paquete trae ${JSON.stringify(padre.nombre)} como archivo y como carpeta`);
    }
  }
}

// ── Importar ────────────────────────────────────────────────────────────────

/**
 * Recrea un proyecto a partir de su paquete, en `raiz` (fuera de todo repo).
 * Todas las entradas tienen que estar bajo una única carpeta, que es el nombre
 * del proyecto. Se extrae a una carpeta temporal y se publica con un rename: o
 * aparece el proyecto entero, o no aparece. Nunca pisa uno existente. Deja una
 * marca (`.importado.json`) que dice de qué paquete vino.
 */
export function importarPaquete({ zip, raiz, ahora = new Date() }) {
  const entradas = leerZip(fs.readFileSync(zip));
  const nombres = new Set(entradas.map((e) => e.nombre.split('/')[0]));
  if (nombres.size !== 1) throw new Error(`el paquete tiene que traer una sola carpeta de proyecto (trae: ${[...nombres].join(', ')})`);
  const [nombre] = nombres;
  const malo = validarNombre(nombre);
  if (malo) throw errorDeUso(`el paquete trae un ${malo}`);
  const estado = entradas.find((e) => e.nombre === `${nombre}/estado.json`);
  if (!estado) throw new Error(`el paquete no trae ${nombre}/estado.json: no es un proyecto SDD`);
  // Antes de publicar: un proyecto con estado.json roto importado igual no se
  // podría ni abrir, y "importado" le diría al arquitecto lo contrario.
  let mala;
  try { mala = formaInvalida(JSON.parse(estado.datos.toString('utf8'))); } catch { mala = 'no es JSON válido'; }
  if (mala) throw new Error(`el estado.json del paquete no sirve (${mala}): el paquete está dañado o no es un proyecto SDD`);

  const raizAbs = path.resolve(raiz);
  exigirFueraDeGit(raizAbs);
  const destino = path.join(raizAbs, nombre);
  const yaExiste = () => new Error(`ya existe ${destino}; importá en otra raíz con --raiz, o mové el proyecto existente`);
  if (fs.existsSync(destino) || isSymlink(destino)) throw yaExiste();

  fs.mkdirSync(raizAbs, { recursive: true });
  const tmp = path.join(raizAbs, `.importando-${nombre}-${randomUUID()}`);
  fs.mkdirSync(tmp);
  try {
    for (const e of entradas) {
      const rel = e.nombre.slice(nombre.length + 1).replace(/\/$/, '');
      if (!rel) continue;
      const p = path.join(tmp, rel);
      if (e.esDir) { fs.mkdirSync(p, { recursive: true }); continue; }
      fs.mkdirSync(path.dirname(p), { recursive: true });
      fs.writeFileSync(p, e.datos, { flag: 'wx' });
    }
    fs.writeFileSync(path.join(tmp, MARCA_IMPORTADO), `${JSON.stringify({ paquete: path.basename(zip), importado: fecha(ahora) }, null, 2)}\n`, { flag: 'wx' });
    try {
      fs.renameSync(tmp, destino);
    } catch (err) {
      // Otro import del mismo paquete ganó la carrera entre el chequeo y el rename.
      if (err.code === 'EEXIST' || err.code === 'ENOTEMPTY') throw yaExiste();
      throw err;
    }
  } catch (err) {
    fs.rmSync(tmp, { recursive: true, force: true });
    throw err;
  }
  return { dir: destino, nombre, archivos: entradas.filter((e) => !e.esDir).length };
}

function isSymlink(p) {
  try { return fs.lstatSync(p).isSymbolicLink(); } catch { return false; }
}

// ── Traspaso ────────────────────────────────────────────────────────────────

/**
 * El brief para `/sap-techlead`, o `{ bloqueos }` si el SDD no está listo. Listo
 * quiere decir: C1–C4 aprobadas, ninguna vieja, y el gate de C4 limpio. Un SDD
 * a medio aprobar no se implementa: se termina primero.
 */
export function traspaso(proyecto) {
  const calc = calcularEstado(proyecto);
  const bloqueos = [];
  for (const f of FASES) {
    const e = calc[f.id];
    if (e.estado === 'pendiente') bloqueos.push(`${f.id} no está aprobada`);
    if (e.estado === 'vieja') bloqueos.push(`${f.id} quedó vieja: ${e.motivos.join('; ')}`);
  }
  // El gate de C4 otra vez no es redundante: atrapa lo que cambió después de
  // aprobar y la huella no cubre.
  if (!bloqueos.length) bloqueos.push(...gate(proyecto, 'C4').map((h) => `gate C4: ${h}`));
  if (bloqueos.length) return { bloqueos };

  const { dir } = proyecto;
  const leer = (rel) => leerSi(path.join(dir, rel));
  const { objetos } = leerInventario('C3-diseno/diseno.md', leer('C3-diseno/diseno.md'));
  const { resumen } = estimacionDe(dir);
  const horas = Object.fromEntries(resumen.porObjeto.map((x) => [x.obj, x.horas]));
  const riesgos = tablaBajo(leer('C4-plan/plan.md'), 'Riesgos');
  const est = tablaBajo(leer('C4-plan/estimacion.md'), 'Estimación');
  return {
    bloqueos: [],
    brief: {
      proyecto: proyecto.nombre,
      dir,
      aprobaciones: Object.fromEntries(FASES.map((f) => [f.id, calc[f.id].aprobacion])),
      notas: FASES.map((f) => calc[f.id].nota).filter(Boolean),
      inventario: [...objetos].map(([id, c]) => ({
        id, objeto: c.objeto, tipo: c.tipo, capa: c.capa ?? '', cleanCore: c['clean core'], fuente: c.fuente, horas: horas[id] ?? 0,
      })),
      tareas: (est?.filas ?? []).map(({ celdas: c }) => ({ id: c.id, tarea: c.tarea, obj: c.obj, o: c.o, m: c.m, p: c.p, e: c.e })),
      estimacion: { base: resumen.base, contingencia: resumen.contingencia, total: resumen.total, p80: resumen.p80, transversal: resumen.transversal },
      riesgos: [...riesgosDe(leer('C4-plan/plan.md'))].map((id) => {
        const fila = riesgos?.filas.find((f) => f.celdas.id === id);
        return { id, riesgo: fila?.celdas.riesgo ?? '', mitigacion: fila?.celdas.mitigacion ?? '' };
      }),
      referencias: [
        'C1-captura/requerimiento.md', 'C1-captura/preguntas.md',
        'C2-escenarios/escenarios.md', 'C2-escenarios/casos-prueba.md', 'C3-diseno/diseno.md',
      ].filter((rel) => fs.existsSync(path.join(dir, rel))),
      orden: leer('C4-plan/handoff.md').trim(),
    },
  };
}

/** El brief en markdown: lo que `/sap-techlead` lee como su plan. */
export function briefMarkdown(b) {
  const fila = (xs) => `| ${xs.join(' | ')} |`;
  return [
    `# Traspaso a implementación — ${b.proyecto}`,
    '',
    `SDD aprobado en \`${b.dir}\`: ${Object.entries(b.aprobaciones).map(([f, a]) => `${f} ${a.dec} (${a.decide}, ${a.fecha})`).join('; ')}.`,
    ...b.notas.map((n) => `> ${n}`),
    '',
    '## Reglas',
    '',
    '- El inventario es cerrado: un objeto que no está acá no se construye sin volver a C3 (`/sap-sdd`).',
    '- La estimación es la del SDD: no se re-estima. Si una tarea se desvía, se informa contra sus horas.',
    '- Cada tarea referencia su `OBJ-NN`. La capa decide el agente. `entradas/` no se lee: la fuente es el SDD.',
    '- QA (PASO 3.5) prueba contra los escenarios y casos de C2.',
    '',
    '## Inventario',
    '',
    fila(['ID', 'Objeto', 'Tipo', 'Capa', 'Clean Core', 'Reglas', 'Horas (E)']),
    fila(['---', '---', '---', '---', '---', '---', '---']),
    ...b.inventario.map((o) => fila([o.id, o.objeto, o.tipo, o.capa, o.cleanCore, o.fuente, o.horas])),
    '',
    '## Tareas estimadas',
    '',
    fila(['ID', 'Tarea', 'OBJ', 'O', 'M', 'P', 'E']),
    fila(['---', '---', '---', '---', '---', '---', '---']),
    ...b.tareas.map((t) => fila([t.id, t.tarea, t.obj, t.o, t.m, t.p, t.e])),
    '',
    `Estimación: base ${b.estimacion.base} h + contingencia ${b.estimacion.contingencia} h = **${b.estimacion.total} h** (P80 ${b.estimacion.p80} h; transversales ${b.estimacion.transversal} h).`,
    '',
    '## Riesgos',
    '',
    ...(b.riesgos.length ? b.riesgos.map((r) => `- **${r.id}** ${r.riesgo}${r.mitigacion ? ` — mitigación: ${r.mitigacion}` : ''}`) : ['- (ninguno)']),
    '',
    '## Para consultar',
    '',
    ...b.referencias.map((r) => `- \`${path.join(b.dir, r)}\``),
    '',
    '## Orden de trabajo (C4-plan/handoff.md)',
    '',
    b.orden,
    '',
  ].join('\n');
}
