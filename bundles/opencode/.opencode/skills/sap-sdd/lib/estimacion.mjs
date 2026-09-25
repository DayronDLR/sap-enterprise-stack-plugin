/**
 * El inventario de objetos de C3 y la estimación de C4, verificados (ADR-014,
 * fase P4).
 *
 * La estimación tiene que ser JUSTA: ni inflada ni corta. El sobredimensionamiento
 * casi nunca viene de un número malo, sino de cómo se arman los números:
 *
 *   - se estima lo que el diseño no pide     → cada línea apunta a un OBJ de C3
 *   - se olvida algo y se compensa con colchón → todo OBJ de C3 está estimado
 *   - el colchón va escondido en cada tarea   → tres puntos: M es lo MÁS PROBABLE,
 *                                               la incertidumbre va en O y P
 *   - un 20 % de contingencia "por las dudas" → contingencia sólo por riesgo
 *                                               identificado, con 0 < Prob < 1
 *   - el total es la suma de los pesimistas   → total = ΣE + contingencia
 *   - tareas enormes esconden holgura         → una línea con M > 40 h se parte
 *
 * EL MÉTODO. O, M y P son el P10, el P50 y el P90 de la tarea: "1 de cada 10
 * veces sale así de rápido, la mitad de las veces en menos de M, 1 de cada 10
 * tarda esto o más". M es la MEDIANA y no la moda: Swanson la supone, y con la
 * moda —que en tareas con cola hacia el lado malo queda por debajo— el total
 * salía un 3,6 % corto. Es lo que una persona puede estimar
 * de verdad; los extremos absolutos que supone PERT (y su /6) no, y con ellos la
 * media y la dispersión salían subestimadas —el "P80" medido era un P67—. Con
 * P10/P90:
 *
 *   E = 0,3·O + 0,4·M + 0,3·P        (Swanson: media menos sesgada que PERT)
 *   σ = (P − O) / 2,563               (z90 − z10)
 *
 * Las líneas que comparten algún objeto se agregan como correlacionadas (σ del
 * grupo = Σσ): las hace el mismo equipo con la misma tecnología, y si una se
 * complica, se complican juntas. Las transversales, entre sí, también. Los
 * grupos entre sí, como independientes. Sin esto, partir una tarea en cuatro
 * —o repartirla entre objetos parciales— achicaba el P80 por el mismo trabajo.
 *
 * Un riesgo es un evento que ocurre o no: aporta p·I a la media (la
 * contingencia) y p·(1−p)·I² a la varianza. El P80 lleva las dos varianzas.
 *
 * Todo lo que se puede verificar con aritmética, se verifica acá. El juicio —si M
 * es realista— es del arquitecto, y el resumen del gate le da los números.
 */
import fs from 'node:fs';
import path from 'node:path';

/** Una línea con M mayor a esto se parte: una semana es lo más grande que se estima bien. */
export const MAX_M_HORAS = 40;
/** P mayor a esto por M: la incertidumbre es una pregunta sin responder, no un rango. */
export const MAX_P_SOBRE_M = 3;
/** Un rango (P − O) menor a esta fracción de M es certeza declarada: se avisa. */
export const MIN_RANGO_SOBRE_M = 0.2;
/** Ratio contingencia / base a partir del cual se avisa (0,25 = 25 %). */
export const AVISO_CONTINGENCIA = 0.25;
/** Ratio transversales / base a partir del cual se avisa (0,35 = 35 %). */
export const AVISO_TRANSVERSAL = 0.35;
/** Probabilidad desde la cual un "riesgo" se parece más a trabajo seguro: se avisa. */
export const AVISO_PROB = 0.8;
/** Una fila que cubre esta cantidad de objetos o más ya no dice qué estima: se avisa. */
export const AVISO_OBJETOS_POR_FILA = 3;
/** Φ⁻¹(0,80). */
export const Z80 = 0.8416;
/** Φ⁻¹(0,90) − Φ⁻¹(0,10): cuántas σ separan el P10 del P90. */
export const Z10_90 = 2.5631;
const TOLERANCIA = 0.11;

/** Las clasificaciones Clean Core de un objeto. `Modificación` no se acepta. */
export const CLEAN_CORE = ['Estándar', 'Configuración', 'Extensión', 'BTP'];

