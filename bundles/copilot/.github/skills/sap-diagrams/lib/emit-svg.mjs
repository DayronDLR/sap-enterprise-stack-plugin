// Emisor SVG. Es la salida que entra al .docx/.pptx vía PNG.
//
// Fondo blanco y colores planos a propósito: el destino es un documento impreso
// o un Word de cliente, no un visor con tema oscuro. Todo el texto sale con el
// font-size que calculó text-fit, así que lo que valida el gate es exactamente
// lo que se ve.

import { rectRight, rectBottom, rectCenter, routeSegments } from './geometry.mjs';
import { fittedFontSize } from './text-fit.mjs';
import { COLORS, nodePalette, stepPalette, laneStyle, systemRoleStyle, relationColor, relationLabel, ZONE_STYLE, derivedLegend } from './palette.mjs';
import { iconBase64, fallbackPath } from './icons.mjs';
import { escapeXml } from './xml.mjs';

const FONT = "Arial, Helvetica, 'Segoe UI', sans-serif";

// El SVG trata <text> como texto, no como HTML: un solo escape alcanza.
const esc = escapeXml;

function polyline(points) {
  return points.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ');
}

function textEl(x, y, text, { size = 12, color = COLORS.titleColor, weight = 'normal', anchor = 'middle' } = {}) {
  return `<text x="${x.toFixed(1)}" y="${y.toFixed(1)}" font-family="${FONT}" font-size="${size}" `
    + `fill="${color}" font-weight="${weight}" text-anchor="${anchor}" dominant-baseline="middle">${esc(text)}</text>`;
}

function zoneEl(zone) {
  const style = ZONE_STYLE[zone.kind] || ZONE_STYLE.external;
  const parts = [
    `<rect x="${zone.rect.x.toFixed(1)}" y="${zone.rect.y.toFixed(1)}" width="${zone.rect.w.toFixed(1)}" `
    + `height="${zone.rect.h.toFixed(1)}" rx="14" fill="${style.fill}" stroke="${style.stroke}" stroke-width="1.5"/>`,
    textEl(zone.rect.x + 14, zone.rect.y + 17, zone.label, { size: 13, weight: 'bold', anchor: 'start' }),
  ];
  if (zone.sublabel) {
    parts.push(textEl(zone.rect.x + 14, zone.rect.y + 32, zone.sublabel, {
      size: 10, color: COLORS.textColor, anchor: 'start',
    }));
  }
  return parts.join('\n    ');
}

/** Carril de iFlow: banda a todo el ancho con el nombre en una franja lateral. */
function laneEl(lane) {
  const st = laneStyle(lane.kind);
  const r = lane.rect;
  const w = lane.labelW;
  const cy = r.y + r.h / 2;
  return [
    `<rect x="${r.x.toFixed(1)}" y="${r.y.toFixed(1)}" width="${r.w.toFixed(1)}" height="${r.h.toFixed(1)}" `
    + `rx="6" fill="${st.fill}" stroke="${st.stroke}" stroke-width="1.5"/>`,
    `<rect x="${r.x.toFixed(1)}" y="${r.y.toFixed(1)}" width="${w}" height="${r.h.toFixed(1)}" `
    + `rx="6" fill="${COLORS.white}" fill-opacity="0.55" stroke="${st.stroke}" stroke-width="1"/>`,
    `<text x="${(r.x + w / 2).toFixed(1)}" y="${cy.toFixed(1)}" font-family="${FONT}" font-size="11" `
    + `fill="${st.label}" font-weight="bold" text-anchor="middle" dominant-baseline="middle" `
    + `transform="rotate(-90 ${(r.x + w / 2).toFixed(1)} ${cy.toFixed(1)})">${esc(lane.label)}</text>`,
    lane.sublabel
      ? textEl(r.x + w + 12, r.y + 14, lane.sublabel, { size: 9, color: COLORS.textColor, anchor: 'start' })
      : '',
  ].filter(Boolean).join('\n    ');
}

/** Caja de sistema del landscape: SID grande, rol por color, mandantes adentro. */
function systemEl(sys) {
  const st = systemRoleStyle(sys.role);
  const r = sys.rect;
  return [
    `<rect x="${r.x.toFixed(1)}" y="${r.y.toFixed(1)}" width="${r.w.toFixed(1)}" height="${r.h.toFixed(1)}" `
    + `rx="12" fill="${st.fill}" stroke="${st.stroke}" stroke-width="2"/>`,
    textEl(r.x + r.w / 2, r.y + 20, sys.sid, { size: 18, weight: 'bold', color: st.stroke }),
    textEl(r.x + r.w / 2, r.y + 35, sys.label || st.label, { size: 10, color: COLORS.textColor }),
  ].join('\n    ');
}

