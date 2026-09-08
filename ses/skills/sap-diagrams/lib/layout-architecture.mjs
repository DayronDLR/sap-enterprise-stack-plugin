// Layout determinista de un diagrama de arquitectura SAP.
//
// El punto entero del motor: el agente NUNCA escribe coordenadas. Escribe
// semántica (quién habla con quién, qué vive dentro de qué zona) y acá se
// calcula la geometría. Todo lo que sigue es aritmética pura — misma entrada,
// misma salida, sin heurísticas con estado.
//
// Modelo: capas verticales (flujo izquierda→derecha) × bandas horizontales
// (una por zona). La banda es lo que hace que los marcos BTP/on-premise nunca
// se solapen: dos zonas distintas ocupan franjas de Y disjuntas por construcción,
// así que su bounding box no puede pisarse.

import { rect, boundingBox, rectRight, rectBottom } from './geometry.mjs';
import { requiredBoxWidth, overflowsEvenShrunk } from './text-fit.mjs';
import { nodeStyle } from './palette.mjs';
import { planChannels } from './channels.mjs';

export const LAYOUT = Object.freeze({
  marginX: 40,
  marginY: 30,
  titleHeight: 52,
  nodeMinW: 120,
  nodeMaxW: 200,
  nodeH: 76,
  gapX: 120,          // separación entre capas: aloja canales de ruteo + etiquetas
  gapY: 34,           // separación vertical entre nodos de una misma banda
  bandGap: 46,        // separación entre bandas (marcos de zona)
  zonePad: 26,
  zoneLabelPad: 20,
  zoneNestStep: 16,
  legendW: 210,
  legendRowH: 20,
  legendPadY: 26,
  labelFontPx: 12,
  sublabelFontPx: 10,
});

/**
 * Techo de nodos por nivel de detalle.
 *
 * El cap del schema (24) es el del nivel más detallado. Un L0 es la lámina que
 * ve un comité: si tiene 20 cajas dejó de ser un L0 y nadie lo va a leer. El
 * nivel es una declaración del autor sobre a quién le habla el diagrama, así
 * que el motor lo hace valer en vez de dejarlo como metadato decorativo.
 */
export const LEVEL_NODE_CAP = Object.freeze({ L0: 6, L1: 12, L2: 24 });

/** Ancho de caja que exige el texto del nodo, acotado al máximo. */
export function nodeWidth(node) {
  const need = Math.max(
    LAYOUT.nodeMinW,
    requiredBoxWidth(node.label, LAYOUT.labelFontPx),
    node.sublabel ? requiredBoxWidth(node.sublabel, LAYOUT.sublabelFontPx) : 0,
  );
  return Math.min(LAYOUT.nodeMaxW, need);
}

/**
 * Capa de cada nodo. `layer` explícito manda; el resto se infiere por camino más
 * largo desde las fuentes, ignorando aristas de retorno (detectadas por DFS) para
 * que un ciclo callback→servicio no rompa el rankeo.
 */
// DFS para marcar aristas de retorno (from→to donde `to` está en la pila). Un
// ciclo no tiene capas: sin sacarlas, el longest-path no termina.
function aristasDeRetorno(ids, out) {
  const backEdges = new Set();
  const state = new Map(ids.map((id) => [id, 0])); // 0 nuevo, 1 en pila, 2 cerrado
  const visit = (id) => {
    state.set(id, 1);
    for (const next of out.get(id)) {
      if (state.get(next) === 1) backEdges.add(`${id}>${next}`);
      else if (state.get(next) === 0) visit(next);
    }
    state.set(id, 2);
  };
  for (const id of ids) if (state.get(id) === 0) visit(id);
  return backEdges;
}

// Pull-right: un nodo sin predecesores queda pegado a su primer consumidor.
//
// Sin esto, XSUAA o un servicio de Destination caen en la capa 0 solo porque
// nadie los invoca, y su única relación termina cruzando media lámina por la
// calle inferior. Pegarlo a su consumidor la convierte en un salto de una capa.
function pullRight(ids, forward, layer, explicit) {
  const hasIncoming = new Set(forward.map((e) => e.to));
  const successors = new Map(ids.map((id) => [id, []]));
  for (const e of forward) successors.get(e.from).push(e.to);
  for (const id of ids) {
    if (explicit.has(id) || hasIncoming.has(id)) continue;
    const succ = successors.get(id);
    if (!succ.length) continue;
    const target = Math.min(...succ.map((s) => layer.get(s))) - 1;
    if (target > layer.get(id)) layer.set(id, target);
  }
}