const RE_CITA = /\[C1-captura\/requerimiento\.md:\d+(?:-\d+)?\]/;

/** `R-1`, `R-01` y `R-001` son el mismo riesgo. */
const riesgoNormal = (r) => `R-${Number(r.slice(2))}`;

// ── Tablas markdown ─────────────────────────────────────────────────────────

const limpiar = (c) => c.replace(/\*\*|__|`/g, '').replace(/\u0000/g, '|').trim();
const sinTildes = (t) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/**
 * El texto sin bloques de código, conservando las líneas: una tabla de ejemplo
 * dentro de un bloque no es la tabla del documento.
 */
function sinBloques(texto) {
  return texto.replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, (m) => m.replace(/[^\n]/g, ''));
}

/** Los índices de las líneas de título `##`/`###` que dicen `titulo` (con o sin número, tilde o mayúscula). */
function titulos(lineas, titulo) {
  const buscado = sinTildes(titulo);
  return lineas.flatMap((l, i) => {
    const m = /^#{2,3}\s+(?:\d+[.)]\s*)?(.+?)\s*$/.exec(l.trim());
    return m && sinTildes(m[1]) === buscado ? [i] : [];
  });
}

/**
 * La tabla debajo del título `titulo`, como `{ linea, columnas, filas:
 * [{ linea, celdas }], sueltas: [líneas], repetida }`, o null si no hay.
 * `sueltas` son filas de tabla que quedaron en la sección después de la tabla
 * (por una línea en blanco en el medio, o una segunda tabla): el documento las
 * muestra y la cuenta no las vería, así que se informan.
 */
export function tablaBajo(texto, titulo) {
  const lineas = sinBloques(texto).split(/\r?\n/);
  const [inicio, otro] = titulos(lineas, titulo);
  if (inicio === undefined) return null;
  let fin = lineas.findIndex((l, k) => k > inicio && /^#{1,3}\s/.test(l));
  if (fin === -1) fin = lineas.length;
  let i = inicio + 1;
  while (i < fin && !lineas[i].trim().startsWith('|')) i += 1;
  if (i >= fin) return null;
  const celdas = (l) => l.trim().replace(/\\\|/g, '\u0000').replace(/^\|/, '').replace(/\|$/, '').split('|').map(limpiar);
  const columnas = celdas(lineas[i]).map((c) => sinTildes(c));
  const filas = [];
  let j = i + 2;
  for (; j < fin && lineas[j].trim().startsWith('|'); j += 1) {
    const v = celdas(lineas[j]);
    filas.push({ linea: j + 1, celdas: Object.fromEntries(columnas.map((c, k) => [c, v[k] ?? ''])) });
  }
  const sueltas = [];
  for (; j < fin; j += 1) if (lineas[j].trim().startsWith('|')) sueltas.push(j + 1);
  return { linea: i + 1, columnas, filas, sueltas, repetida: otro === undefined ? null : otro + 1 };
}

/** `12`, `12.5`, `12,5`, `12 h`, `12 hs`, `30%`, `30 %` → número; lo demás → NaN. */
export function numero(texto) {
  const t = String(texto).trim().replace(/\s*h(s|oras?)?$/i, '').replace(',', '.');
  const pct = /^(\d+(?:\.\d+)?)\s*%$/.exec(t);
  if (pct) return Number(pct[1]) / 100;
  return /^\d+(\.\d+)?$/.test(t) ? Number(t) : NaN;
}

const faltanColumnas = (tabla, cols) => cols.filter((c) => !tabla.columnas.includes(c));

/** Hallazgos de estructura comunes: filas sueltas y secciones repetidas. */
function estructura(rel, t, titulo) {
  const h = [];
  if (t.repetida) h.push(`${rel}:${t.repetida} hay otra sección «${titulo}»: va una sola, y la segunda no se cuenta`);
  if (t.sueltas.length) h.push(`${rel}:${t.sueltas[0]} hay filas de tabla fuera de la tabla de «${titulo}» (¿una línea en blanco en el medio?): no se cuentan`);
  return h;
}

// ── C3: inventario ──────────────────────────────────────────────────────────

/**
 * El inventario de objetos de `diseno.md`. Devuelve `{ objetos: Map(id → fila),
 * hallazgos }`. Es la lista cerrada de lo que se construye: lo que no está acá no
 * se estima en C4.
 */
export function leerInventario(rel, texto) {
  const objetos = new Map();
  const t = tablaBajo(texto, 'Inventario de objetos');
  if (!t) return { objetos, hallazgos: [`${rel} no tiene la tabla «## Inventario de objetos»: es la lista cerrada de lo que se construye, y C4 estima contra ella`] };
  const falta = faltanColumnas(t, ['id', 'objeto', 'tipo', 'clean core', 'fuente']);
  if (falta.length) return { objetos, hallazgos: [`${rel}:${t.linea} al inventario le faltan columnas: ${falta.join(', ')}`] };
  const h = estructura(rel, t, 'Inventario de objetos');
  if (!t.filas.length) h.push(`${rel}:${t.linea} el inventario está vacío`);
  for (const { linea, celdas } of t.filas) h.push(...filaDeInventario(`${rel}:${linea}`, celdas, objetos));
  return { objetos, hallazgos: h };
}

function filaDeInventario(donde, celdas, objetos) {
  const id = celdas.id;
  if (!/^OBJ-\d+$/.test(id)) return [`${donde} «${id}» no es un ID de objeto (OBJ-NN)`];
  if (objetos.has(id)) return [`${donde} ${id} está repetido`];
  objetos.set(id, celdas);
  const h = [];
  const cc = celdas['clean core'];
  if (/modificaci/i.test(cc)) {
    h.push(`${donde} ${id} es una modificación del estándar: Clean Core no la admite. Resolvelo con ${CLEAN_CORE.slice(1).join(', ')}`);
  } else if (!CLEAN_CORE.some((c) => sinTildes(c) === sinTildes(cc))) {
    h.push(`${donde} ${id} tiene Clean Core «${cc}»: tiene que ser ${CLEAN_CORE.join(', ')}`);
  }
  if (!RE_CITA.test(celdas.fuente)) h.push(`${donde} ${id} no cita la regla que lo pide en Fuente`);
  return h;
}

// ── C4: estimación ──────────────────────────────────────────────────────────

const casi = (a, b) => Math.abs(a - b) <= TOLERANCIA;
const r1 = (x) => Math.round(x * 10) / 10;
/** Swanson: la media con O = P10 y P = P90. */
export const esperado = (o, m, p) => 0.3 * o + 0.4 * m + 0.3 * p;
/** σ con O = P10 y P = P90. */
export const desvio = (o, p) => (p - o) / Z10_90;

/** Los números de una fila: O ≤ M ≤ P, E por fórmula, M acotado. */
function revisarNumeros(donde, id, { o, m, p, e }) {
  const h = [];
  if (!(o > 0 && o <= m && m <= p)) h.push(`${donde} ${id}: tiene que valer 0 < O ≤ M ≤ P (O=${o}, M=${m}, P=${p})`);
  const esp = esperado(o, m, p);
  if (!casi(e, esp)) h.push(`${donde} ${id}: E=${e} no es 0,3·O + 0,4·M + 0,3·P = ${r1(esp)}`);
  if (m > MAX_M_HORAS) h.push(`${donde} ${id}: M=${m} h pasa de ${MAX_M_HORAS} h; partila en tareas más chicas, que es donde se esconde la holgura`);
  return h;
}

/** A qué objetos apunta una fila; `transversal` no apunta a ninguno. */
function revisarReferencias(donde, id, texto, objetos) {
  const refs = texto.split(/[,;\s]+/).filter((r) => r && !/^(y|e|and)$/i.test(r));
  const transversal = refs.some((r) => /^transversal$/i.test(r));
  if (transversal && refs.length > 1) return { refs: [], transversal: false, h: [`${donde} ${id} es transversal o apunta a objetos, no las dos cosas`] };
  if (transversal) return { refs: [], transversal: true, h: [] };
  const h = refs.length ? [] : [`${donde} ${id} no dice qué objeto estima (OBJ-NN, o «transversal»)`];
  for (const r of refs) {
    if (!objetos.has(r)) h.push(`${donde} ${id} estima ${r}, que no está en el inventario de C3: lo que no se diseñó no se estima`);
  }
  return { refs, transversal: false, h };
}

/**
 * La base de una fila: cómo salió M. Un porcentaje no es una base —es la puerta
 * de la gestión y las pruebas "como 30 % del desarrollo"—, y una sola palabra
 * genérica no dice nada que se pueda revisar.
 */
function revisarBase(donde, id, base) {
  if (!base) return { h: [`${donde} ${id} no dice en qué se basa (comparable, descomposición…)`], aviso: null };
  if (/\d\s*%/.test(base)) return { h: [`${donde} ${id}: la base «${base}» es un porcentaje; se estima por entregable concreto (casos × tiempo, objetos, ciclos)`], aviso: null };
  // Por forma, no por lista: una lista de palabras vacías ("experiencia",
  // "juicio") siempre deja afuera la siguiente ("instinto"). Una base revisable
  // cuenta algo —pasos, casos, intervalos— o nombra un comparable.
  const revisable = /\d/.test(base) || base.trim().split(/\s+/).length >= 3;
  return { h: [], aviso: revisable ? null : `${id}: la base «${base}» no dice nada revisable; contá los pasos o nombrá el comparable` };
}

/** Una fila de la estimación: sus números y lo que tiene mal. */
function filaDeEstimacion(rel, { linea, celdas }, objetos) {
  const donde = `${rel}:${linea}`;
  const id = celdas.id;
  const h = [];
  if (!/^EST-\d+$/.test(id)) h.push(`${donde} «${id}» no es un ID de estimación (EST-NN)`);
  const base = revisarBase(donde, id, celdas.base);
  h.push(...base.h);
  const ref = revisarReferencias(donde, id, celdas.obj, objetos);
  h.push(...ref.h);
  const n = Object.fromEntries(['o', 'm', 'p', 'e'].map((k) => [k, numero(celdas[k])]));
  // Con los números rotos igual se informa qué objetos cubre: si no, cada fila
  // rota traía además un "sin estimar OBJ-NN" en cascada.
  if (Object.values(n).some(Number.isNaN)) return { h: [...h, `${donde} ${id}: O, M, P y E tienen que ser horas (números)`], refs: ref.refs };
  const numeros = revisarNumeros(donde, id, n);
  h.push(...numeros);
  // Una fila con los números mal no suma en el resumen: con ella, la "suma
  // correcta" no existe y el resumen confundiría al arquitecto.
  if (numeros.length) return { h, refs: ref.refs };
  return { h, ...n, id, base: celdas.base, refs: ref.refs, transversal: ref.transversal, aviso: base.aviso };
}

/** Una fila de contingencia: riesgo del plan, 0 < Prob < 1 y Horas = Prob × Impacto. */
function filaDeContingencia(donde, celdas, riesgosDelPlan) {
  const riesgo = /R-\d+/.exec(celdas.riesgo)?.[0];
  if (!riesgo) return { h: [`${donde} la contingencia se asigna por riesgo identificado (R-NN del plan), no en general`] };
  const delPlan = new Set([...riesgosDelPlan].map(riesgoNormal));
  const h = delPlan.has(riesgoNormal(riesgo)) ? [] : [`${donde} ${riesgo} no está en la tabla «## Riesgos» de plan.md`];
  const [pr, imp, hs] = [numero(celdas.prob), numero(celdas.impacto), numero(celdas.horas)];
  if ([pr, imp, hs].some(Number.isNaN)) return { h: [...h, `${donde} ${riesgo}: Prob, Impacto y Horas tienen que ser números`] };
  // Probabilidad 1 no es un riesgo: es trabajo seguro, y va a la base como
  // tarea con su objeto. En la contingencia es un porcentaje disfrazado.
  if (pr >= 1) h.push(`${donde} ${riesgo}: probabilidad ${pr} no es un riesgo, es trabajo seguro: va a la estimación como tarea con su OBJ`);
  else if (!(pr > 0)) h.push(`${donde} ${riesgo}: la probabilidad va entre 0 y 1 (o en %)`);
  if (!casi(hs, pr * imp)) h.push(`${donde} ${riesgo}: Horas=${hs} no es Prob × Impacto = ${r1(pr * imp)}`);
  return h.length ? { h } : { h, horas: hs, varianza: pr * (1 - pr) * imp * imp };
}

/** Las filas de contingencia: una por riesgo del plan, con probabilidad × impacto. */
function contingencia(rel, texto, riesgosDelPlan) {
  const t = tablaBajo(texto, 'Contingencia');
  if (!t) return { h: [`${rel} no tiene «## Contingencia». Si no hay riesgos que la justifiquen, va la tabla con una fila «—» y 0 h`], horas: 0, varianza: 0 };
  const falta = faltanColumnas(t, ['riesgo', 'prob', 'impacto', 'horas']);
  if (falta.length) return { h: [`${rel}:${t.linea} a la contingencia le faltan columnas: ${falta.join(', ')}`], horas: 0, varianza: 0 };
  const h = estructura(rel, t, 'Contingencia');
  let horas = 0;
  let varianza = 0;
  const vistos = new Set();
  const probables = [];
  for (const { linea, celdas } of t.filas) {
    if (/^[—-]$/.test(celdas.riesgo) && numero(celdas.horas) === 0) continue;
    const riesgo = /R-\d+/.exec(celdas.riesgo)?.[0];
    // Un riesgo tiene una probabilidad y un impacto: contarlo dos veces duplica
    // su valor esperado aunque cada fila lleve otro nombre.
    if (riesgo && vistos.has(riesgoNormal(riesgo))) { h.push(`${rel}:${linea} ${riesgo} ya está en la contingencia: cada riesgo del plan se cuantifica una sola vez`); continue; }
    if (riesgo) vistos.add(riesgoNormal(riesgo));
    const f = filaDeContingencia(`${rel}:${linea}`, celdas, riesgosDelPlan);
    h.push(...f.h);
    horas += f.horas ?? 0;
    varianza += f.varianza ?? 0;
    if (f.horas !== undefined && numero(celdas.prob) >= AVISO_PROB) probables.push(riesgo);
  }
  return { h, horas, varianza, probables };
}

const FILAS_TOTALES = ['Base', 'Contingencia', 'Total', 'P80'];

/** Los totales declarados: exactamente estas cuatro filas, y cada una es la cuenta. */
function totales(rel, t, calculado) {
  const h = [];
  const nombre = (f) => sinTildes(Object.values(f.celdas)[0]);
  h.push(...estructura(rel, t, 'Totales'));
  const nombres = t.filas.map(nombre);
  for (const n of new Set(nombres.filter((x, i) => nombres.indexOf(x) !== i))) {
    h.push(`${rel}:${t.linea} la fila «${n}» está repetida en los totales: va una sola`);
  }
  for (const f of t.filas) {
    if (!FILAS_TOTALES.some((n) => sinTildes(n) === nombre(f))) {
      h.push(`${rel}:${f.linea} «${Object.values(f.celdas)[0]}» no es una fila de totales: van sólo ${FILAS_TOTALES.join(', ')}. Un total "de seguridad" no existe`);
    }
  }
  for (const [n, valor] of Object.entries(calculado)) {
    const f = t.filas.find((x) => nombre(x) === sinTildes(n));
    if (!f) { h.push(`${rel}:${t.linea} a los totales les falta la fila «${n}»`); continue; }
    const v = numero(Object.values(f.celdas)[1]);
    if (!(Math.abs(v - valor) <= Math.max(0.5, valor * 0.005))) {
      h.push(`${rel}:${f.linea} ${n} dice ${Object.values(f.celdas)[1]} y la cuenta da ${r1(valor)}`);
    }
  }
  return h;
}

/**
 * La varianza de las tareas: las del mismo objeto (o conjunto de objetos) como
 * correlacionadas —σ del grupo = Σσ—, los grupos entre sí como independientes.
 * Cada transversal es su propio grupo.
 */
/**
 * El grupo de cada fila. Union-find sobre los objetos: dos filas que comparten
 * ALGÚN objeto quedan en el mismo grupo. Con la lista exacta como clave, agregar
 * un objeto de más a una fila la desacoplaba del resto y achicaba el P80.
 * Devuelve `{ grupoDe: [raíz por fila], miembros: Map(raíz → objetos) }`.
 */
function agrupar(filas) {
  const padre = new Map();
  const raiz = (x) => {
    while (padre.get(x) !== x) { padre.set(x, padre.get(padre.get(x))); x = padre.get(x); }
    return x;
  };
  const unir = (a, b) => { padre.set(raiz(a), raiz(b)); };
  const claves = filas.map((f) => (f.transversal ? ['transversal'] : f.refs));
  for (const k of claves.flat()) if (!padre.has(k)) padre.set(k, k);
  for (const k of claves) for (const otro of k.slice(1)) unir(k[0], otro);
  const miembros = new Map();
  for (const k of padre.keys()) if (k !== 'transversal') miembros.set(raiz(k), [...(miembros.get(raiz(k)) ?? []), k]);
  return { grupoDe: claves.map((k) => raiz(k[0])), miembros };
}

/** σ² de las tareas: σ sumadas dentro de cada grupo, grupos independientes. */
export function varianzaDeTareas(filas) {
  const { grupoDe } = agrupar(filas);
  const grupos = new Map();
  filas.forEach((f, i) => grupos.set(grupoDe[i], (grupos.get(grupoDe[i]) ?? 0) + desvio(f.o, f.p)));
  return [...grupos.values()].reduce((s, sigma) => s + sigma ** 2, 0);
}

/** Grupos que encadenan 3 objetos o más: suben el P80 aunque ninguna fila cubra 3. */
function gruposGrandes(filas) {
  return [...agrupar(filas).miembros.values()].filter((m) => m.length >= AVISO_OBJETOS_POR_FILA).map((m) => m.sort());
}

/** Avisos por fila: rango, base y cantidad de objetos. */
function avisosDeFila(f) {
  const avisos = [];
  if (f.p > MAX_P_SOBRE_M * f.m) avisos.push(`${f.id}: P > ${MAX_P_SOBRE_M}×M; esa incertidumbre es una pregunta abierta, no un rango`);
  if (f.p - f.o < MIN_RANGO_SOBRE_M * f.m) avisos.push(`${f.id}: O, M y P casi iguales; ¿de verdad no hay incertidumbre, o M está inflado para cubrirla?`);
  if (f.refs.length >= AVISO_OBJETOS_POR_FILA) avisos.push(`${f.id} cubre ${f.refs.length} objetos: una fila así ya no dice qué estima; partila por objeto`);
  if (f.aviso) avisos.push(f.aviso);
  return avisos;
}

/**
 * Objetos del inventario del MISMO tipo que citan exactamente las mismas
 * reglas: ¿son uno solo partido? Que una regla pida una CDS y una app es un
 * diseño sano; que pida dos CDS idénticas en todo menos el nombre, no.
 */
function objetosGemelos(objetos) {
  const porFuente = new Map();
  for (const [id, c] of objetos) {
    const citas = [...(c.fuente.match(/\[C1-captura\/requerimiento\.md:[^\]]+\]/g) ?? [])].sort().join();
    if (citas) {
      const k = `${sinTildes(c.tipo)}|${citas}`;
      porFuente.set(k, [...(porFuente.get(k) ?? []), id]);
    }
  }
  return [...porFuente.values()].filter((ids) => ids.length > 1);
}

/** Avisos para el juicio del arquitecto: no bloquean. */
function avisosDe({ filas, base, cont, objetos }) {
  const avisos = filas.flatMap(avisosDeFila);
  if (base && cont.horas / base > AVISO_CONTINGENCIA) avisos.push(`la contingencia es el ${Math.round((100 * cont.horas) / base)} % de la base: revisá probabilidades e impactos`);
  for (const r of cont.probables ?? []) avisos.push(`${r}: con probabilidad ${AVISO_PROB} o más se parece a trabajo seguro; ¿no va como tarea?`);
  // Las transversales legítimas pueden pesar mucho en un proyecto chico: lo que
  // se avisa no es cuánto pesan, sino que alguna no esté contada por entregable.
  const transversales = filas.filter((f) => f.transversal);
  const sinContar = transversales.filter((f) => !/\d/.test(f.base));
  const dev = base - transversales.reduce((s, f) => s + f.e, 0);
  if (sinContar.length && dev > 0 && (base - dev) / dev > AVISO_TRANSVERSAL) {
    avisos.push(`las transversales son el ${Math.round((100 * (base - dev)) / dev)} % del desarrollo y ${sinContar.map((f) => f.id).join(', ')} no ${sinContar.length === 1 ? 'dice' : 'dicen'} cuántos entregables ${sinContar.length === 1 ? 'cuenta' : 'cuentan'}`);
  }
  for (const ids of objetosGemelos(objetos)) avisos.push(`${ids.join(', ')} son del mismo tipo y citan exactamente las mismas reglas: ¿son partes de un mismo objeto? El P80 los trata como independientes`);
  for (const g of gruposGrandes(filas)) avisos.push(`${g.join(', ')} quedan en un mismo grupo de riesgo porque hay filas que los comparten: el P80 los trata como una sola cosa`);
  return avisos;
}

/** Horas esperadas por objeto, de mayor a menor: donde mirar si algo está inflado. */
function porObjeto(filas) {
  const out = new Map();
  for (const f of filas) {
    for (const r of f.refs) out.set(r, (out.get(r) ?? 0) + f.e / f.refs.length);
  }
  return [...out.entries()].sort((a, b) => b[1] - a[1]).map(([obj, horas]) => ({ obj, horas: r1(horas) }));
}

/**
 * Verifica `estimacion.md` contra el inventario de C3 y los riesgos del plan.
 * Devuelve `{ hallazgos, resumen }`; el resumen son los números para el juicio
 * del arquitecto, y sus `avisos` no bloquean.
 */
export function verificarEstimacion({ rel, texto, objetos, riesgosDelPlan }) {
  const t = tablaBajo(texto, 'Estimación');
  if (!t) return { hallazgos: [`${rel} no tiene la tabla «## Estimación»`], resumen: null };
  const falta = faltanColumnas(t, ['id', 'tarea', 'obj', 'base', 'o', 'm', 'p', 'e']);
  if (falta.length) return { hallazgos: [`${rel}:${t.linea} a la estimación le faltan columnas: ${falta.join(', ')}`], resumen: null };

  const h = estructura(rel, t, 'Estimación');
  const filas = t.filas.map((f) => filaDeEstimacion(rel, f, objetos));
  filas.forEach((f) => h.push(...f.h));
  const ids = t.filas.map((f) => f.celdas.id);
  for (const id of new Set(ids.filter((x, i) => ids.indexOf(x) !== i))) h.push(`${rel} ${id} está repetido`);

  const estimados = new Set(filas.flatMap((f) => f.refs ?? []));
  const sinEstimar = [...objetos.keys()].filter((id) => !estimados.has(id));
  if (sinEstimar.length) h.push(`${rel}: sin estimar ${sinEstimar.join(', ')} del inventario de C3; lo olvidado se termina pagando con colchón`);

  const sanas = filas.filter((f) => f.e !== undefined);
  const base = sanas.reduce((s, f) => s + f.e, 0);
  const cont = contingencia(rel, texto, riesgosDelPlan);
  h.push(...cont.h);
  const total = base + cont.horas;
  const p80 = total + Z80 * Math.sqrt(varianzaDeTareas(sanas) + cont.varianza);

  // Que falte la tabla se dice siempre; las cuentas se comparan sólo con las
  // filas sanas, porque con una fila rota la "suma correcta" no existe.
  const tt = tablaBajo(texto, 'Totales');
  if (!tt) h.push(`${rel} no tiene «## Totales» (${FILAS_TOTALES.join(', ')})`);
  else if (!h.length) h.push(...totales(rel, tt, { Base: base, Contingencia: cont.horas, Total: total, P80: p80 }));

  const transversal = sanas.filter((f) => f.transversal).reduce((s, f) => s + f.e, 0);
  return {
    hallazgos: h,
    resumen: {
      base: r1(base), contingencia: r1(cont.horas), total: r1(total), p80: r1(p80),
      optimista: r1(sanas.reduce((s, f) => s + f.o, 0)),
      sumaPesimistas: r1(sanas.reduce((s, f) => s + f.p, 0)),
      transversal: r1(transversal),
      porObjeto: porObjeto(sanas),
      avisos: avisosDe({ filas: sanas, base, cont, objetos }),
    },
  };
}

/** Los `R-NN` de la tabla «## Riesgos» de plan.md: los que la contingencia puede usar. */
export function riesgosDe(texto) {
  const t = tablaBajo(texto, 'Riesgos');
  if (!t?.columnas.includes('id')) return new Set();
  return new Set(t.filas.map((f) => f.celdas.id).filter((id) => /^R-\d+$/.test(id)));
}

/** Leer un archivo si existe, o ''. */
export function leerSi(p) {
  return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '';
}

/** Ruta del motor de diagramas, hermano de este skill en todos los hosts. */
export function rutaSapdiag(aqui) {
  return path.resolve(aqui, '..', '..', 'sap-diagrams', 'bin', 'sapdiag.mjs');
}
