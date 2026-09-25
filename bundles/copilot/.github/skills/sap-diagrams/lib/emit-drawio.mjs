// Emisor draw.io (.drawio / mxGraph XML). Es el entregable que el cliente edita.
//
// Regla de fidelidad: el XML reproduce EXACTAMENTE la geometría que validó el
// gate. Por eso las aristas salen con `edgeStyle=none` + waypoints explícitos y
// restricciones exit/entry fijas, en vez de dejar que draw.io re-rutee: un
// re-ruteo del editor invalidaría en silencio los checks de cruce y corredor.
//
// Convenciones de estilo heredadas de agents/11-documentation/tools/sap-drawio-generator.py
// (arcSize=24, absoluteArcSize=1, strokeWidth=1.5, labels de icono en texto plano).

import { rectRight, rectBottom, rectCenter, routeSegments, segmentLength } from './geometry.mjs';
import { fittedFontSize } from './text-fit.mjs';
import { COLORS, nodePalette, stepPalette, laneStyle, systemRoleStyle, relationColor, relationLabel, ZONE_STYLE, derivedLegend } from './palette.mjs';
import { iconBase64, fallbackSvgBase64 } from './icons.mjs';
import { escapeXml, escapeXmlText } from './xml.mjs';

// TODAS las celdas de este emisor llevan `html=1`, así que todo texto de usuario
// pasa por el doble escape. Ver lib/xml.mjs para el porqué.
const esc = escapeXmlText;

function geometry(r) {
  return `<mxGeometry x="${r.x.toFixed(1)}" y="${r.y.toFixed(1)}" `
    + `width="${r.w.toFixed(1)}" height="${r.h.toFixed(1)}" as="geometry" />`;
}

function vertex(id, value, style, r) {
  return `<mxCell id="${id}" value="${esc(value)}" style="${style}" parent="1" vertex="1">${geometry(r)}</mxCell>`;
}

/** Fracción [0..1] del largo total de la ruta a la que cae el ancla de etiqueta. */
function anchorFraction(points, anchor) {
  const segs = routeSegments(points);
  const total = segs.reduce((sum, s) => sum + segmentLength(s), 0);
  if (!total) return 0.5;
  let run = 0;
  for (const s of segs) {
    const len = segmentLength(s);
    const [[x1, y1], [x2, y2]] = s;
    const onSeg = Math.abs(x1 - x2) < 0.001
      ? Math.abs(anchor[0] - x1) < 1 && anchor[1] >= Math.min(y1, y2) - 1 && anchor[1] <= Math.max(y1, y2) + 1
      : Math.abs(anchor[1] - y1) < 1 && anchor[0] >= Math.min(x1, x2) - 1 && anchor[0] <= Math.max(x1, x2) + 1;
    if (onSeg) {
      const into = Math.hypot(anchor[0] - x1, anchor[1] - y1);
      return Math.min(1, Math.max(0, (run + into) / total));
    }
    run += len;
  }
  return 0.5;
}

function exitConstraint(r, point, prefix) {
  const x = (point[0] - r.x) / r.w;
  const y = (point[1] - r.y) / r.h;
  return `${prefix}X=${x.toFixed(4)};${prefix}Y=${y.toFixed(4)};${prefix}Dx=0;${prefix}Dy=0;`;
}

function zoneCell(zone, id) {
  const style = ZONE_STYLE[zone.kind] || ZONE_STYLE.external;
  const value = zone.sublabel
    ? `${esc(zone.label)}&lt;div&gt;&lt;font style=&quot;font-size: 11px;&quot;&gt;`
      + `&lt;span style=&quot;font-weight: normal;&quot;&gt;${esc(zone.sublabel)}&lt;/span&gt;&lt;/font&gt;&lt;/div&gt;`
    : esc(zone.label);
  const style2 = `rounded=1;whiteSpace=wrap;html=1;strokeColor=${style.stroke};fillColor=${style.fill};`
    + 'arcSize=24;absoluteArcSize=1;strokeWidth=1.5;container=0;verticalAlign=top;align=left;'
    + `fontSize=13;fontStyle=1;spacingLeft=10;spacingTop=6;fontFamily=Arial;fontColor=${COLORS.titleColor};`;
  return `<mxCell id="${id}" value="${value}" style="${style2}" parent="1" vertex="1">${geometry(zone.rect)}</mxCell>`;
}

