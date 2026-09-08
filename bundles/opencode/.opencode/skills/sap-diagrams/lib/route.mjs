// Ruteo ortogonal automático sobre la escena ya posicionada.
//
// Tres formas de ruta, elegidas por la distancia de capas — no hay solver ni
// búsqueda: el layout en capas hace que el caso general no exista.
//
//   Δcapa = 1  → H-V-H por el canal entre las dos capas (el 90% de los casos)
//   Δcapa > 1  → desvío por una calle inferior, que por construcción no cruza nodos
//   retorno / misma capa → vertical directo si son vecinos, si no desvío
//
// Port spread: varias relaciones sobre el mismo lado de un nodo reciben puntos
// de salida distintos, ordenados por la posición del otro extremo. Sin esto las
// flechas se apilan en el mismo píxel y el diagrama miente sobre cuántas hay.
// Técnica adaptada de archify (MIT, tt-a1i) — ver NOTICE.

import {
  rect, rectRight, rectBottom, rectCenter, normalizeRoute, routeSegments,
  segmentIntersectsRect, rectsOverlap, inflate, pointAtFraction,
} from './geometry.mjs';
import { textWidth } from './text-fit.mjs';

export const ROUTING = Object.freeze({
  portSpacing: 16,
  portMargin: 12,
  laneGap: 18,
  laneOffset: 26,
  clearance: 6,
  minJog: 16,
  jogConflict: 10,
  labelFontPx: 10,
  labelPadX: 6,
  labelH: 14,
  labelClearance: 5,
  labelSlots: [0.5, 0.62, 0.38, 0.72, 0.28],
  // Desplazamiento perpendicular al tramo. Antes solo se probaban 5 posiciones
  // A LO LARGO del camino; si el corredor estaba ocupado en toda su longitud,
  // ninguna servia y la etiqueta caia al centro para que el gate la reportara.
  // Correrla al costado triplica los candidatos y convierte muchos errores
  // bloqueantes en diagramas que salen bien solos.
  labelPerp: [0, -15, 15],
});

/** Punto de salida sobre un lado del nodo, desplazado `offset` px del centro. */
function portPoint(r, side, offset) {
  const [cx, cy] = rectCenter(r);
  if (side === 'right') return [rectRight(r), cy + offset];
  if (side === 'left') return [r.x, cy + offset];
  if (side === 'top') return [cx + offset, r.y];
  return [cx + offset, rectBottom(r)];
}

/** Lados de salida/entrada según la relación de capas. */
function sidesFor(a, b) {
  if (a.layer < b.layer) return ['right', 'left'];
  if (a.layer > b.layer) return ['bottom', 'bottom'];
  return a.rect.y <= b.rect.y ? ['bottom', 'top'] : ['top', 'bottom'];
}

/**
 * Reparte los puntos de conexión de un mismo lado. El orden lo fija la posición
 * del otro extremo, de modo que dos relaciones hacia arriba y hacia abajo no se
 * crucen apenas salen del nodo.
 */
function spreadPorts(entries, r, side) {
  const span = side === 'left' || side === 'right' ? r.h : r.w;
  const usable = Math.max(0, span - ROUTING.portMargin * 2);
  const n = entries.length;
  if (n <= 1) return new Map(entries.map((e) => [e.key, 0]));
  const spacing = Math.min(ROUTING.portSpacing, usable / (n - 1));
  const sorted = [...entries].sort((a, b) => a.sortKey - b.sortKey || a.key.localeCompare(b.key));
  const start = -((n - 1) * spacing) / 2;
  return new Map(sorted.map((e, i) => [e.key, start + i * spacing]));
}

function crossesAnyNode(points, nodes, exclude) {
  const segs = routeSegments(points);
  for (const n of nodes) {
    if (exclude.has(n.id)) continue;
    for (const s of segs) if (segmentIntersectsRect(s, n.rect, ROUTING.clearance)) return true;
  }
  return false;
}

/**
 * Rutea todas las relaciones. Devuelve las rutas y cuánto espacio vertical extra
 * consumieron las calles de desvío, para que el lienzo se cierre después.
 */
// Paso 2: port spread por (nodo, lado).
function portSpread(plans) {
  const groups = new Map();
  for (const p of plans) {
    for (const [node, side, key, other] of [
      [p.a, p.fromSide, `${p.id}:from`, p.b],
      [p.b, p.toSide, `${p.id}:to`, p.a],
    ]) {
      const gk = `${node.id}|${side}`;
      if (!groups.has(gk)) groups.set(gk, { node, side, entries: [] });
      const [ocx, ocy] = rectCenter(other.rect);
      groups.get(gk).entries.push({ key, sortKey: side === 'left' || side === 'right' ? ocy : ocx });
    }
  }
  const offsets = new Map();
  for (const { node, side, entries } of groups.values()) {
    for (const [key, off] of spreadPorts(entries, node.rect, side)) offsets.set(key, off);
  }
  return offsets;
}

