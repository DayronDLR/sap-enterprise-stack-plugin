// Operaciones sobre la escena completa.
//
// El ruteo puede necesitar calles POR ENCIMA del contenido, y esas calles no
// existen todavía cuando el layout coloca: el título ocupa esa franja. En vez de
// reservar espacio a ciegas —que estiraría toda lámina aunque nadie lo use— el
// ruteo declara cuánto necesitó y la escena se desplaza hacia abajo lo justo.

import { rect } from './geometry.mjs';

function mover(r, dy) {
  return r ? rect(r.x, r.y + dy, r.w, r.h) : r;
}

/**
 * Desplaza la escena y sus rutas `dy` píxeles hacia abajo.
 *
 * Toca TODO lo que tiene coordenada: si algo queda sin trasladar, se separa del
 * resto y el diagrama sale roto de una forma difícil de atribuir. Por eso la
 * lista de campos es explícita y no un recorrido genérico.
 */
export function translateScene(scene, routes, dy) {
  if (!dy) return { scene, routes };
  const desplazada = {
    ...scene,
    nodes: scene.nodes.map((n) => ({ ...n, rect: mover(n.rect, dy) })),
    zones: (scene.zones || []).map((z) => ({ ...z, rect: mover(z.rect, dy) })),
    content: mover(scene.content, dy),
  };
  if (scene.lanes) desplazada.lanes = scene.lanes.map((l) => ({ ...l, rect: mover(l.rect, dy) }));
  if (scene.systems) desplazada.systems = scene.systems.map((s) => ({ ...s, rect: mover(s.rect, dy) }));
  if (scene.footers) desplazada.footers = scene.footers.map((f) => mover(f, dy));
  if (scene.lifelineTop !== undefined) desplazada.lifelineTop = scene.lifelineTop + dy;
  if (scene.lifelineBottom !== undefined) desplazada.lifelineBottom = scene.lifelineBottom + dy;

  // Escena ya cerrada (la de `sequence`, que no pasa por un finalize aparte):
  // leyenda, título y lienzo también tienen coordenada. Hoy ningún tipo llama
  // acá después de finalizar, pero una función de traslado que deja campos
  // atrás es una trampa esperando al próximo tipo de diagrama.
  if (scene.legend) desplazada.legend = mover(scene.legend, dy);
  if (scene.title) desplazada.title = mover(scene.title, dy);
  if (scene.size) desplazada.size = { ...scene.size, height: scene.size.height + dy };

  const rutas = (routes || []).map((r) => ({
    ...r,
    points: r.points.map(([x, y]) => [x, y + dy]),
    labelAnchor: r.labelAnchor ? [r.labelAnchor[0], r.labelAnchor[1] + dy] : r.labelAnchor,
    labelRect: mover(r.labelRect, dy),
    noteRect: mover(r.noteRect, dy),
  }));
  return { scene: desplazada, routes: rutas };
}