/** Carril de iFlow: en draw.io es un `swimlane` horizontal nativo, editable. */
function laneCell(lane, id) {
  const st = laneStyle(lane.kind);
  const value = lane.sublabel ? `${lane.label} — ${lane.sublabel}` : lane.label;
  const style = `swimlane;horizontal=0;html=1;startSize=${lane.labelW};rounded=1;arcSize=6;`
    + `fillColor=${st.fill};strokeColor=${st.stroke};strokeWidth=1.5;fontFamily=Arial;fontSize=11;`
    + `fontStyle=1;fontColor=${st.label};container=0;collapsible=0;`;
  return vertex(id, value, style, lane.rect);
}

/** Caja de sistema del landscape. */
function systemCell(sys, id) {
  const st = systemRoleStyle(sys.role);
  const value = `${sys.sid}&lt;div&gt;&lt;font style=&quot;font-size: 10px;&quot;&gt;`
    + `&lt;span style=&quot;font-weight: normal;&quot;&gt;${esc(sys.label || st.label)}&lt;/span&gt;&lt;/font&gt;&lt;/div&gt;`;
  const style = `rounded=1;whiteSpace=wrap;html=1;strokeColor=${st.stroke};fillColor=${st.fill};`
    + 'arcSize=12;absoluteArcSize=1;strokeWidth=2;container=0;verticalAlign=top;align=center;'
    + `fontSize=18;fontStyle=1;spacingTop=6;fontFamily=Arial;fontColor=${st.stroke};`;
  return `<mxCell id="${id}" value="${value}" style="${style}" parent="1" vertex="1">${geometry(sys.rect)}</mxCell>`;
}

function nodeCells(node, id, resolvePalette = nodePalette) {
  const pal = resolvePalette(node.type);
  const icon = iconBase64(node.icon);
  const r = node.rect;
  const cells = [];
  if (icon) {
    const box = `rounded=1;whiteSpace=wrap;html=1;strokeColor=${pal.stroke};fillColor=${pal.fill};`
      + 'arcSize=16;absoluteArcSize=1;strokeWidth=1.5;container=0;verticalAlign=bottom;spacingBottom=6;'
      + `fontFamily=Arial;fontSize=${fittedFontSize(node.label, r.w, 12)};fontStyle=1;fontColor=${pal.text};`;
    const label = node.sublabel ? `${node.label}\n${node.sublabel}` : node.label;
    cells.push(vertex(id, label, box, r));
    const [cx] = rectCenter(r);
    cells.push(`<mxCell id="${id}-ico" value="" style="shape=image;imageAspect=0;aspect=fixed;`
      + `image=data:image/svg+xml,${icon};" parent="1" vertex="1">`
      + `<mxGeometry x="${(cx - 14).toFixed(1)}" y="${(r.y + 8).toFixed(1)}" width="28" height="28" as="geometry" /></mxCell>`);
  } else {
    // Sin icono SAP va el glifo propio, en la misma posición que ocuparía el
    // oficial: el .drawio del plugin público y el del stack interno se ven igual
    // salvo por el pictograma.
    const box = `rounded=1;whiteSpace=wrap;html=1;strokeColor=${pal.stroke};fillColor=${pal.fill};`
      + 'arcSize=16;absoluteArcSize=1;strokeWidth=1.5;container=0;verticalAlign=bottom;spacingBottom=6;'
      + `fontFamily=Arial;fontSize=${fittedFontSize(node.label, r.w, 12)};fontStyle=1;fontColor=${pal.text};`;
    const label = node.sublabel ? `${node.label}\n${node.sublabel}` : node.label;
    cells.push(vertex(id, label, box, r));
    const [cx] = rectCenter(r);
    cells.push(`<mxCell id="${id}-glifo" value="" style="shape=image;imageAspect=0;aspect=fixed;`
      + `image=data:image/svg+xml;base64,${fallbackSvgBase64(node.type, pal.stroke)};" parent="1" vertex="1">`
      + `<mxGeometry x="${(cx - 13).toFixed(1)}" y="${(r.y + 8).toFixed(1)}" width="26" height="26" as="geometry" /></mxCell>`);
  }
  return cells;
}

