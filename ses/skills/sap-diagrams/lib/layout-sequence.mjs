// Layout determinista de un diagrama de secuencia SAP.
//
// Una secuencia no necesita ruteo: las columnas son los participantes y las filas
// son los mensajes. Lo único que hay que resolver bien es el ancho de columna,
// y se resuelve midiendo: cada gap entre lifelines se ensancha hasta que la
// etiqueta más larga que lo cruza entra sin pisar la línea de al lado. Eso mata
// el defecto clásico del sequenceDiagram de Mermaid — el texto montado sobre la
// flecha vecina.

import { rect, rectBottom, rectRight, boundingBox } from './geometry.mjs';
import { requiredBoxWidth, textWidth, overflowsEvenShrunk } from './text-fit.mjs';
import { nodeStyle } from './palette.mjs';

export const SEQ = Object.freeze({
  marginX: 40,
  marginY: 30,
  titleHeight: 52,
  headW: 150,
  headMaxW: 210,
  headH: 58,
  minGap: 60,
  labelPad: 24,
  rowH: 46,
  firstRowPad: 44,
  lastRowPad: 40,
  selfLoopW: 34,
  selfLoopH: 22,
  labelFontPx: 11,
  labelH: 15,
  noteH: 20,
  noteFontPx: 9,
  notePadX: 16,
  legendW: 210,
  legendRowH: 20,
  legendPadY: 26,
  notePad: 30,
});

function headWidth(p) {
  return Math.min(SEQ.headMaxW, Math.max(
    SEQ.headW,
    requiredBoxWidth(p.label, 12),
    p.sublabel ? requiredBoxWidth(p.sublabel, 10) : 0,
  ));
}

/**
 * Ancho de cada hueco entre lifelines. Arranca en el mínimo y se ensancha por
 * mensaje: si una etiqueta cruza tres columnas, el déficit se reparte entre los
 * tres huecos, no se le carga todo al primero.
 */
export function solveGaps(participants, messages) {
  const gaps = new Array(Math.max(0, participants.length - 1)).fill(SEQ.minGap);
  const index = new Map(participants.map((p, i) => [p.id, i]));
  const spans = (messages || [])
    .map((m) => {
      const a = index.get(m.from); const b = index.get(m.to);
      if (a === undefined || b === undefined || a === b) return null;
      const lo = Math.min(a, b); const hi = Math.max(a, b);
      // La nota cuelga centrada en el mismo tramo que el mensaje, así que
      // reclama ancho igual que la etiqueta. Sin esto una nota larga se sale
      // del lienzo y el PNG llega recortado al documento.
      const need = Math.max(
        textWidth(m.label, SEQ.labelFontPx) + SEQ.labelPad,
        m.note ? textWidth(m.note, SEQ.noteFontPx) + SEQ.notePadX + SEQ.labelPad : 0,
      );
      return { lo, hi, need };
    })
    .filter(Boolean)
    .sort((x, y) => (x.hi - x.lo) - (y.hi - y.lo));

  for (const s of spans) {
    const slice = gaps.slice(s.lo, s.hi);
    const have = slice.reduce((a, b) => a + b, 0);
    if (have >= s.need) continue;
    const deficit = (s.need - have) / slice.length;
    for (let i = s.lo; i < s.hi; i += 1) gaps[i] += deficit;
  }
  return gaps.map((g) => Math.ceil(g));
}

