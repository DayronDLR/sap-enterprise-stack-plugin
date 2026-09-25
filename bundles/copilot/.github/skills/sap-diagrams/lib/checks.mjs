// Gate de composición: mide el diagrama ya posicionado y ruteado.
//
// Esta es la pieza que faltaba en el stack. Antes el agente escribía coordenadas
// y entregaba a ciegas; acá cada defecto que un revisor humano señalaría ("esa
// caja pisa a la otra", "la flecha atraviesa el servicio", "el label tapa la
// línea") está medido en píxeles y devuelto como una instrucción de reparación.
//
// Dos perfiles:
//   standard → bloquea lo que rompe la lectura; el resto queda como warning
//   showcase → 0 errores y 0 warnings. Es el perfil de un entregable a cliente.
//
// Conjunto de checks y contrato de perfiles adaptados de archify (MIT, tt-a1i)
// — ver NOTICE.

import {
  rectGap, rectsOverlap, rectContains, inflate,
  routeSegments, segmentIntersectsRect, properCrossing, parallelCorridor,
  borderRun, routeRhythm, isHorizontal, isVertical, bends,
} from './geometry.mjs';
import { DiagnosticBag } from './diagnostics.mjs';
import { fittedFontSize } from './text-fit.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

/**
 * Umbrales por defecto del gate de composición.
 *
 * Un proyecto puede pisarlos desde `config/stack.config.json` → `diagrams.thresholds`.
 * El caso real que lo motiva: una lámina destinada a un A3 impreso tolera más
 * ancho que una de PowerPoint, y hoy `desktopWidth` estaba clavado en el código.
 *
 * Solo se pisa lo que se declara; el resto queda en el default. Y subir un
 * umbral RELAJA el gate — no es una preferencia de estilo, es aceptar más
 * defecto visual, así que conviene dejar escrito el porqué al lado del valor.
 */
export const DEFAULT_THRESHOLDS = Object.freeze({
  nodeGap: 12,
  routeNodeClearance: 6,
  corridorDistance: 12,
  corridorOverlap: 24,
  borderTolerance: 6,
  borderMinRun: 20,
  microSegment: 8,
  interiorSegment: 16,
  labelClearance: 4,
  desktopWidth: 1400,
  minProjectedFontPx: 6,
  maxBendsPerRoute: 3,
});

/** Lee los overrides del proyecto. Un config ausente o roto no puede tumbar el render. */
function overridesDelProyecto() {
  const candidatos = [
    process.env.SAP_DIAGRAMS_CONFIG,
    path.resolve(HERE, '../../../config/stack.config.json'),
    path.resolve(process.cwd(), 'config/stack.config.json'),
  ].filter(Boolean);
  for (const archivo of candidatos) {
    try {
      if (!fs.existsSync(archivo)) continue;
      const conf = JSON.parse(fs.readFileSync(archivo, 'utf8'));
      const t = conf?.diagrams?.thresholds;
      if (t && typeof t === 'object') {
        // Solo claves conocidas y numéricas: un typo no puede desactivar un
        // check por la via de introducir un umbral que nadie lee.
        return Object.fromEntries(Object.entries(t)
          .filter(([k, v]) => k in DEFAULT_THRESHOLDS && typeof v === 'number' && Number.isFinite(v)));
      }
    } catch {
      // Config ilegible: se sigue con los defaults. Relajar el gate por un JSON
      // roto seria el peor comportamiento posible.
    }
  }
  return {};
}

export const THRESHOLDS = Object.freeze({ ...DEFAULT_THRESHOLDS, ...overridesDelProyecto() });

/** Códigos que solo bloquean en `showcase`; en `standard` son warning. */
const SHOWCASE_ONLY = new Set([
  'composition/short-interior-segment',
  'composition/proper-crossing',
  'composition/ambiguous-corridor',
  'composition/border-run',
  'composition/label-route-clearance',
  'composition/label-overlap',
  'composition/note-route-clearance',
  'composition/note-overlap',
  'composition/desktop-readability',
  'composition/route-bends',
]);

function severityFor(code, profile) {
  if (!SHOWCASE_ONLY.has(code)) return 'error';
  return profile === 'showcase' ? 'error' : 'warning';
}

/** Tamaño real al que se ve una fuente cuando el diagrama se escala a un ancho de lectura. */
export function projectedFontPx(fontPx, canvasWidth, targetWidth = THRESHOLDS.desktopWidth) {
  if (!canvasWidth) return fontPx;
  return fontPx * Math.min(1, targetWidth / canvasWidth);
}