/**
 * Texto accesible de un elemento.
 *
 * `<title>` es lo que lee un lector de pantalla y lo que hace buscable el texto
 * cuando el SVG termina dentro de un PDF. Sin esto el diagrama es una mancha
 * para quien no lo ve, y en el PDF no se puede buscar "HANA Cloud".
 */
function tituloAccesible(texto) {
  return `<title>${esc(texto)}</title>`;
}

function nodeEl(node, resolvePalette = nodePalette) {
  const pal = resolvePalette(node.type);
  const r = node.rect;
  const [cx] = rectCenter(r);
  const icon = iconBase64(node.icon);
  const out = [
    `<rect x="${r.x.toFixed(1)}" y="${r.y.toFixed(1)}" width="${r.w.toFixed(1)}" height="${r.h.toFixed(1)}" `
    + `rx="10" fill="${pal.fill}" stroke="${pal.stroke}" stroke-width="1.5"/>`,
  ];

  // El icono oficial de SAP si está; si no, el glifo propio en el MISMO lugar,
  // para que las dos variantes del diagrama tengan idéntica composición y no
  // haya dos calidades de entregable según quién lo corra.
  if (icon) {
    out.push(`<image x="${(cx - 14).toFixed(1)}" y="${(r.y + 9).toFixed(1)}" width="28" height="28" `
      + `href="data:image/svg+xml;base64,${icon}"/>`);
  } else {
    const escala = (26 / 24).toFixed(3);
    out.push(`<g transform="translate(${(cx - 13).toFixed(1)} ${(r.y + 9).toFixed(1)}) scale(${escala})" `
      + `fill="none" stroke="${pal.stroke}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">`
      + `<path d="${fallbackPath(node.type)}"/></g>`);
  }

  out.push(textEl(cx, r.y + 50, node.label, {
    size: fittedFontSize(node.label, r.w, 12), weight: 'bold', color: pal.text,
  }));
  if (node.sublabel) {
    out.push(textEl(cx, r.y + 64, node.sublabel, {
      size: fittedFontSize(node.sublabel, r.w, 10), color: COLORS.textColor,
    }));
  }

  const descripcion = [node.label, node.sublabel].filter(Boolean).join(' — ');
  return `<g role="img" aria-label="${esc(descripcion)}">${tituloAccesible(descripcion)}\n    `
    + `${out.join('\n    ')}</g>`;
}

function routeEl(route, diagramType) {
  const color = relationColor(route.kind, diagramType);
  const dash = route.style === 'dashed' ? ' stroke-dasharray="6 4"' : '';
  const marker = ` marker-end="url(#arrow-${route.kind})"`;
  const startMarker = route.bidirectional ? ` marker-start="url(#arrow-back-${route.kind})"` : '';
  const out = [
    `<polyline points="${polyline(route.points)}" fill="none" stroke="${color}" stroke-width="1.6" `
    + `stroke-linejoin="round"${dash}${marker}${startMarker}/>`,
  ];
  if (route.note && route.noteRect) {
    const nr = route.noteRect;
    out.push(`<rect x="${nr.x.toFixed(1)}" y="${nr.y.toFixed(1)}" width="${nr.w.toFixed(1)}" `
      + `height="${nr.h.toFixed(1)}" rx="3" fill="${COLORS.orangeFill}" stroke="${COLORS.orangeBorder}" `
      + 'stroke-width="1" stroke-dasharray="4 3"/>');
    out.push(textEl(nr.x + nr.w / 2, nr.y + nr.h / 2, route.note, { size: 9, color: COLORS.orangeBorder }));
  }
  if (route.label && route.labelRect) {
    const lr = route.labelRect;
    out.push(`<rect x="${lr.x.toFixed(1)}" y="${lr.y.toFixed(1)}" width="${lr.w.toFixed(1)}" `
      + `height="${lr.h.toFixed(1)}" rx="3" fill="${COLORS.white}" fill-opacity="0.92"/>`);
    out.push(textEl(lr.x + lr.w / 2, lr.y + lr.h / 2, route.label, { size: 10, color: COLORS.textColor }));
  }
  const descripcion = route.label
    ? `${route.from} → ${route.to}: ${route.label}`
    : `${route.from} → ${route.to}`;
  return `<g role="img" aria-label="${esc(descripcion)}">${tituloAccesible(descripcion)}\n    `
    + `${out.join('\n    ')}</g>`;
}