export function layoutSequence(spec) {
  const problems = [];
  const participants = spec.participants || [];
  const messages = spec.messages || [];
  const known = new Map(participants.map((p) => [p.id, p]));

  const firstAt = new Map();
  for (const [i, p2] of participants.entries()) {
    if (firstAt.has(p2.id)) {
      problems.push({
        code: 'model/duplicate-participant-id',
        message: `El id "${p2.id}" aparece en /participants/${firstAt.get(p2.id)} y en /participants/${i}.`,
        subject: { path: `/participants/${i}/id`, identity: p2.id },
        evidence: { firstAt: firstAt.get(p2.id), duplicateAt: i },
        supportedFixes: ['renombrar el segundo participante', 'quitar el duplicado'],
      });
    } else firstAt.set(p2.id, i);
  }

  for (const [i, m] of messages.entries()) {
    for (const end of ['from', 'to']) {
      if (!known.has(m[end])) {
        problems.push({
          code: 'model/dangling-message',
          message: `El mensaje /messages/${i} apunta a "${m[end]}", que no está en participants.`,
          subject: { path: `/messages/${i}/${end}`, identity: m[end] },
          evidence: { known: [...known.keys()] },
          supportedFixes: ['usar un id de participants', `agregar el participante "${m[end]}"`],
        });
      }
    }
  }

  const widths = participants.map(headWidth);
  for (const [i, p] of participants.entries()) {
    if (overflowsEvenShrunk(p.label, widths[i])) {
      problems.push({
        code: 'text/participant-overflow',
        message: `El label "${p.label}" no entra en la cabecera ni encogido al mínimo legible.`,
        subject: { path: `/participants/${i}/label`, identity: p.id },
        evidence: { boxWidth: widths[i], maxBoxWidth: SEQ.headMaxW },
        supportedFixes: ['acortar el nombre del participante', 'mover el detalle a `sublabel`'],
      });
    }
  }

  const gaps = solveGaps(participants, messages);
  const xs = [];
  let cursor = SEQ.marginX;
  participants.forEach((p, i) => {
    xs.push(cursor);
    cursor += widths[i] + (gaps[i] ?? 0);
  });

  const headTop = SEQ.marginY + SEQ.titleHeight;
  const nodes = participants.map((p, i) => ({
    ...p,
    icon: nodeStyle(p.type).icon,
    lifelineX: xs[i] + widths[i] / 2,
    rect: rect(xs[i], headTop, widths[i], SEQ.headH),
  }));
  const lifeline = new Map(nodes.map((n) => [n.id, n.lifelineX]));

  let y = headTop + SEQ.headH + SEQ.firstRowPad;
  const routes = [];
  messages.forEach((m, i) => {
    const x1 = lifeline.get(m.from);
    const x2 = lifeline.get(m.to);
    if (x1 === undefined || x2 === undefined) return;
    const id = m.id || `m${i}`;
    const self = m.from === m.to;
    const points = self
      ? [[x1, y], [x1 + SEQ.selfLoopW, y], [x1 + SEQ.selfLoopW, y + SEQ.selfLoopH], [x1, y + SEQ.selfLoopH]]
      : [[x1, y], [x2, y]];
    const w = textWidth(m.label, SEQ.labelFontPx) + 12;
    const cx = self ? x1 + SEQ.selfLoopW + w / 2 + 8 : (x1 + x2) / 2;
    // La nota cuelga bajo el mensaje, centrada en su tramo. Va a la escena como
    // un rectángulo más: el gate la mide igual que a una etiqueta, así que una
    // nota que tapa una lifeline o a otra nota bloquea la entrega.
    const noteW = m.note ? textWidth(m.note, SEQ.noteFontPx) + SEQ.notePadX : 0;
    const noteRect = m.note
      ? rect(cx - noteW / 2, y + 10, noteW, SEQ.noteH)
      : null;

    routes.push({
      id,
      index: i,
      from: m.from,
      to: m.to,
      label: m.label,
      note: m.note || '',
      noteRect,
      kind: m.kind || 'data',
      style: m.style || (m.return ? 'dashed' : 'solid'),
      isReturn: Boolean(m.return),
      self,
      order: i + 1,
      points,
      labelAnchor: [cx, y - SEQ.labelH / 2 - 2],
      labelRect: rect(cx - w / 2, y - SEQ.labelH - 4, w, SEQ.labelH),
    });
    y += SEQ.rowH + (self ? SEQ.selfLoopH : 0) + (m.note ? SEQ.notePad : 0);
  });

  const lifelineBottom = y + SEQ.lastRowPad;
  const footers = nodes.map((n) => rect(n.rect.x, lifelineBottom, n.rect.w, SEQ.headH));
  const content = boundingBox([...nodes.map((n) => n.rect), ...footers]);
  const legendRows = Math.max(1, new Set(routes.map((r) => r.kind)).size);
  const legend = rect(
    SEQ.marginX,
    rectBottom(content) + SEQ.legendPadY,
    SEQ.legendW,
    30 + legendRows * SEQ.legendRowH,
  );
  const width = Math.max(rectRight(content), rectRight(legend)) + SEQ.marginX;
  const height = rectBottom(legend) + SEQ.marginY;

  return {
    diagramType: 'sequence',
    meta: spec.meta,
    nodes,
    footers,
    zones: [],
    routes,
    content,
    legend,
    lifelineTop: headTop + SEQ.headH,
    lifelineBottom,
    title: rect(SEQ.marginX, SEQ.marginY, width - SEQ.marginX * 2, SEQ.titleHeight),
    size: { width: Math.round(width), height: Math.round(height) },
    problems,
  };
}