// Relajación: |V| pasadas bastan para el camino más largo en un DAG.
function relajarCapas(ids, forward, layer, explicit) {
  for (let pass = 0; pass < ids.length; pass += 1) {
    let moved = false;
    for (const e of forward) {
      if (explicit.has(e.to)) continue;
      const want = layer.get(e.from) + 1;
      if (want > layer.get(e.to)) { layer.set(e.to, want); moved = true; }
    }
    if (!moved) return;
  }
}

// Normalizar a base 0 solo cuando nadie fijó una capa a mano: un `layer`
// explícito es una restricción dura del autor y desplazarla la rompería.
function normalizarBase(ids, layer, explicit) {
  if (explicit.size !== 0) return;
  const min = Math.min(...ids.map((id) => layer.get(id)));
  if (min !== 0) for (const id of ids) layer.set(id, layer.get(id) - min);
}

export function assignLayers(nodes, edges) {
  const ids = nodes.map((n) => n.id);
  const known = new Set(ids);
  const out = new Map(ids.map((id) => [id, []]));
  const clean = (edges || []).filter((e) => known.has(e.from) && known.has(e.to) && e.from !== e.to);
  for (const e of clean) out.get(e.from).push(e.to);

  const backEdges = aristasDeRetorno(ids, out);
  const forward = clean.filter((e) => !backEdges.has(`${e.from}>${e.to}`));
  const explicit = new Map(nodes.filter((n) => Number.isInteger(n.layer)).map((n) => [n.id, n.layer]));
  const layer = new Map(ids.map((id) => [id, explicit.get(id) ?? 0]));

  relajarCapas(ids, forward, layer, explicit);
  pullRight(ids, forward, layer, explicit);
  normalizarBase(ids, layer, explicit);
  return layer;
}

/**
 * Banda de cada nodo: la cadena de zonas que lo contienen, de la más externa a
 * la más interna. Ordenar por esta clave mantiene contiguos los nodos de una
 * misma zona y, por lo tanto, hace que los marcos no se crucen.
 */
export function assignBands(nodes, zones) {
  const zoneIndex = new Map((zones || []).map((z, i) => [z.id, i]));
  const memberOf = new Map(nodes.map((n) => [n.id, []]));
  for (const z of zones || []) {
    for (const id of z.wraps) if (memberOf.has(id)) memberOf.get(id).push(z.id);
  }
  const keyFor = (id) => memberOf.get(id)
    .slice()
    .sort((a, b) => zoneIndex.get(a) - zoneIndex.get(b))
    .map((zid) => String(zoneIndex.get(zid)).padStart(2, '0'))
    .join('.');

  const keys = [...new Set(nodes.map((n) => keyFor(n.id)))].sort();
  const bandOf = new Map(nodes.map((n) => [n.id, keys.indexOf(keyFor(n.id))]));
  return { bandOf, bandCount: keys.length, memberOf };
}

/** Nivel de anidamiento de una zona: cuántas zonas la contienen estrictamente. */
function zoneNestLevel(zone, zones) {
  const mine = new Set(zone.wraps);
  let level = 0;
  for (const other of zones) {
    if (other.id === zone.id) continue;
    const theirs = new Set(other.wraps);
    if (mine.size >= theirs.size) continue;
    if ([...mine].every((id) => theirs.has(id))) level += 1;
  }
  return level;
}

/**
 * Posiciona nodos y zonas. Devuelve la escena y los problemas estructurales que
 * el layout detecta por sí mismo (referencias colgantes, texto que no entra).
 */