function edgeCell(route, id, sourceId, targetId, sourceRect, targetRect, diagramType) {
  const color = relationColor(route.kind, diagramType);
  const dash = route.style === 'dashed' ? 'dashed=1;' : '';
  const start = route.bidirectional ? 'startArrow=blockThin;startFill=1;startSize=5;' : '';
  const points = route.points;
  const style = 'edgeStyle=none;rounded=0;html=1;endArrow=blockThin;endFill=1;endSize=5;strokeWidth=1.6;'
    + `strokeColor=${color};${dash}${start}fontFamily=Arial;fontSize=10;fontColor=${COLORS.textColor};`
    + `labelBackgroundColor=${COLORS.white};`
    + exitConstraint(sourceRect, points[0], 'exit')
    + exitConstraint(targetRect, points[points.length - 1], 'entry');
  const waypoints = points.slice(1, -1)
    .map(([x, y]) => `<mxPoint x="${x.toFixed(1)}" y="${y.toFixed(1)}" />`)
    .join('');
  const t = route.label ? anchorFraction(points, route.labelAnchor) : 0.5;
  const labelPos = route.label ? ` x="${(2 * t - 1).toFixed(4)}" y="0"` : '';
  return `<mxCell id="${id}" value="${esc(route.label || '')}" style="${style}" parent="1" `
    + `source="${sourceId}" target="${targetId}" edge="1">`
    + `<mxGeometry relative="1"${labelPos} as="geometry">`
    + (waypoints ? `<Array as="points">${waypoints}</Array>` : '')
    + '</mxGeometry></mxCell>';
}

/** Nota de un mensaje: caja punteada ámbar, con la misma geometría que validó el gate. */
function noteCell(route, id) {
  const style = `rounded=1;whiteSpace=wrap;html=1;dashed=1;dashPattern=4 3;arcSize=12;absoluteArcSize=1;`
    + `strokeColor=${COLORS.orangeBorder};fillColor=${COLORS.orangeFill};strokeWidth=1;`
    + `fontFamily=Arial;fontSize=9;fontColor=${COLORS.orangeBorder};verticalAlign=middle;`;
  return vertex(id, route.note, style, route.noteRect);
}

function legendCells(legend, entries, seed, diagramType) {
  const cells = [
    `<mxCell id="${seed}" value="" style="rounded=0;whiteSpace=wrap;html=1;strokeColor=${COLORS.legendBorder};`
    + `strokeWidth=1.5;fillColor=${COLORS.white};" parent="1" vertex="1">${geometry(legend)}</mxCell>`,
    `<mxCell id="${seed}-t" value="Leyenda" style="text;html=1;align=left;verticalAlign=middle;strokeColor=none;`
    + `fillColor=none;fontSize=12;fontStyle=1;fontFamily=Arial;fontColor=${COLORS.titleColor};" parent="1" vertex="1">`
    + `<mxGeometry x="${(legend.x + 10).toFixed(1)}" y="${(legend.y + 6).toFixed(1)}" width="120" height="20" as="geometry" /></mxCell>`,
  ];
  entries.forEach((entry, i) => {
    const y = legend.y + 29 + i * 20;
    cells.push(`<mxCell id="${seed}-d${i}" value="" style="ellipse;html=1;aspect=fixed;strokeColor=none;`
      + `fillColor=${relationColor(entry.kind, diagramType)};" parent="1" vertex="1">`
      + `<mxGeometry x="${(legend.x + 15).toFixed(1)}" y="${y.toFixed(1)}" width="10" height="10" as="geometry" /></mxCell>`);
    cells.push(`<mxCell id="${seed}-l${i}" value="${esc(entry.label || relationLabel(entry.kind, diagramType))}" `
      + `style="text;html=1;align=left;verticalAlign=middle;strokeColor=none;fillColor=none;fontSize=10;`
      + `fontFamily=Arial;fontColor=${COLORS.textColor};" parent="1" vertex="1">`
      + `<mxGeometry x="${(legend.x + 30).toFixed(1)}" y="${(y - 5).toFixed(1)}" width="160" height="20" as="geometry" /></mxCell>`);
  });
  return cells;
}