/** ¿La zona `a` contiene al conjunto de la zona `b`? */
function zoneNested(a, b) {
  const A = new Set(a.wraps);
  const B = new Set(b.wraps);
  return [...B].every((id) => A.has(id)) || [...A].every((id) => B.has(id));
}

/**
 * Corre todos los checks sobre la escena. Devuelve el bag de diagnósticos y las
 * métricas que van al receipt (los números son la evidencia del gate; el criterio
 * de corte del loop de reparación se apoya en `summary.errors`).
 */
// Etiquetas de relación y notas, con la forma que usan los checks 6 y 7.
//
// Se miden con el mismo procedimiento porque fallan igual: son rectángulos
// opacos que pueden tapar información. Solo cambia el código del diagnóstico,
// para que el fix hable del elemento correcto.
function cajasDeTexto(routes) {
  const textBoxes = [];
  for (const r of routes) {
    if (r.labelRect && r.label) {
      textBoxes.push({ kind: 'label', noun: 'La etiqueta', route: r, text: r.label, rect: r.labelRect });
    }
    if (r.noteRect && r.note) {
      textBoxes.push({ kind: 'note', noun: 'La nota', route: r, text: r.note, rect: r.noteRect });
    }
  }
  return textBoxes;
}

// Nodos que se pisan.
function checkNodosSolapados(scene, add, metrics) {
  const nodes = scene.nodes;
  for (let i = 0; i < nodes.length; i += 1) {
    for (let j = i + 1; j < nodes.length; j += 1) {
      const gap = rectGap(nodes[i].rect, nodes[j].rect);
      metrics.minNodeGap = metrics.minNodeGap === null ? gap : Math.min(metrics.minNodeGap, gap);
      if (gap < THRESHOLDS.nodeGap) {
        add('composition/node-overlap', {
          message: `Los nodos "${nodes[i].id}" y "${nodes[j].id}" quedan a ${gap.toFixed(1)}px (mínimo ${THRESHOLDS.nodeGap}px).`,
          subject: { nodes: [nodes[i].id, nodes[j].id] },
          evidence: { gap: Number(gap.toFixed(2)), required: THRESHOLDS.nodeGap },
          supportedFixes: [
            'separar los nodos en capas distintas con `layer`',
            'acortar los labels para que las cajas sean más angostas',
          ],
        });
      }
    }
  }
}

// Zonas que se cruzan sin estar anidadas.
function checkZonasSolapadas(scene, add) {
  const zones = scene.zones || [];
  for (let i = 0; i < zones.length; i += 1) {
    for (let j = i + 1; j < zones.length; j += 1) {
      if (zoneNested(zones[i], zones[j])) continue;
      if (rectsOverlap(zones[i].rect, zones[j].rect)) {
        add('composition/zone-overlap', {
          message: `Los marcos "${zones[i].id}" y "${zones[j].id}" se solapan sin estar anidados.`,
          subject: { zones: [zones[i].id, zones[j].id] },
          evidence: { a: zones[i].rect, b: zones[j].rect },
          supportedFixes: [
            'revisar `wraps`: un nodo no puede estar en dos zonas hermanas',
            'anidar una zona dentro de la otra declarando el superconjunto de `wraps`',
          ],
        });
      }
    }
  }
}

// Nodo ajeno dentro de un marco: el diagrama dice algo falso sobre dónde corre.
function checkNodosAjenos(scene, add) {
  const nodes = scene.nodes;
  const zones = scene.zones || [];
  for (const z of zones) {
    const members = new Set(z.wraps);
    for (const n of nodes) {
      if (members.has(n.id)) continue;
      if (rectsOverlap(z.rect, n.rect) && !rectContains(z.rect, n.rect)) {
        add('composition/zone-node-straddle', {
          message: `El nodo "${n.id}" monta el borde del marco "${z.id}": no se lee si está dentro o fuera.`,
          subject: { zone: z.id, node: n.id },
          evidence: { zone: z.rect, node: n.rect },
          supportedFixes: [
            `agregar "${n.id}" a los \`wraps\` de "${z.id}" si corre ahí dentro`,
            'separar las bandas moviendo el nodo a otra capa con `layer`',
          ],
        });
      }
      if (rectContains(z.rect, n.rect)) {
        add('composition/zone-foreign-node', {
          message: `El nodo "${n.id}" cae dentro del marco "${z.id}" sin pertenecer a él.`,
          subject: { zone: z.id, node: n.id },
          evidence: { zone: z.rect, node: n.rect },
          supportedFixes: [
            `agregar "${n.id}" a los \`wraps\` de "${z.id}" si realmente corre ahí`,
            `mover "${n.id}" a otra capa fuera del marco`,
          ],
        });
      }
    }
  }
}