function legendEl(legend, entries, diagramType) {
  const out = [
    `<rect x="${legend.x.toFixed(1)}" y="${legend.y.toFixed(1)}" width="${legend.w.toFixed(1)}" `
    + `height="${legend.h.toFixed(1)}" rx="4" fill="${COLORS.white}" stroke="${COLORS.legendBorder}" stroke-width="1.5"/>`,
    textEl(legend.x + 12, legend.y + 16, 'Leyenda', { size: 12, weight: 'bold', anchor: 'start' }),
  ];
  entries.forEach((entry, i) => {
    const y = legend.y + 36 + i * 20;
    out.push(`<circle cx="${(legend.x + 20).toFixed(1)}" cy="${y.toFixed(1)}" r="5" fill="${relationColor(entry.kind, diagramType)}"/>`);
    out.push(textEl(legend.x + 34, y, entry.label || relationLabel(entry.kind, diagramType), {
      size: 10, color: COLORS.textColor, anchor: 'start',
    }));
  });
  return out.join('\n    ');
}

function markers(kinds, diagramType) {
  return kinds.flatMap((kind) => [
    `<marker id="arrow-${kind}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">`
    + `<path d="M 0 1 L 10 5 L 0 9 z" fill="${relationColor(kind, diagramType)}"/></marker>`,
    // El path ya apunta a -x y este marker se usa SOLO como marker-start, donde
    // `auto-start-reverse` rotaria 180 grados y cancelaria esa inversion: la
    // flecha de vuelta terminaria apuntando al destino. Con `auto` apunta al origen.
    `<marker id="arrow-back-${kind}" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" orient="auto">`
    + `<path d="M 10 1 L 0 5 L 10 9 z" fill="${relationColor(kind, diagramType)}"/></marker>`,
  ]).join('\n    ');
}

/** Lifelines y cajas de cierre, exclusivos del diagrama de secuencia. */
function sequenceChrome(scene) {
  const out = [];
  for (const n of scene.nodes) {
    out.push(`<line x1="${n.lifelineX.toFixed(1)}" y1="${scene.lifelineTop.toFixed(1)}" `
      + `x2="${n.lifelineX.toFixed(1)}" y2="${scene.lifelineBottom.toFixed(1)}" `
      + `stroke="${COLORS.extBorder}" stroke-width="1" stroke-dasharray="4 4" opacity="0.6"/>`);
  }
  for (const [i, f] of (scene.footers || []).entries()) {
    const node = scene.nodes[i];
    out.push(nodeEl({ ...node, rect: f }));
  }
  return out.join('\n    ');
}

/** Serializa la escena a un SVG standalone. */
export function emitSvg(scene, routes) {
  const porDefecto = scene.diagramType === 'landscape' ? 'workbench' : 'data';
  const kinds = [...new Set([...(routes || []).map((r) => r.kind || porDefecto), porDefecto])];
  const entries = derivedLegend(routes, scene.meta?.legend, scene.diagramType);
  const body = [
    `<rect width="${scene.size.width}" height="${scene.size.height}" fill="${COLORS.white}"/>`,
    textEl(scene.title.x, scene.title.y + 20, scene.meta?.title || '', {
      size: 17, weight: 'bold', color: COLORS.btpBorder, anchor: 'start',
    }),
    scene.meta?.subtitle
      ? textEl(scene.title.x, scene.title.y + 40, scene.meta.subtitle, {
        size: 11, color: COLORS.textColor, anchor: 'start',
      })
      : '',
    ...(scene.zones || []).map(zoneEl),
    ...(scene.lanes || []).map(laneEl),
    ...(scene.systems || []).map(systemEl),
    scene.diagramType === 'sequence' ? sequenceChrome(scene) : '',
    ...scene.nodes.map((n) => nodeEl(n, scene.diagramType === 'integration' ? stepPalette : nodePalette)),
    ...(routes || []).map((r) => routeEl(r, scene.diagramType)),
    legendEl(scene.legend, entries, scene.diagramType),
  ].filter(Boolean).join('\n    ');

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" `
    + `width="${scene.size.width}" height="${scene.size.height}" `
    + `viewBox="0 0 ${scene.size.width} ${scene.size.height}" role="img" `
    + `aria-label="${esc(scene.meta?.title || 'Diagrama SAP')}">
  <defs>
    ${markers(kinds, scene.diagramType)}
  </defs>
  <g>
    ${body}
  </g>
</svg>
`;
}

export { esc as escapeXml, rectRight, rectBottom, routeSegments };
