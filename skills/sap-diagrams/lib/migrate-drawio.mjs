// Conversión de un .drawio heredado a una especificación .sapdiag.json.
//
// Es un PUNTO DE PARTIDA, no una traducción fiel, y el motor lo dice en voz alta.
// Un .drawio hecho a mano no tiene la semántica que el motor necesita: qué es un
// nodo y qué un marco se adivina por geometría, el tipo SAP se infiere del texto,
// y la intención (qué es una zona, qué protocolo lleva una relación) sencillamente
// no está en el archivo. Lo que sale hay que revisarlo.
//
// La alternativa —migrar a mano— es peor: reconstruir 20 nodos y 30 relaciones
// desde XML es donde se cometen los errores de transcripción que este motor
// existe para evitar.

import { NODE_STYLE } from './palette.mjs';

/** Atributos de una etiqueta XML, sin parser: el mxGraph es plano y regular. */
function atributos(tag) {
  const out = {};
  for (const m of tag.matchAll(/([\w-]+)="([^"]*)"/g)) out[m[1]] = m[2];
  return out;
}

// Tags que draw.io usa para dar formato dentro de un `value`. La lista es
// CERRADA a propósito.
//
// Antes se quitaba cualquier `<...>`, y eso no puede distinguir el `<div>` de
// draw.io del `<Pedido>` que escribió una persona. En diagramas SAP eso no es
// exótico: `<SID>`, `<mandante>`, `<PO_NUMBER>`, tipos de mensaje entre ángulos.
// Un label "Mapeo <Pedido> a IDoc" salía como "Mapeo a IDoc" en silencio, y el
// aviso mostraba el texto ya mutilado — o sea que la observabilidad lavaba la
// corrupción en vez de detectarla.
const TAGS_DRAWIO = 'div|br|span|b|i|u|font|p|strong|em|h[1-6]|ul|ol|li|table|tbody|tr|td|th|sub|sup|strike|s';
const RE_TAG_DRAWIO = new RegExp(`</?(?:${TAGS_DRAWIO})(?:\\s[^>]*)?/?>`, 'gi');