// Validación del modelo: ids repetidos, extremos de relación inexistentes y
// `wraps` que apuntan a nada. No toca geometría — acumula problemas.
// Un id repetido pisa al anterior en `byId`, así que las relaciones que apuntaban
// al primero terminan en el segundo y el original queda de adorno. El diagrama
// sale limpio afirmando algo que no es.
function validarIds(nodes, problems) {
  const firstAt = new Map();
  for (const [i, n] of nodes.entries()) {
    if (firstAt.has(n.id)) {
      problems.push({
        code: 'model/duplicate-node-id',
        message: `El id "${n.id}" aparece en /nodes/${firstAt.get(n.id)} y en /nodes/${i}.`,
        subject: { path: `/nodes/${i}/id`, identity: n.id },
        evidence: { firstAt: firstAt.get(n.id), duplicateAt: i },
        supportedFixes: [
          'renombrar el segundo nodo',
          'fusionar los dos si son el mismo componente',
        ],
      });
    } else firstAt.set(n.id, i);
  }
}

// Relaciones: sin auto-loops y con los dos extremos declarados.
function validarRelaciones(edges, byId, problems) {
  for (const [i, e] of edges.entries()) {
    // Un auto-loop se descartaba en el filtro del rankeo sin decir nada: el
    // spec afirmaba una interacción que el archivo entregado no contenía.
    if (e.from === e.to) {
      problems.push({
        code: 'model/self-loop',
        message: `La relación /edges/${i} sale y llega al mismo nodo "${e.from}".`,
        subject: { path: `/edges/${i}`, identity: e.from },
        evidence: { from: e.from, to: e.to },
        supportedFixes: [
          'quitar la relación si es un artefacto del spec',
          'modelar el bucle con un segundo nodo (p.ej. una cola de reintento)',
          'usar un diagrama `sequence`, donde el auto-mensaje sí se dibuja',
        ],
      });
    }
    for (const end of ['from', 'to']) {
      if (!byId.has(e[end])) {
        problems.push({
          code: 'model/dangling-edge',
          message: `La relación /edges/${i} apunta a "${e[end]}", que no existe en nodes.`,
          subject: { path: `/edges/${i}/${end}`, identity: e[end] },
          evidence: { known: [...byId.keys()] },
          supportedFixes: [`usar un id existente en nodes`, `agregar el nodo "${e[end]}"`],
        });
      }
    }
  }
}

// `wraps` que apunta a un nodo inexistente: el marco se dibuja mas chico de lo
// que el autor cree.
function validarWraps(zones, byId, problems) {
  for (const [i, z] of zones.entries()) {
    for (const id of z.wraps) {
      if (!byId.has(id)) {
        problems.push({
          code: 'model/dangling-zone-member',
          message: `La zona "${z.id}" envuelve a "${id}", que no existe en nodes.`,
          subject: { path: `/zones/${i}/wraps`, identity: id },
          evidence: { known: [...byId.keys()] },
          supportedFixes: [`quitar "${id}" de wraps`, `agregar el nodo "${id}"`],
        });
      }
    }
  }
}

function validarModelo({ nodes, zones, edges, byId }, problems) {
  validarIds(nodes, problems);
  validarRelaciones(edges, byId, problems);
  validarWraps(zones, byId, problems);
}

// Tamaño de cada nodo y control de texto. Un label que no entra ni encogido es
// un problema del modelo, no del layout: se reporta en vez de recortarse.
function medirNodos(nodes, layerOf, bandOf, problems) {
  return nodes.map((n) => {
    const w = nodeWidth(n);
    if (overflowsEvenShrunk(n.label, w)) {
      problems.push({
        code: 'text/label-overflow',
        message: `El label "${n.label}" no entra en su caja ni encogido al mínimo legible (${w}px de ancho).`,
        subject: { path: `/nodes/${nodes.indexOf(n)}/label`, identity: n.id },
        evidence: { boxWidth: w, maxBoxWidth: LAYOUT.nodeMaxW },
        supportedFixes: [
          'acortar el label conservando el nombre del producto SAP',
          'mover el detalle a `sublabel`',
        ],
      });
    }
    if (n.sublabel && overflowsEvenShrunk(n.sublabel, w)) {
      problems.push({
        code: 'text/sublabel-overflow',
        message: `El sublabel "${n.sublabel}" no entra en su caja ni encogido al mínimo legible (${w}px).`,
        subject: { path: `/nodes/${nodes.indexOf(n)}/sublabel`, identity: n.id },
        evidence: { boxWidth: w, maxBoxWidth: LAYOUT.nodeMaxW },
        supportedFixes: ['acortar el sublabel', 'quitar el sublabel si el label ya lo implica'],
      });
    }
    return { ...n, w, h: LAYOUT.nodeH, layer: layerOf.get(n.id), band: bandOf.get(n.id), icon: nodeStyle(n.type).icon };
  });
}

