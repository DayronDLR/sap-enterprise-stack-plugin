// Layout determinista de un iFlow de SAP Integration Suite.
//
// Un iFlow es un pipeline con carriles: sistemas emisores arriba, el proceso de
// integración en el medio, el subproceso de excepción abajo, receptores al pie.
// Eso lo hace el mismo problema que una arquitectura en capas — flujo de
// izquierda a derecha, agrupación horizontal — con una diferencia visual: el
// carril **ocupa todo el ancho**, no la caja de sus miembros. Un carril que se
// encoge alrededor de sus pasos deja de leerse como un pool de BPMN.
//
// Por eso se reusa `assignLayers` y el plan de canales, y solo cambia cómo se
// dibuja la agrupación.

import { rect, rectBottom, rectRight, boundingBox } from './geometry.mjs';
import { overflowsEvenShrunk } from './text-fit.mjs';
import { assignLayers, nodeWidth, LAYOUT } from './layout-architecture.mjs';
import { planChannels } from './channels.mjs';
import { stepStyle } from './palette.mjs';

export const IFLOW = Object.freeze({
  laneLabelW: 34,       // franja vertical con el nombre del carril
  laneGap: 18,
  lanePadY: 26,
  minLaneH: 108,
});

/** El carril declarado primero se dibuja arriba: el autor define el orden de lectura. */
// Ids de paso repetidos: el segundo pisa al primero en `byId`, y los flujos que
// apuntaban al original terminan en otro lado.
function validarPasos(steps, laneById, problems) {
  const firstAt = new Map();
  for (const [i, s] of steps.entries()) {
    if (firstAt.has(s.id)) {
      problems.push({
        code: 'model/duplicate-step-id',
        message: `El id "${s.id}" aparece en /steps/${firstAt.get(s.id)} y en /steps/${i}.`,
        subject: { path: `/steps/${i}/id`, identity: s.id },
        evidence: { firstAt: firstAt.get(s.id), duplicateAt: i },
        supportedFixes: ['renombrar el segundo paso', 'fusionar los dos si son el mismo paso'],
      });
    } else firstAt.set(s.id, i);

    if (!laneById.has(s.lane)) {
      problems.push({
        code: 'model/dangling-lane',
        message: `El paso "${s.id}" declara el carril "${s.lane}", que no existe.`,
        subject: { path: `/steps/${i}/lane`, identity: s.lane },
        evidence: { known: [...laneById.keys()] },
        supportedFixes: [`usar uno de ${JSON.stringify([...laneById.keys()])}`, `agregar el carril "${s.lane}"`],
      });
    }
  }
}

// Flujos con extremos que no existen, o que salen y llegan al mismo paso.
function validarFlujos(flows, byId, problems) {
  for (const [i, f] of flows.entries()) {
    if (f.from === f.to) {
      problems.push({
        code: 'model/self-loop',
        message: `El flujo /flows/${i} sale y llega al mismo paso "${f.from}".`,
        subject: { path: `/flows/${i}`, identity: f.from },
        evidence: { from: f.from, to: f.to },
        supportedFixes: ['quitar el flujo', 'modelar el reintento con un paso propio (p.ej. un timer)'],
      });
    }
    for (const end of ['from', 'to']) {
      if (!byId.has(f[end])) {
        problems.push({
          code: 'model/dangling-flow',
          message: `El flujo /flows/${i} apunta a "${f[end]}", que no existe en steps.`,
          subject: { path: `/flows/${i}/${end}`, identity: f[end] },
          evidence: { known: [...byId.keys()] },
          supportedFixes: ['usar un id existente en steps', `agregar el paso "${f[end]}"`],
        });
      }
    }
  }
}

  // Un carril vacío es casi siempre un typo en `lane`, no una decisión.
function validarCarriles(lanes, steps, problems) {
  for (const [i, lane] of lanes.entries()) {
    if (!steps.some((s) => s.lane === lane.id)) {
      problems.push({
        code: 'model/empty-lane',
        message: `El carril "${lane.id}" no tiene ningún paso.`,
        subject: { path: `/lanes/${i}`, identity: lane.id },
        evidence: {},
        supportedFixes: ['quitar el carril', 'revisar el campo `lane` de los pasos que iban ahí'],
      });
    }
  }
}

// Validación del modelo. No toca geometría — acumula problemas.
function validarModelo({ lanes, steps, flows, byId, laneById }, problems) {
  validarPasos(steps, laneById, problems);
  validarFlujos(flows, byId, problems);
  validarCarriles(lanes, steps, problems);
}