// Un segmento de una ruta: ortogonalidad, cruce de nodos ajenos, y corrida sobre
// el borde de un marco. Tres bucles anidados eran todo el costo de la funcion
// original; el de mas adentro sale aca.
function checkSegmento(s, i, r, { nodes, zones }, add, metrics) {
    if (!isHorizontal(s) && !isVertical(s)) {
      add('composition/non-orthogonal', {
        message: `La relación ${r.from}→${r.to} tiene un segmento diagonal (índice ${i}).`,
        subject: { relationship: r.id, segment: i },
        evidence: { segment: s },
        supportedFixes: ['reportar el defecto: el router solo debe emitir tramos H o V'],
      });
    }
    const len = Math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]);
    metrics.minSegmentPx = metrics.minSegmentPx === null ? len : Math.min(metrics.minSegmentPx, len);

    for (const n of nodes) {
      if (n.id === r.from || n.id === r.to) continue;
      if (segmentIntersectsRect(s, n.rect, THRESHOLDS.routeNodeClearance)) {
        add('composition/route-crosses-node', {
          message: `La relación ${r.from}→${r.to} atraviesa el nodo "${n.id}".`,
          subject: { relationship: r.id, node: n.id },
          evidence: { segment: s, node: n.rect },
          supportedFixes: [
            `reordenar la capa con \`order\` para que "${n.id}" no quede en el camino`,
            'mover uno de los extremos a otra capa con `layer`',
            'quitar la relación si el camino ya está implícito en otras dos',
          ],
        });
      }
    }
    for (const z of zones) {
      const run = borderRun(s, z.rect, {
        tolerance: THRESHOLDS.borderTolerance, minRun: THRESHOLDS.borderMinRun,
      });
      if (run) {
        metrics.borderRuns += 1;
        add('composition/border-run', {
          message: `La relación ${r.from}→${r.to} corre ${run.run.toFixed(0)}px pegada al borde ${run.side} de "${z.id}".`,
          subject: { relationship: r.id, zone: z.id },
          evidence: { ...run, tolerance: THRESHOLDS.borderTolerance },
          supportedFixes: [
            'cruzar el marco perpendicular al borde en vez de correr a lo largo',
            'reordenar los nodos para que la relación no bordee la zona',
          ],
        });
      }
    }
}

// Rutas: ortogonalidad, cruce de nodos, ritmo, corridas sobre borde.
function checkRutas(scene, routes, segmentsOf, add, metrics) {
  const geo = { nodes: scene.nodes, zones: scene.zones || [] };
  for (const r of routes) {
    const routeBends = bends(r.points);
    metrics.maxBends = Math.max(metrics.maxBends, routeBends);

    for (const [i, s] of segmentsOf.get(r.id).entries()) checkSegmento(s, i, r, geo, add, metrics);

    for (const issue of routeRhythm(r.points, {
      microPx: THRESHOLDS.microSegment, interiorPx: THRESHOLDS.interiorSegment,
    })) {
      const code = issue.kind === 'micro'
        ? 'composition/micro-segment'
        : 'composition/short-interior-segment';
      add(code, {
        message: `La relación ${r.from}→${r.to} tiene un tramo de ${issue.length.toFixed(1)}px (mínimo ${issue.limit}px).`,
        subject: { relationship: r.id, segment: issue.index },
        evidence: { length: Number(issue.length.toFixed(2)), limit: issue.limit },
        supportedFixes: [
          'alinear los dos extremos en la misma fila para que la ruta sea recta',
          'separar los nodos para que el giro tenga espacio',
        ],
      });
    }

    if (routeBends > THRESHOLDS.maxBendsPerRoute) {
      add('composition/route-bends', {
        message: `La relación ${r.from}→${r.to} tiene ${routeBends} quiebres (sugerido ${THRESHOLDS.maxBendsPerRoute}).`,
        subject: { relationship: r.id },
        evidence: { bends: routeBends, limit: THRESHOLDS.maxBendsPerRoute },
        supportedFixes: ['acercar los extremos en capas contiguas', 'quitar la relación si es redundante'],
      });
    }
  }
}