// Paso 3: canales. El plan es el mismo que usó el layout para abrir el hueco, así
// que el carril siempre entra donde se reservó.
function canales(plans, scene) {
  const channelX = new Map();
  for (const p of plans) {
    if (p.b.layer - p.a.layer !== 1) continue;
    const gap = scene.channelPlan?.get(p.a.layer);
    const start = scene.layerX.get(p.a.layer) + scene.layerW.get(p.a.layer);
    const offset = gap?.channels.get(p.id);
    channelX.set(p.id, offset !== undefined
      ? start + offset
      : (start + scene.layerX.get(p.b.layer)) / 2);
  }
  return channelX;
}

// Paso 4: calles de desvío.
//
// Antes todas iban por debajo. Con cuatro o cinco relaciones de salto largo la
// lámina se estiraba hacia abajo y la leyenda terminaba lejísimos del dibujo.
// Ahora cada desvío elige lado segun donde estan sus extremos, y dentro de cada
// lado el mas largo va mas lejos, para que dos calles no se crucen.
function callesDeDesvio(plans, scene) {
  const centroY = scene.content.y + scene.content.h / 2;
  const detours = plans.filter((p) => p.b.layer - p.a.layer !== 1);
  const conLado = detours.map((p) => {
    const [, ay] = rectCenter(p.a.rect);
    const [, by] = rectCenter(p.b.rect);
    const span = Math.abs(rectCenter(p.a.rect)[0] - rectCenter(p.b.rect)[0]);
    return { p, arriba: ay < centroY && by < centroY, span };
  });

  const laneY = new Map();
  const laneArriba = new Map();
  for (const arriba of [true, false]) {
    // Ascendente por longitud: el desvío más corto queda pegado al contenido y
    // el más largo, más afuera. Al revés, el largo cruzaría por debajo de los
    // tramos verticales de todos los cortos.
    const grupo = conLado.filter((d) => d.arriba === arriba).sort((a, b) => a.span - b.span);
    grupo.forEach((d, i) => {
      const offset = ROUTING.laneOffset + i * ROUTING.laneGap;
      laneY.set(d.p.id, arriba ? scene.content.y - offset : scene.content.y + scene.content.h + offset);
      laneArriba.set(d.p.id, arriba);
    });
  }
  return { laneY, laneArriba };
}

// Paso 5: puertos definitivos, corrigiendo los saltos ínfimos.
//
// Un desfase de 8px entre el puerto de salida y el de entrada genera un tramo
// vertical de 8px entre dos giros: no se lee como un quiebre, se lee como un
// defecto de render. Cuando el salto es menor al mínimo de giro, se alinean los
// dos puertos y la ruta sale recta — salvo que alinear pise el puerto de otra
// relación en ese mismo lado.
function puertosDefinitivos(plans, offsets) {
  const ports = new Map();
  for (const p of plans) {
    ports.set(p.id, {
      start: portPoint(p.a.rect, p.fromSide, offsets.get(`${p.id}:from`) || 0),
      end: portPoint(p.b.rect, p.toSide, offsets.get(`${p.id}:to`) || 0),
    });
  }
  alinearSaltosInfimos(plans, ports, detectorDeConflictos(plans, ports));
  return ports;
}

// Dos puertos que caen a menos de `jogConflict` en el mismo lado del mismo nodo
// se leen como uno. El detector responde si mover un puerto ahi pisaria a otro.
function detectorDeConflictos(plans, ports) {
  const sideKey = (nodeId, side) => `${nodeId}|${side}`;
  const occupied = new Map();
  for (const p of plans) {
    const { start, end } = ports.get(p.id);
    for (const [node, side, pt] of [[p.a, p.fromSide, start], [p.b, p.toSide, end]]) {
      const key = sideKey(node.id, side);
      if (!occupied.has(key)) occupied.set(key, []);
      occupied.get(key).push({ id: p.id, pt });
    }
  }
  return (nodeId, side, id, value, axis) => (occupied.get(sideKey(nodeId, side)) || [])
    .some((o) => o.id !== id && Math.abs(o.pt[axis] - value) < ROUTING.jogConflict);
}

