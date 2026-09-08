// Layout determinista de un landscape SAP y su ruta de transportes.
//
// La forma es fija y el orden lo declara el autor: un sistema por columna, de
// izquierda a derecha, con sus mandantes apilados adentro. No hay inferencia de
// capas porque la ruta de transportes YA es el orden — DEV, QAS, PRD — y
// dejarla al grafo permitiría dibujar un landscape donde PRD queda antes que QAS.
//
// Los mandantes son los nodos reales: un transporte va de un mandante a otro
// (DEV 100 → QAS 200), no de "sistema a sistema". Modelarlo así hace que el
// diagrama no pueda mentir sobre a qué mandante entra el TR.

import { rect, rectBottom, rectRight, boundingBox } from './geometry.mjs';
import { requiredBoxWidth, overflowsEvenShrunk } from './text-fit.mjs';
import { LAYOUT } from './layout-architecture.mjs';
import { planChannels } from './channels.mjs';

export const LANDSCAPE = Object.freeze({
  systemPadX: 18,
  systemPadTop: 46,
  systemPadBottom: 18,
  clientGapY: 16,
  clientH: 62,
  clientMinW: 150,
  clientMaxW: 210,
  systemGapX: 130,
});

function clientWidth(client) {
  return Math.min(LANDSCAPE.clientMaxW, Math.max(
    LANDSCAPE.clientMinW,
    requiredBoxWidth(client.label, 12),
    client.sublabel ? requiredBoxWidth(client.sublabel, 10) : 0,
  ));
}

// Validación del modelo: ids de mandante repetidos y transportes con extremos
// inexistentes. No toca geometría — acumula problemas, y devuelve el índice de
// mandante a sistema que la colocación necesita después.
function validarModelo(systems, transports, problems) {
  const clientOf = new Map();   // id de mandante -> indice de sistema
  const firstAt = new Map();
  for (const [si, sys] of systems.entries()) {
    for (const [ci, c] of (sys.clients || []).entries()) {
      if (firstAt.has(c.id)) {
        problems.push({
          code: 'model/duplicate-client-id',
          message: `El id de mandante "${c.id}" aparece dos veces (${firstAt.get(c.id)} y /systems/${si}/clients/${ci}).`,
          subject: { path: `/systems/${si}/clients/${ci}/id`, identity: c.id },
          evidence: { firstAt: firstAt.get(c.id) },
          supportedFixes: ['renombrar el segundo, p.ej. `qas-200`'],
        });
      } else firstAt.set(c.id, `/systems/${si}/clients/${ci}`);
      clientOf.set(c.id, si);
      if (overflowsEvenShrunk(c.label, clientWidth(c))) {
        problems.push({
          code: 'text/label-overflow',
          message: `El label "${c.label}" no entra en su caja ni encogido al mínimo legible.`,
          subject: { path: `/systems/${si}/clients/${ci}/label`, identity: c.id },
          evidence: { boxWidth: clientWidth(c) },
          supportedFixes: ['acortar el nombre del mandante', 'mover el detalle a `sublabel`'],
        });
      }
    }
  }

  validarTransportes(transports, systems, clientOf, problems);
}