function desescapar(texto) {
  // El ORDEN importa: draw.io guarda su markup escapado (`&lt;div&gt;`), así que
  // hay que desescapar primero y recién después quitar los tags conocidos.
  const plano = String(texto || '')
    .replace(/&#10;|&#xa;/gi, ' ')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'");
  return plano
    .replace(RE_TAG_DRAWIO, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

/** id estable a partir del texto: minúsculas, guiones, sin acentos. */
export function idDesdeTexto(texto, usados) {
  const base = desescapar(texto)
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40) || 'nodo';
  let id = base;
  let n = 2;
  while (usados.has(id)) { id = `${base}-${n}`; n += 1; }
  usados.add(id);
  return id;
}

/**
 * Tipo SAP inferido del texto de la caja.
 *
 * Deliberadamente conservador: ante la duda devuelve `external`, que es visible
 * y obliga a corregir. Adivinar `cap` porque dice "servicio" produciría un
 * diagrama que afirma algo que nadie verificó.
 */
export function tipoDesdeTexto(texto) {
  const t = desescapar(texto).toLowerCase();
  const reglas = [
    [/hana|hdi/, 'hana'], [/fiori|ui5|launchpad/, 'fiori'], [/\bcap\b|cds/, 'cap'],
    [/xsuaa|authorization/, 'xsuaa'], [/\bias\b|identity/, 'ias'],
    [/cloud connector|\bscc\b/, 'cloud-connector'], [/destination/, 'destination'],
    [/connectivity/, 'connectivity'], [/event mesh|event-mesh/, 'event-mesh'],
    [/s\/?4 ?hana|\bs4\b/, 's4-onprem'], [/\becc\b|r\/3/, 'ecc'], [/\bbw\b/, 'bw'],
    [/analytics|\bsac\b/, 'sac'], [/integration suite|cpi|iflow/, 'integration-suite'],
    [/work ?zone/, 'work-zone'], [/business application studio|\bbas\b/, 'bas'],
    [/abap/, 'abap-cloud'], [/cloud foundry/, 'cf-runtime'], [/kyma/, 'kyma'],
    [/usuario|user|browser|cliente/, 'user'], [/audit/, 'audit-log'],
    [/job|scheduler/, 'job-scheduler'], [/document/, 'dms'],
  ];
  for (const [re, tipo] of reglas) if (re.test(t)) return tipo;
  return 'external';
}

/**
 * Convierte el XML de un .drawio en un spec y una lista de avisos.
 *
 * Los avisos NO son errores: son las decisiones que el conversor tuvo que tomar
 * sin información suficiente. Van al output para que el que revisa sepa
 * exactamente qué mirar, en vez de tener que auditar todo el archivo.
 */
// Avisos sobre lo que el .drawio trae y no se puede migrar tal cual: cajas sin
// texto (que suelen ser marcos o adornos) e ids repetidos.
function avisarSobreVertices(vertices, conTexto, avisos) {
  // Una caja sin texto no puede ser un nodo: no hay qué rotular. Suelen ser
  // marcos o adornos, y meterlas produciría nodos anónimos.
  const sinTexto = vertices.length - conTexto.length;
  if (sinTexto > 0) {
    avisos.push(`${sinTexto} caja(s) sin texto omitidas: suelen ser marcos o adornos. `
      + 'Si alguna era una zona, declarala a mano en `zones`.');
  }

  const idsRepetidos = new Set();
  const vistos = new Set();
  for (const v of vertices) {
    if (v.id && vistos.has(v.id)) idsRepetidos.add(v.id);
    else if (v.id) vistos.add(v.id);
  }
  if (idsRepetidos.size) {
    avisos.push(`El .drawio tiene ${idsRepetidos.size} id(s) de celda repetidos. `
      + 'Los conectores que apunten a esos ids pueden haber quedado mal dirigidos: '
      + 'revisá esas relaciones una por una.');
  }

}

// Relaciones. Una arista que apunta a una celda que no llego a ser nodo se
// descarta con aviso: dejarla produciria un spec que no valida.
function migrarAristas(aristas, porCeldaId, nodes, avisos) {
  const edges = [];
  for (const e of aristas) {
    const from = porCeldaId.get(e.source);
    const to = porCeldaId.get(e.target);
    if (!from || !to) {
      avisos.push('Un conector quedó afuera: apunta a una caja sin texto o suelta.');
      continue;
    }
    if (from === to) continue;
    const label = desescapar(e.value).slice(0, 28);
    edges.push({ from, to, ...(label ? { label } : {}) });
  }

  if (!edges.length && nodes.length > 1) {
    avisos.push('No se recuperó ninguna relación. En draw.io un conector puede estar dibujado '
      + 'sin conectar de verdad (sin source/target), y entonces no existe como dato.');
  }
  return edges;
}

export function migrarDrawio(xml, { titulo } = {}) {
  const avisos = [];
  const celdas = [...xml.matchAll(/<mxCell\b[^>]*>|<mxCell\b[^>]*\/>/g)].map((m) => m[0]);

  const vertices = [];
  const aristas = [];
  for (const celda of celdas) {
    const a = atributos(celda);
    if (a.vertex === '1') vertices.push(a);
    else if (a.edge === '1') aristas.push(a);
  }

  const conTexto = vertices.filter((v) => desescapar(v.value).length > 0);
  avisarSobreVertices(vertices, conTexto, avisos);

  const inferencias = [];
  const usados = new Set();
  const porCeldaId = new Map();
  const nodes = conTexto.map((v) => {
    const label = desescapar(v.value).slice(0, 34);
    const id = idDesdeTexto(label, usados);
    porCeldaId.set(v.id, id);
    const type = tipoDesdeTexto(v.value);
    // Se listan TODAS las inferencias, no solo las que cayeron en `external`.
    // Lo riesgoso no es lo conservador sino lo confiado: un "Gestor documental
    // legado" clasificado como `dms` sin decirlo es peor que un `external`.
    inferencias.push(`${label} → ${type}`);
    return { id, type, label };
  });

  const edges = migrarAristas(aristas, porCeldaId, nodes, avisos);

  // El techo del schema es de diseño, no técnico: 24 nodos no entran en una
  // lámina legible. Un .drawio hecho a mano suele pasarse, y decidir QUÉ se
  // recorta es una decisión de modelado que el conversor no puede tomar.
  const TECHO = 24;
  if (nodes.length > TECHO) {
    avisos.push(`Se recuperaron ${nodes.length} nodos y el schema admite ${TECHO}: el spec `
      + 'todavía NO valida. Recortá lo accesorio (leyendas, rótulos sueltos) o partilo en '
      + 'L1 + L2. Cuál se va es una decisión de modelado, no del conversor.');
  }

  avisos.push('El tipo de cada nodo, las zonas y los protocolos NO están en el .drawio: '
    + 'revisalos y completalos antes de entregar. Tipos inferidos: '
    + inferencias.join(' · '));

  const spec = {
    schema_version: 1,
    diagram_type: 'architecture',
    meta: {
      title: titulo || desescapar((xml.match(/<diagram[^>]*name="([^"]*)"/) || [])[1]) || 'Diagrama migrado',
      quality_profile: 'standard',
    },
    nodes,
    ...(edges.length ? { edges } : {}),
  };
  return { spec, avisos, tiposConocidos: Object.keys(NODE_STYLE) };
}