// Cuando el salto entre los dos puertos es menor al minimo de giro, se alinean y
// la ruta sale recta. Se muta `ports` in situ: es el resultado del paso.
function alinearSaltosInfimos(plans, ports, conflicts) {
  const fits = (r, y) => y >= r.y + ROUTING.portMargin && y <= rectBottom(r) - ROUTING.portMargin;
  for (const p of plans) {
    if (p.b.layer - p.a.layer !== 1) continue;
    const { start, end } = ports.get(p.id);
    const jog = Math.abs(start[1] - end[1]);
    if (jog === 0 || jog >= ROUTING.minJog) continue;
    const mid = (start[1] + end[1]) / 2;
    if (!fits(p.a.rect, mid) || !fits(p.b.rect, mid)) continue;
    if (conflicts(p.a.id, p.fromSide, p.id, mid, 1) || conflicts(p.b.id, p.toSide, p.id, mid, 1)) continue;
    start[1] = mid;
    end[1] = mid;
  }
}

// Paso 6: trazado.
// La polilinea de UNA relacion. Tres formas segun la distancia entre capas:
// directa por canal, giro corto entre nodos de la misma capa, o calle de desvio.
function polilinea(p, ctx) {
  const { ports, channelX, laneY, laneArriba, offsets, nodes, scene } = ctx;
  const { start, end } = ports.get(p.id);

  if (p.b.layer - p.a.layer === 1) {
    const ch = channelX.get(p.id);
    const points = Math.abs(start[1] - end[1]) < 0.5
      ? [start, end]
      : [start, [ch, start[1]], [ch, end[1]], end];
    if (!crossesAnyNode(points, nodes, new Set([p.a.id, p.b.id]))) return points;

    // Fallback de una ruta de salto 1 que igual cruza un nodo: va por abajo, que
    // es donde siempre hay lugar (la leyenda se corre despues).
    const usadasAbajo = [...laneArriba.entries()].filter(([, a]) => !a).length;
    const lane = scene.content.y + scene.content.h + ROUTING.laneOffset + usadasAbajo * ROUTING.laneGap;
    laneY.set(p.id, lane);
    laneArriba.set(p.id, false);
    return calle(p, lane, 'bottom', offsets);
  }

  if (p.a.layer === p.b.layer && Math.abs(p.a.rect.y - p.b.rect.y) <= p.a.rect.h * 2.4) {
    const midY = (start[1] + end[1]) / 2;
    return [start, [start[0], midY], [end[0], midY], end];
  }

  return calle(
    p,
    laneY.get(p.id) ?? (scene.content.y + scene.content.h + ROUTING.laneOffset),
    laneArriba.get(p.id) ? 'top' : 'bottom',
    offsets,
  );
}

// Ruta que sale por un lado, corre por una calle horizontal y vuelve a entrar.
function calle(p, lane, lado, offsets) {
  const s = portPoint(p.a.rect, lado, offsets.get(`${p.id}:from`) || 0);
  const e = portPoint(p.b.rect, lado, offsets.get(`${p.id}:to`) || 0);
  return [s, [s[0], lane], [e[0], lane], e];
}

function trazar(plans, ports, channelX, laneY, laneArriba, offsets, scene) {
  const nodes = scene.nodes;
  const ctx = { ports, channelX, laneY, laneArriba, offsets, nodes, scene };
  const routes = plans.map((p) => ({
    id: p.id,
    index: p.index,
    from: p.edge.from,
    to: p.edge.to,
    label: p.edge.label || '',
    kind: p.edge.kind || 'data',
    style: p.edge.style || 'solid',
    bidirectional: Boolean(p.edge.bidirectional),
    fromSide: p.fromSide,
    toSide: p.toSide,
    points: normalizeRoute(polilinea(p, ctx)),
    labelAnchor: null,
    labelRect: null,
  }));

  placeLabels(routes, nodes);

  const abajo = [...laneY.entries()].filter(([id]) => !laneArriba.get(id)).map(([, y]) => y);
  const arriba = [...laneY.entries()].filter(([id]) => laneArriba.get(id)).map(([, y]) => y);
  const extraBottom = abajo.length
    ? Math.max(0, Math.max(...abajo) - (scene.content.y + scene.content.h) + ROUTING.laneGap) : 0;
  const extraTop = arriba.length
    ? Math.max(0, scene.content.y - Math.min(...arriba) + ROUTING.laneGap) : 0;
  return { routes, extraBottom, extraTop };
}

