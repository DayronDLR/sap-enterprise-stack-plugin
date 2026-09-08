// Planificación de canales de ruteo entre capas.
//
// El hueco entre dos capas no es una constante: es la suma del espacio que
// necesitan las relaciones que lo cruzan. Cada relación se lleva un carril
// propio, y el ancho del carril lo fija su etiqueta — así una etiqueta no puede
// invadir el carril de al lado, que es el defecto que hace ilegible el 90% de
// los diagramas de arquitectura generados automáticamente.
//
// Lo calculan por igual el layout (para saber cuánto separar las capas) y el
// router (para saber dónde poner cada carril). Misma función, misma respuesta.

import { textWidth } from './text-fit.mjs';

export const CHANNEL = Object.freeze({
  margin: 26,      // aire entre el borde de una capa y el primer carril
  minSlot: 36,     // carril mínimo, aunque la relación no tenga etiqueta
  labelPad: 18,    // aire a cada lado de la etiqueta dentro de su carril
  labelFontPx: 10,
});

function slotWidth(label) {
  if (!label) return CHANNEL.minSlot;
  return Math.max(CHANNEL.minSlot, textWidth(label, CHANNEL.labelFontPx) + CHANNEL.labelPad);
}

/**
 * Devuelve, por hueco entre capas contiguas, el ancho necesario y el offset de
 * cada carril medido desde el borde derecho de la capa izquierda.
 *
 * Solo entran las relaciones de salto 1: las de salto mayor van por calle
 * inferior y no consumen canal.
 */
export function planChannels(layerOf, edges) {
  const perGap = new Map();
  (edges || []).forEach((e, i) => {
    const from = layerOf.get(e.from);
    const to = layerOf.get(e.to);
    if (from === undefined || to === undefined || to - from !== 1) return;
    if (!perGap.has(from)) perGap.set(from, []);
    perGap.get(from).push({ id: e.id || `e${i}`, slot: slotWidth(e.label) });
  });

  const plan = new Map();
  for (const [gap, list] of perGap) {
    const channels = new Map();
    let cursor = CHANNEL.margin;
    for (const entry of list) {
      channels.set(entry.id, cursor + entry.slot / 2);
      cursor += entry.slot;
    }
    plan.set(gap, { width: cursor + CHANNEL.margin, channels });
  }
  return plan;
}