// Un par de segmentos de dos relaciones sin parentesco: cruce propio y corredor
// ambiguo. Cuatro bucles anidados eran todo el costo; los dos de adentro salen.
function checkParDeSegmentos(sa, sb, a, b, related, add, metrics) {
    const crossing = related ? null : properCrossing(sa, sb);
    if (crossing) {
      metrics.properCrossings += 1;
      add('composition/proper-crossing', {
        message: `Las relaciones ${a.from}→${a.to} y ${b.from}→${b.to} se cruzan.`,
        subject: { relationships: [a.id, b.id] },
        evidence: { at: crossing },
        supportedFixes: [
          'reordenar los nodos de la capa con `order` para desenredar el cruce',
          'quitar una de las dos relaciones si la información ya está en la otra',
        ],
      });
    }
    const corridor = parallelCorridor(sa, sb, {
      maxDistance: THRESHOLDS.corridorDistance, minOverlap: THRESHOLDS.corridorOverlap,
    });
    if (corridor && !related) {
      metrics.ambiguousCorridors += 1;
      add('composition/ambiguous-corridor', {
        message: `Las relaciones ${a.from}→${a.to} y ${b.from}→${b.to} corren a ${corridor.distance.toFixed(1)}px durante ${corridor.overlap.toFixed(0)}px: se leen como una sola.`,
        subject: { relationships: [a.id, b.id] },
        evidence: corridor,
        supportedFixes: [
          'separar los nodos para que los canales de ruteo se abran',
          'quitar una de las relaciones si son el mismo hecho contado dos veces',
        ],
      });
    }
}

// Cruces propios y corredores ambiguos entre relaciones sin parentesco.
function checkCrucesEntreRutas(routes, segmentsOf, add, metrics) {
  for (let i = 0; i < routes.length; i += 1) {
    for (let j = i + 1; j < routes.length; j += 1) {
      const a = routes[i]; const b = routes[j];
      const related = a.from === b.from || a.from === b.to || a.to === b.from || a.to === b.to;
      for (const sa of segmentsOf.get(a.id)) {
        for (const sb of segmentsOf.get(b.id)) {
          checkParDeSegmentos(sa, sb, a, b, related, add, metrics);
        }
      }
    }
  }
}

// Cajas de texto — etiquetas de relación y notas — contra nodos, contra otras
// cajas y contra rutas ajenas.
function checkCajasDeTexto(scene, routes, segmentsOf, textBoxes, add, metrics) {
  const nodes = scene.nodes;

  const TEXT_FIXES = {
    label: [
      'acortar la etiqueta conservando protocolo y dirección',
      'separar los nodos para que el tramo etiquetado sea más largo',
    ],
    note: [
      'acortar la nota o moverla al cuerpo del documento',
      'quitar la nota si el mensaje ya dice lo mismo',
    ],
  };

  for (const box of textBoxes) {
    checkUnaCaja(box, { nodes, routes, segmentsOf, textBoxes, TEXT_FIXES }, add, metrics);
  }

  checkCarrilesDeIflow(scene, routes, segmentsOf, add, metrics);
}

// Una caja de texto contra nodos, contra las otras cajas y contra rutas ajenas.
function checkUnaCaja(box, ctx, add, metrics) {
  const { nodes, routes, segmentsOf, textBoxes, TEXT_FIXES } = ctx;
const r = box.route;
for (const n of nodes) {
  if (rectsOverlap(box.rect, n.rect, THRESHOLDS.labelClearance)) {
    add(`composition/${box.kind}-node-overlap`, {
      message: `${box.noun} "${box.text}" (${r.from}→${r.to}) se monta sobre el nodo "${n.id}".`,
      subject: { relationship: r.id, node: n.id, kind: box.kind },
      evidence: { box: box.rect, node: n.rect },
      supportedFixes: TEXT_FIXES[box.kind],
    });
  }
}
for (const other of textBoxes) {
  if (other === box) continue;
  if (`${other.kind}:${other.route.id}` <= `${box.kind}:${r.id}`) continue;
  if (rectsOverlap(box.rect, other.rect, THRESHOLDS.labelClearance)) {
    metrics.labelClearanceIssues += 1;
    add(`composition/${box.kind}-overlap`, {
      message: `"${box.text}" y "${other.text}" se solapan.`,
      subject: { relationships: [r.id, other.route.id], kinds: [box.kind, other.kind] },
      evidence: { a: box.rect, b: other.rect },
      supportedFixes: TEXT_FIXES[box.kind],
    });
  }
}
for (const other of routes) {
  if (other.id === r.id) continue;
  const hit = segmentsOf.get(other.id)
    .some((seg) => segmentIntersectsRect(seg, inflate(box.rect, THRESHOLDS.labelClearance), 0));
  if (hit) {
    metrics.labelClearanceIssues += 1;
    add(`composition/${box.kind}-route-clearance`, {
      message: `${box.noun} "${box.text}" tapa la relación ${other.from}→${other.to}.`,
      subject: { relationship: r.id, obstructs: other.id, kind: box.kind },
      evidence: { box: box.rect },
      supportedFixes: [
        ...TEXT_FIXES[box.kind],
        'separar las capas para que los canales de ruteo no compartan corredor',
      ],
    });
  }
}
}