// Transportes: los dos extremos tienen que ser mandantes declarados, y la ruta
// no puede ir hacia atras en el landscape.
function validarTransportes(transports, systems, clientOf, problems) {
  for (const [i, t] of transports.entries()) {
    for (const end of ['from', 'to']) {
      if (!clientOf.has(t[end])) {
        problems.push({
          code: 'model/dangling-transport',
          message: `El transporte /transports/${i} apunta al mandante "${t[end]}", que no existe.`,
          subject: { path: `/transports/${i}/${end}`, identity: t[end] },
          evidence: { known: [...clientOf.keys()] },
          supportedFixes: ['usar un id de mandante declarado en systems[].clients'],
        });
        continue;
      }
    }
    if (!clientOf.has(t.from) || !clientOf.has(t.to)) continue;
    const desde = clientOf.get(t.from);
    const hasta = clientOf.get(t.to);
    // Un transporte que retrocede en la ruta es casi siempre un error de modelo,
    // y cuando NO lo es (un retrofit) merece decirse explicito, no dibujarse
    // como si fuera un import normal.
    if (hasta <= desde) {
      problems.push({
        code: 'model/backward-transport',
        message: `El transporte /transports/${i} va de "${t.from}" a "${t.to}", que no avanza en la ruta declarada.`,
        subject: { path: `/transports/${i}`, identity: t.id || `${t.from}->${t.to}` },
        evidence: { fromSystem: systems[desde]?.sid, toSystem: systems[hasta]?.sid },
        supportedFixes: [
          'revisar el orden de `systems`: la ruta se lee de izquierda a derecha',
          'si es un retrofit deliberado, declararlo con `kind: "manual"` y etiquetarlo como tal',
        ],
      });
    }
  }

}

export function layoutLandscape(spec) {
  const problems = [];
  const systems = spec.systems || [];
  const transports = spec.transports || [];

  validarModelo(systems, transports, problems);

  // Colocación: una columna por sistema, mandantes apilados dentro.
  const placed = [];
  const placedSystems = [];
  const layerX = new Map();
  const layerW = new Map();
  let cursorX = LAYOUT.marginX;
  const topY = LAYOUT.marginY + LAYOUT.titleHeight;

  for (const [si, sys] of systems.entries()) {
    const clients = sys.clients || [];
    const anchoInterno = Math.max(...clients.map(clientWidth), LANDSCAPE.clientMinW);
    const anchoSistema = anchoInterno + LANDSCAPE.systemPadX * 2;
    const altoSistema = LANDSCAPE.systemPadTop + LANDSCAPE.systemPadBottom
      + clients.length * LANDSCAPE.clientH + (clients.length - 1) * LANDSCAPE.clientGapY;

    layerX.set(si, cursorX + LANDSCAPE.systemPadX);
    layerW.set(si, anchoInterno);

    clients.forEach((c, ci) => {
      placed.push({
        ...c,
        id: c.id,
        type: sys.type || 's4-onprem',
        layer: si,
        system: sys.id,
        role: sys.role,
        label: c.label,
        sublabel: c.sublabel || `Mandante ${c.mandt}`,
        rect: rect(
          cursorX + LANDSCAPE.systemPadX + (anchoInterno - clientWidth(c)) / 2,
          topY + LANDSCAPE.systemPadTop + ci * (LANDSCAPE.clientH + LANDSCAPE.clientGapY),
          clientWidth(c),
          LANDSCAPE.clientH,
        ),
      });
    });

    placedSystems.push({ ...sys, rect: rect(cursorX, topY, anchoSistema, altoSistema) });
    cursorX += anchoSistema + LANDSCAPE.systemGapX;
  }

  const layerOf = new Map(placed.map((c) => [c.id, c.layer]));
  const channelPlan = planChannels(layerOf, transports);

  const content = boundingBox([...placed.map((c) => c.rect), ...placedSystems.map((s) => s.rect)]);

  return {
    diagramType: 'landscape',
    meta: spec.meta,
    nodes: placed,
    systems: placedSystems,
    zones: [],
    content,
    legendRows: Math.max(1, new Set(transports.map((t) => t.kind || 'workbench')).size),
    layers: systems.map((_, i) => i),
    layerX,
    layerW,
    channelPlan,
    problems,
  };
}

export function finalizeLandscape(scene, extra = 0) {
  const extraBottom = typeof extra === 'number' ? extra : (extra.bottom || 0);
  const bottom = rectBottom(scene.content) + Math.max(0, extraBottom);
  const legend = rect(
    LAYOUT.marginX,
    bottom + LAYOUT.legendPadY,
    LAYOUT.legendW + 40,
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