export function routeEdges(scene, edges) {
  const nodes = scene.nodes;
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const valid = (edges || []).filter((e) => byId.has(e.from) && byId.has(e.to) && e.from !== e.to);

  // Paso 1: lado de cada extremo.
  const plans = valid.map((e, i) => {
    const a = byId.get(e.from);
    const b = byId.get(e.to);
    const [fromSide, toSide] = sidesFor(a, b);
    return { edge: e, index: i, id: e.id || `e${i}`, a, b, fromSide, toSide };
  });

  const offsets = portSpread(plans);
  const channelX = canales(plans, scene);
  const { laneY, laneArriba } = callesDeDesvio(plans, scene);

  const ports = puertosDefinitivos(plans, offsets);
  return trazar(plans, ports, channelX, laneY, laneArriba, offsets, scene);
}

/** Caja que ocupa una etiqueta centrada en `anchor`. */
export function labelBoxAt(anchor, label) {
  const w = textWidth(label, ROUTING.labelFontPx) + ROUTING.labelPadX * 2;
  return rect(anchor[0] - w / 2, anchor[1] - ROUTING.labelH / 2, w, ROUTING.labelH);
}

/**
 * Coloca cada etiqueta en la primera posición libre de su ruta.
 *
 * Se prueban cinco puntos a lo largo del camino (centro primero, después hacia
 * los extremos). Libre = no pisa un nodo, no pisa otra etiqueta ya colocada y no
 * tapa una relación ajena. Si ninguna sirve, se deja el centro: el gate lo
 * reporta con la medición en vez de esconder el problema moviendo el texto a un
 * lugar arbitrario.
 */
/**
 * Orientación del tramo que contiene el punto a la fracción `t`.
 *
 * Hace falta para desplazar la etiqueta PERPENDICULAR a la línea: sobre un tramo
 * horizontal se la sube o se la baja; sobre uno vertical, se la corre al lado.
 * Desplazarla en el eje equivocado la deja encima de su propia relación.
 */
function orientacionEn(points, t) {
  const segs = routeSegments(points);
  if (!segs.length) return 'horizontal';
  const total = segs.reduce((sum, seg) => sum + Math.hypot(seg[1][0] - seg[0][0], seg[1][1] - seg[0][1]), 0);
  if (!total) return 'horizontal';
  let run = 0;
  const objetivo = Math.min(1, Math.max(0, t)) * total;
  for (const seg of segs) {
    const len = Math.hypot(seg[1][0] - seg[0][0], seg[1][1] - seg[0][1]);
    if (run + len >= objetivo) {
      return Math.abs(seg[0][1] - seg[1][1]) < 0.001 ? 'horizontal' : 'vertical';
    }
    run += len;
  }
  return 'horizontal';
}

/** Candidatos de posición: 5 puntos del camino × 3 desplazamientos perpendiculares. */
function candidatosDeEtiqueta(route) {
  const out = [];
  for (const t of ROUTING.labelSlots) {
    const base = pointAtFraction(route.points, t);
    const eje = orientacionEn(route.points, t);
    for (const perp of ROUTING.labelPerp) {
      out.push(eje === 'horizontal' ? [base[0], base[1] + perp] : [base[0] + perp, base[1]]);
    }
  }
  return out;
}

export function placeLabels(routes, nodes) {
  const placed = [];
  const ordered = [...routes]
    .filter((r) => r.label)
    .sort((a, b) => b.label.length - a.label.length || a.id.localeCompare(b.id));

  // Los segmentos de cada ruta se calculan una vez: el bucle de candidatos los
  // consulta N×M veces y volver a partir la polilinea en cada consulta no aporta.
  const segmentosDe = new Map(routes.map((r) => [r.id, routeSegments(r.points)]));

  for (const r of ordered) {
    let chosen = null;
    for (const anchor of candidatosDeEtiqueta(r)) {
      const box = labelBoxAt(anchor, r.label);
      const padded = inflate(box, ROUTING.labelClearance);
      const hitsNode = nodes.some((n) => rectsOverlap(box, n.rect, ROUTING.labelClearance));
      const hitsLabel = placed.some((b) => rectsOverlap(box, b, ROUTING.labelClearance));
      const hitsRoute = routes.some((other) => other.id !== r.id
        && segmentosDe.get(other.id).some((s) => segmentIntersectsRect(s, padded, 0)));
      if (!hitsNode && !hitsLabel && !hitsRoute) { chosen = { anchor, box }; break; }
    }
    if (!chosen) {
      const anchor = pointAtFraction(r.points, 0.5);
      chosen = { anchor, box: labelBoxAt(anchor, r.label) };
    }
    r.labelAnchor = chosen.anchor;
    r.labelRect = chosen.box;
    placed.push(chosen.box);
  }
  for (const r of routes) {
    if (!r.label) r.labelAnchor = pointAtFraction(r.points, 0.5);
  }
  return routes;
}