// Orden dentro de (banda, capa): `order` explícito, luego id, para determinismo.
function ordenarCeldas(sized) {
  const cell = new Map(); // `${band}:${layer}` -> nodos
  for (const n of sized) {
    const key = `${n.band}:${n.layer}`;
    if (!cell.has(key)) cell.set(key, []);
    cell.get(key).push(n);
  }
  for (const list of cell.values()) {
    list.sort((a, b) => (a.order ?? 50) - (b.order ?? 50) || a.id.localeCompare(b.id));
  }
  return cell;
}

// Ancho y X de cada capa. El hueco entre capas lo dicta el ruteo, no una
// constante: las etiquetas necesitan su carril y el layout tiene que reservarlo
// antes de posicionar.
function geometriaDeCapas(sized, layerOf, edges) {
  const layers = [...new Set(sized.map((n) => n.layer))].sort((a, b) => a - b);
  const layerW = new Map(layers.map((l) => [
    l, Math.max(...sized.filter((n) => n.layer === l).map((n) => n.w)),
  ]));
  // El hueco entre capas lo dicta el ruteo, no una constante: las etiquetas
  // necesitan su carril y el layout tiene que reservarlo antes de posicionar.
  const channelPlan = planChannels(layerOf, edges);
  const layerX = new Map();
  let cursorX = LAYOUT.marginX + LAYOUT.zonePad + LAYOUT.zoneNestStep;
  for (const [i, l] of layers.entries()) {
    layerX.set(l, cursorX);
    const gapNeeded = channelPlan.get(l)?.width ?? 0;
    if (i < layers.length - 1) cursorX += layerW.get(l) + Math.max(LAYOUT.gapX, gapNeeded);
  }
  return { layers, layerW, layerX, channelPlan };
}