// Carriles de iFlow: un conector que corre a lo largo del borde de un pool no se
// lee como perteneciente a ninguno de los dos. Cruzarlo perpendicular es normal y
// no se marca — `borderRun` ya distingue.
function checkCarrilesDeIflow(scene, routes, segmentsOf, add, metrics) {
  for (const lane of scene.lanes || []) {
    for (const r of routes) {
      for (const seg of segmentsOf.get(r.id)) {
        const run = borderRun(seg, lane.rect, {
          tolerance: THRESHOLDS.borderTolerance, minRun: THRESHOLDS.borderMinRun,
        });
        if (run) {
          metrics.borderRuns += 1;
          add('composition/border-run', {
            message: `El flujo ${r.from}→${r.to} corre ${run.run.toFixed(0)}px pegado al borde ${run.side} del carril "${lane.id}".`,
            subject: { relationship: r.id, lane: lane.id },
            evidence: { ...run, tolerance: THRESHOLDS.borderTolerance },
            supportedFixes: [
              'cruzar el carril perpendicular al borde en vez de correr a lo largo',
              'mover el paso a otra capa con `layer` para que el flujo no bordee el pool',
            ],
          });
        }
      }
    }
  }
}

// La leyenda no puede pisar nodos ni rutas: es un elemento opaco encima del
// diagrama.
function checkLeyenda(scene, routes, segmentsOf, add) {
  if (!scene.legend) return;
  const nodes = scene.nodes;
  for (const n of nodes) {
    if (rectsOverlap(scene.legend, n.rect)) {
      add('composition/legend-clearance', {
        message: `El nodo "${n.id}" invade la caja de leyenda.`,
        subject: { node: n.id },
        evidence: { legend: scene.legend, node: n.rect },
        supportedFixes: ['reportar el defecto: la leyenda se coloca bajo el contenido'],
      });
    }
  }
  for (const r of routes) {
    const hit = segmentsOf.get(r.id).some((s) => segmentIntersectsRect(s, scene.legend, 0));
    if (hit) {
      add('composition/legend-clearance', {
        message: `La relación ${r.from}→${r.to} entra en la caja de leyenda.`,
        subject: { relationship: r.id },
        evidence: { legend: scene.legend },
        supportedFixes: ['reportar el defecto: las calles de desvío deben quedar sobre la leyenda'],
      });
    }
  }
}

// Todo dentro del lienzo. Lo que se sale se recorta al exportar y nadie se
// entera: el receipt sale limpio y el PNG llega cortado al Word.
function checkLienzo(scene, routes, textBoxes, add) {
  const nodes = scene.nodes;
  const canvas = { x: 0, y: 0, w: scene.size.width, h: scene.size.height };
for (const n of nodes) {
  if (!rectContains(canvas, n.rect)) {
    add('composition/viewbox-containment', {
      message: `El nodo "${n.id}" queda fuera del lienzo ${canvas.w}×${canvas.h}.`,
      subject: { node: n.id },
      evidence: { node: n.rect, canvas },
      supportedFixes: ['reportar el defecto: el lienzo se calcula desde el contenido'],
    });
  }
}
// Una etiqueta o una nota que se sale del lienzo se recorta al exportar y
// nadie se entera: el receipt sale limpio y el PNG llega cortado al Word.
for (const box of textBoxes) {
  if (!rectContains(canvas, box.rect)) {
    add('composition/viewbox-containment', {
      message: `${box.noun} "${box.text}" se sale del lienzo ${canvas.w}×${canvas.h}.`,
      subject: { relationship: box.route.id, kind: box.kind },
      evidence: { box: box.rect, canvas },
      supportedFixes: [
        box.kind === 'note' ? 'acortar la nota' : 'acortar la etiqueta',
        'separar los participantes o las capas para que el texto tenga lugar',
      ],
    });
  }
}
for (const r of routes) {
  for (const [x, y] of r.points) {
    if (x < 0 || y < 0 || x > canvas.w || y > canvas.h) {
      add('composition/viewbox-containment', {
        message: `La relación ${r.from}→${r.to} sale del lienzo en (${x.toFixed(0)}, ${y.toFixed(0)}).`,
        subject: { relationship: r.id },
        evidence: { point: [x, y], canvas },
        supportedFixes: ['reportar el defecto: el lienzo se calcula desde el contenido'],
      });
      break;
    }
  }
}
}