/** Serializa la escena a XML de draw.io. */
export function emitDrawio(scene, routes) {
  const cells = [];
  const idOf = new Map();

  cells.push(`<mxCell id="title" value="${esc(scene.meta?.title || '')}" `
    + `style="text;html=1;align=left;verticalAlign=middle;strokeColor=none;fillColor=none;fontSize=17;`
    + `fontStyle=1;fontFamily=Arial;fontColor=${COLORS.btpBorder};" parent="1" vertex="1">`
    + `<mxGeometry x="${scene.title.x}" y="${scene.title.y}" width="${scene.title.w}" height="26" as="geometry" /></mxCell>`);
  if (scene.meta?.subtitle) {
    cells.push(`<mxCell id="subtitle" value="${esc(scene.meta.subtitle)}" `
      + `style="text;html=1;align=left;verticalAlign=middle;strokeColor=none;fillColor=none;fontSize=11;`
      + `fontFamily=Arial;fontColor=${COLORS.textColor};" parent="1" vertex="1">`
      + `<mxGeometry x="${scene.title.x}" y="${scene.title.y + 26}" width="${scene.title.w}" height="20" as="geometry" /></mxCell>`);
  }

  (scene.zones || []).forEach((z, i) => cells.push(zoneCell(z, `zone-${i}`)));
  (scene.lanes || []).forEach((l, i) => cells.push(laneCell(l, `lane-${i}`)));
  (scene.systems || []).forEach((sys, i) => cells.push(systemCell(sys, `sys-${i}`)));
  const paletaDeNodo = scene.diagramType === 'integration' ? stepPalette : nodePalette;

  if (scene.diagramType === 'sequence') {
    scene.nodes.forEach((n, i) => {
      cells.push(`<mxCell id="life-${i}" value="" style="endArrow=none;dashed=1;html=1;strokeColor=${COLORS.extBorder};`
        + `strokeWidth=1;opacity=60;" parent="1" edge="1"><mxGeometry relative="1" as="geometry">`
        + `<mxPoint x="${n.lifelineX.toFixed(1)}" y="${scene.lifelineTop.toFixed(1)}" as="sourcePoint" />`
        + `<mxPoint x="${n.lifelineX.toFixed(1)}" y="${scene.lifelineBottom.toFixed(1)}" as="targetPoint" />`
        + '</mxGeometry></mxCell>');
    });
    (scene.footers || []).forEach((f, i) => {
      cells.push(...nodeCells({ ...scene.nodes[i], rect: f }, `foot-${i}`));
    });
  }

  scene.nodes.forEach((n, i) => {
    const id = `n-${i}`;
    idOf.set(n.id, { id, rect: n.rect });
    cells.push(...nodeCells(n, id, paletaDeNodo));
  });

  (routes || []).forEach((r, i) => {
    const s = idOf.get(r.from);
    const t = idOf.get(r.to);
    if (!s || !t) return;
    cells.push(edgeCell(r, `edge-${i}`, s.id, t.id, s.rect, t.rect, scene.diagramType));
    if (r.note && r.noteRect) cells.push(noteCell(r, `note-${i}`));
  });

  cells.push(...legendCells(scene.legend, derivedLegend(routes, scene.meta?.legend, scene.diagramType), 'legend', scene.diagramType));

  const pageW = Math.max(850, Math.ceil(scene.size.width / 10) * 10);
  const pageH = Math.max(600, Math.ceil(scene.size.height / 10) * 10);
  // El `name` del <diagram> es el rótulo de la pestaña y draw.io lo lee como
  // texto plano, no como HTML: acá el doble escape mostraría `&amp;` literal.
  return `<mxfile host="sap-enterprise-agent-stack" agent="sap-diagrams">
  <diagram name="${escapeXml(scene.meta?.title || 'Diagrama')}" id="sap-diagram-1">
    <mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${pageW}" pageHeight="${pageH}" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        ${cells.join('\n        ')}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
`;
}

export { rectRight, rectBottom };