export function layoutIntegration(spec) {
  const problems = [];
  const lanes = spec.lanes || [];
  const steps = spec.steps || [];
  const flows = spec.flows || [];
  const byId = new Map(steps.map((s) => [s.id, s]));
  const laneById = new Map(lanes.map((l) => [l.id, l]));




  validarModelo({ lanes, steps, flows, byId, laneById }, problems);

  const layerOf = assignLayers(steps, flows);
  const laneIndex = new Map(lanes.map((l, i) => [l.id, i]));

  const sized = steps.map((s) => {
    const w = nodeWidth(s);
    if (overflowsEvenShrunk(s.label, w)) {
      problems.push({
        code: 'text/label-overflow',
        message: `El label "${s.label}" no entra en su caja ni encogido al mínimo legible (${w}px).`,
        subject: { path: `/steps/${steps.indexOf(s)}/label`, identity: s.id },
        evidence: { boxWidth: w, maxBoxWidth: LAYOUT.nodeMaxW },
        supportedFixes: ['acortar el label', 'mover el detalle a `sublabel`'],
      });
    }
    return {
      ...s,
      w,
      h: LAYOUT.nodeH,
      type: s.type,
      layer: layerOf.get(s.id),
      band: laneIndex.get(s.lane) ?? 0,
      icon: stepStyle(s.type).icon,
    };
  });

  const cell = new Map();
  for (const s of sized) {
    const key = `${s.band}:${s.layer}`;
    if (!cell.has(key)) cell.set(key, []);
    cell.get(key).push(s);
  }
  for (const list of cell.values()) {
    list.sort((a, b) => (a.order ?? 50) - (b.order ?? 50) || a.id.localeCompare(b.id));
  }

  const layers = [...new Set(sized.map((s) => s.layer))].sort((a, b) => a - b);
  const layerW = new Map(layers.map((l) => [
    l, Math.max(...sized.filter((s) => s.layer === l).map((s) => s.w)),
  ]));
  const channelPlan = planChannels(layerOf, flows);
  const layerX = new Map();
  let cursorX = LAYOUT.marginX + IFLOW.laneLabelW + LAYOUT.zonePad;
  for (const [i, l] of layers.entries()) {
    layerX.set(l, cursorX);
    if (i < layers.length - 1) {
      cursorX += layerW.get(l) + Math.max(LAYOUT.gapX, channelPlan.get(l)?.width ?? 0);
    }
  }

  const laneH = lanes.map((_, b) => {
    const tallest = Math.max(1, ...layers.map((l) => (cell.get(`${b}:${l}`) || []).length));
    return Math.max(IFLOW.minLaneH, tallest * LAYOUT.nodeH + (tallest - 1) * LAYOUT.gapY + IFLOW.lanePadY * 2);
  });
  const laneY = [];
  let cursorY = LAYOUT.marginY + LAYOUT.titleHeight;
  for (const [b] of lanes.entries()) {
    laneY.push(cursorY);
    cursorY += laneH[b] + IFLOW.laneGap;
  }

  const placed = [];
  for (const s of sized) {
    const list = cell.get(`${s.band}:${s.layer}`);
    const i = list.indexOf(s);
    const stackH = list.length * LAYOUT.nodeH + (list.length - 1) * LAYOUT.gapY;
    const top = laneY[s.band] + (laneH[s.band] - stackH) / 2;
    placed.push({
      ...s,
      rect: rect(
        layerX.get(s.layer) + (layerW.get(s.layer) - s.w) / 2,
        top + i * (LAYOUT.nodeH + LAYOUT.gapY),
        s.w,
        s.h,
      ),
    });
  }

  // El ancho del carril se fija DESPUES de colocar: abarca todo el contenido,
  // no la caja de sus miembros. Un carril angosto no se lee como un pool.
  const contenido = boundingBox(placed.map((s) => s.rect));
  const laneRight = Math.max(rectRight(contenido) + LAYOUT.zonePad, LAYOUT.marginX + 420);
  const placedLanes = lanes.map((lane, b) => ({
    ...lane,
    rect: rect(LAYOUT.marginX, laneY[b], laneRight - LAYOUT.marginX, laneH[b]),
    labelW: IFLOW.laneLabelW,
  }));

  const content = boundingBox([...placed.map((s) => s.rect), ...placedLanes.map((l) => l.rect)]);

  return {
    diagramType: 'integration',
    meta: spec.meta,
    nodes: placed,
    lanes: placedLanes,
    zones: [],
    content,
    legendRows: Math.max(1, new Set(flows.map((f) => f.kind || 'data')).size),
    layers,
    layerX,
    layerW,
    channelPlan,
    problems,
  };
}

/** Cierra el lienzo una vez que el ruteo declaró cuánto espacio inferior usó. */
export function finalizeIntegration(scene, extra = 0) {
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