// Leyenda limpia y todo dentro del lienzo.
function checkLeyendaYLienzo(scene, routes, segmentsOf, textBoxes, add) {
  checkLeyenda(scene, routes, segmentsOf, add);
  checkLienzo(scene, routes, textBoxes, add);
}

// Legibilidad proyectada: el diagrama se lee a ~1400px de ancho, no al 100%.
function checkLegibilidad(scene, add, metrics) {
  const nodes = scene.nodes;
  for (const n of nodes) {
    const source = fittedFontSize(n.label, n.rect.w, 12);
    const projected = projectedFontPx(source, scene.size.width);
    metrics.minProjectedFontPx = metrics.minProjectedFontPx === null
      ? projected : Math.min(metrics.minProjectedFontPx, projected);
    if (projected < THRESHOLDS.minProjectedFontPx) {
      add('composition/desktop-readability', {
        message: `El label de "${n.id}" se ve a ${projected.toFixed(1)}px cuando el diagrama se escala a ${THRESHOLDS.desktopWidth}px (mínimo ${THRESHOLDS.minProjectedFontPx}px).`,
        subject: { node: n.id },
        evidence: { sourceFontPx: source, projectedFontPx: Number(projected.toFixed(2)), canvasWidth: scene.size.width },
        supportedFixes: [
          'reducir la cantidad de capas o de nodos: el lienzo es demasiado ancho',
          'partir el diagrama en L1 general + L2 de detalle',
        ],
      });
    }
  }
}

export function runChecks(scene, routes, { profile = 'standard' } = {}) {
  const bag = new DiagnosticBag();
  const add = (code, raw) => bag.add({ ...raw, code, severity: severityFor(code, profile) });
  const nodes = scene.nodes;
  const zones = scene.zones || [];
  const metrics = {
    profile,
    // Los umbrales EFECTIVOS van al receipt. Sin esto, un receipt `showcase` de
    // un proyecto que relajó `config/stack.config.json` es indistinguible de uno
    // estricto — y el ADR-010 promete que el receipt prueba qué pasó el gate.
    // Solo se registran los que difieren del default, para no inflar la salida.
    thresholdOverrides: Object.fromEntries(
      Object.entries(THRESHOLDS).filter(([k, v]) => DEFAULT_THRESHOLDS[k] !== v),
    ),
    nodes: nodes.length,
    routes: routes.length,
    zones: zones.length,
    properCrossings: 0,
    ambiguousCorridors: 0,
    borderRuns: 0,
    labelClearanceIssues: 0,
    minNodeGap: null,
    minSegmentPx: null,
    maxBends: 0,
    minProjectedFontPx: null,
  };

  // routeSegments y bends recorren y normalizan la polilínea: se calculan una
  // vez por ruta y se reusan, en vez de una vez por comparación.
  const segmentsOf = new Map(routes.map((r) => [r.id, routeSegments(r.points)]));
  const textBoxes = cajasDeTexto(routes);

  checkNodosSolapados(scene, add, metrics);
  checkZonasSolapadas(scene, add);
  checkNodosAjenos(scene, add);
  checkRutas(scene, routes, segmentsOf, add, metrics);
  checkCrucesEntreRutas(routes, segmentsOf, add, metrics);
  checkCajasDeTexto(scene, routes, segmentsOf, textBoxes, add, metrics);
  checkLeyendaYLienzo(scene, routes, segmentsOf, textBoxes, add);
  checkLegibilidad(scene, add, metrics);

  for (const key of ['minNodeGap', 'minSegmentPx', 'minProjectedFontPx']) {
    if (typeof metrics[key] === 'number') metrics[key] = Number(metrics[key].toFixed(2));
  }
  return { bag, metrics };
}