export function layoutArchitecture(spec) {
  const problems = [];
  const nodes = spec.nodes || [];
  const zones = spec.zones || [];
  const edges = spec.edges || [];
  const byId = new Map(nodes.map((n) => [n.id, n]));

  validarModelo({ nodes, zones, edges, byId }, problems);

  const cap = LEVEL_NODE_CAP[spec.meta?.level];
  if (cap && nodes.length > cap) {
    problems.push({
      code: 'model/level-node-cap',
      message: `Un diagrama ${spec.meta.level} admite hasta ${cap} nodos y este tiene ${nodes.length}.`,
      subject: { path: '/meta/level', identity: spec.meta.level },
      evidence: { level: spec.meta.level, cap, actual: nodes.length },
      supportedFixes: [
        `quitar nodos hasta ${cap}, dejando solo lo que el nivel ${spec.meta.level} tiene que contar`,
        'partir en dos diagramas: este nivel para el panorama y un L2 para el detalle',
        `subir \`meta.level\` si el diagrama realmente es de un nivel más detallado`,
      ],
    });
  }

  const layerOf = assignLayers(nodes, edges);
  const { bandOf, bandCount } = assignBands(nodes, zones);

  const sized = medirNodos(nodes, layerOf, bandOf, problems);
  const cell = ordenarCeldas(sized);
  const { layers, layerW, layerX, channelPlan } = geometriaDeCapas(sized, layerOf, edges);

  // Altura de cada banda: la capa más poblada manda.
  const bandH = [];
  for (let b = 0; b < bandCount; b += 1) {
    const tallest = Math.max(1, ...layers.map((l) => (cell.get(`${b}:${l}`) || []).length));
    bandH.push(tallest * LAYOUT.nodeH + (tallest - 1) * LAYOUT.gapY);
  }

  // Cuánto sobresale un marco por arriba y por abajo de sus bandas extremas.
  // La separación entre bandas tiene que cubrir eso: si no, el borde de la zona
  // BTP corta por la mitad al nodo de la banda de arriba — un diagrama que
  // afirma que el usuario final corre dentro del subaccount.
  const maxLevel0 = Math.max(0, ...zones.map((z) => zoneNestLevel(z, zones)));
  const topExt = new Array(bandCount).fill(0);
  const botExt = new Array(bandCount).fill(0);
  for (const z of zones) {
    const bands = z.wraps.map((id) => bandOf.get(id)).filter((b) => b !== undefined);
    if (!bands.length) continue;
    const pad = LAYOUT.zonePad + (maxLevel0 - zoneNestLevel(z, zones)) * LAYOUT.zoneNestStep;
    const first = Math.min(...bands);
    const last = Math.max(...bands);
    topExt[first] = Math.max(topExt[first], pad + LAYOUT.zoneLabelPad);
    botExt[last] = Math.max(botExt[last], pad);
  }

  const bandY = [];
  let cursorY = LAYOUT.marginY + LAYOUT.titleHeight + (topExt[0] || 0);
  for (let b = 0; b < bandCount; b += 1) {
    bandY.push(cursorY);
    const gap = b < bandCount - 1
      ? Math.max(LAYOUT.bandGap, botExt[b] + topExt[b + 1] + LAYOUT.bandGap / 2)
      : 0;
    cursorY += bandH[b] + gap;
  }

  // Colocación final: cada celda (banda, capa) se centra verticalmente en su banda.
  const placed = [];
  for (const n of sized) {
    const list = cell.get(`${n.band}:${n.layer}`);
    const i = list.indexOf(n);
    const stackH = list.length * LAYOUT.nodeH + (list.length - 1) * LAYOUT.gapY;
    const top = bandY[n.band] + (bandH[n.band] - stackH) / 2;
    placed.push({
      ...n,
      rect: rect(
        layerX.get(n.layer) + (layerW.get(n.layer) - n.w) / 2,
        top + i * (LAYOUT.nodeH + LAYOUT.gapY),
        n.w,
        n.h,
      ),
    });
  }
  const rectOf = new Map(placed.map((n) => [n.id, n.rect]));

  // Marcos de zona: bbox de sus miembros + padding escalado por anidamiento.
  const maxLevel = maxLevel0;
  const placedZones = zones
    .map((z) => {
      const members = z.wraps.map((id) => rectOf.get(id)).filter(Boolean);
      if (!members.length) return null;
      const level = zoneNestLevel(z, zones);
      const pad = LAYOUT.zonePad + (maxLevel - level) * LAYOUT.zoneNestStep;
      const box = boundingBox(members);
      return {
        ...z,
        level,
        rect: rect(box.x - pad, box.y - pad - LAYOUT.zoneLabelPad, box.w + pad * 2, box.h + pad * 2 + LAYOUT.zoneLabelPad),
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.level - b.level); // exteriores primero: se dibujan debajo

  const content = boundingBox([...placed.map((n) => n.rect), ...placedZones.map((z) => z.rect)]);

  return {
    diagramType: 'architecture',
    meta: spec.meta,
    nodes: placed,
    zones: placedZones,
    content,
    legendRows: Math.max(1, new Set(edges.map((e) => e.kind || 'data')).size),
    layers,
    layerX,
    layerW,
    channelPlan,
    problems,
  };
}

/**
 * Cierra el lienzo una vez que el ruteo dijo cuánto espacio inferior consumieron
 * las calles de desvío. Se hace en dos tiempos a propósito: la leyenda no puede
 * quedar encima de un conector, y el ruteo no puede saber su altura antes de rutear.
 */
export function finalizeScene(scene, extra = 0) {
  const extraBottom = typeof extra === 'number' ? extra : (extra.bottom || 0);
  const bottom = rectBottom(scene.content) + Math.max(0, extraBottom);
  const legend = rect(
    LAYOUT.marginX,
    bottom + LAYOUT.legendPadY,
    LAYOUT.legendW,
    30 + scene.legendRows * LAYOUT.legendRowH,
  );
  const width = Math.max(rectRight(scene.content), rectRight(legend)) + LAYOUT.marginX;
  const height = rectBottom(legend) + LAYOUT.marginY;
  return {
    ...scene,
    legend,
    title: rect(LAYOUT.marginX, LAYOUT.marginY, width - LAYOUT.marginX * 2, LAYOUT.titleHeight),
    size: { width: Math.round(width), height: Math.round(height) },
  };
}
