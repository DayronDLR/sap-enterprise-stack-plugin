// Primitivas geométricas y colectores de composición.
//
// Todo lo que este motor sabe sobre "el diagrama se lee bien" vive acá, medido
// en píxeles sobre la escena ya posicionada. Ningún colector opina de estilo:
// cada uno devuelve hechos con su medición, y checks.mjs decide la severidad.
//
// Supuesto duro: todas las rutas son ortogonales (segmentos H o V). Lo garantiza
// route.mjs y lo verifica `collectNonOrthogonal`.
//
// Algoritmos de corredor ambiguo, cruce propio, corrida sobre borde y ritmo de
// segmentos adaptados de archify (MIT, tt-a1i) — ver NOTICE.

const EPS = 0.001;

// ── Rectángulos ──────────────────────────────────────────────────────────────

export function rect(x, y, w, h) {
  return { x, y, w, h };
}

export function rectRight(r) { return r.x + r.w; }
export function rectBottom(r) { return r.y + r.h; }
export function rectCenter(r) { return [r.x + r.w / 2, r.y + r.h / 2]; }

/** Separación libre entre dos rects. 0 si se tocan o solapan. */
export function rectGap(a, b) {
  const dx = Math.max(0, Math.max(a.x - rectRight(b), b.x - rectRight(a)));
  const dy = Math.max(0, Math.max(a.y - rectBottom(b), b.y - rectBottom(a)));
  if (dx === 0 && dy === 0) return 0;
  if (dx === 0) return dy;
  if (dy === 0) return dx;
  return Math.hypot(dx, dy);
}

export function rectsOverlap(a, b, gap = 0) {
  return a.x - gap < rectRight(b) && b.x - gap < rectRight(a)
    && a.y - gap < rectBottom(b) && b.y - gap < rectBottom(a);
}

/** true si `inner` está completamente dentro de `outer`. */
export function rectContains(outer, inner) {
  return inner.x >= outer.x && inner.y >= outer.y
    && rectRight(inner) <= rectRight(outer) && rectBottom(inner) <= rectBottom(outer);
}

/** Caja envolvente de una lista de rects. */
export function boundingBox(rects) {
  if (!rects.length) return rect(0, 0, 0, 0);
  const x = Math.min(...rects.map((r) => r.x));
  const y = Math.min(...rects.map((r) => r.y));
  const x2 = Math.max(...rects.map(rectRight));
  const y2 = Math.max(...rects.map(rectBottom));
  return rect(x, y, x2 - x, y2 - y);
}

export function inflate(r, pad) {
  return rect(r.x - pad, r.y - pad, r.w + pad * 2, r.h + pad * 2);
}

// ── Segmentos ────────────────────────────────────────────────────────────────

export function segmentLength(s) {
  return Math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]);
}

export function isHorizontal(s) { return Math.abs(s[0][1] - s[1][1]) < EPS; }
export function isVertical(s) { return Math.abs(s[0][0] - s[1][0]) < EPS; }

/** Quita puntos repetidos y vértices colineales: deja la polilínea mínima. */
export function normalizeRoute(points) {
  const out = [];
  for (const p of points) {
    const last = out[out.length - 1];
    if (last && Math.abs(last[0] - p[0]) < EPS && Math.abs(last[1] - p[1]) < EPS) continue;
    out.push([p[0], p[1]]);
  }
  for (let i = 1; i < out.length - 1;) {
    const [a, b, c] = [out[i - 1], out[i], out[i + 1]];
    const collinear = (Math.abs(a[0] - b[0]) < EPS && Math.abs(b[0] - c[0]) < EPS)
      || (Math.abs(a[1] - b[1]) < EPS && Math.abs(b[1] - c[1]) < EPS);
    if (collinear) out.splice(i, 1);
    else i += 1;
  }
  return out;
}

export function routeSegments(points) {
  const segs = [];
  for (let i = 0; i < points.length - 1; i += 1) segs.push([points[i], points[i + 1]]);
  return segs;
}

/** Distancia mínima de un segmento a un rect. 0 si lo toca o lo atraviesa. */
export function segmentRectClearance(s, r) {
  if (segmentIntersectsRect(s, r, 0)) return 0;
  const [[x1, y1], [x2, y2]] = s;
  if (isHorizontal(s)) {
    const lo = Math.min(x1, x2); const hi = Math.max(x1, x2);
    const dx = Math.max(0, Math.max(r.x - hi, lo - rectRight(r)));
    const dy = Math.max(0, Math.max(r.y - y1, y1 - rectBottom(r)));
    return dx === 0 ? dy : (dy === 0 ? dx : Math.hypot(dx, dy));
  }
  const lo = Math.min(y1, y2); const hi = Math.max(y1, y2);
  const dy = Math.max(0, Math.max(r.y - hi, lo - rectBottom(r)));
  const dx = Math.max(0, Math.max(r.x - x1, x1 - rectRight(r)));
  return dy === 0 ? dx : (dx === 0 ? dy : Math.hypot(dx, dy));
}

/** true si el segmento entra en el rect inflado `gap`. */
export function segmentIntersectsRect(s, r, gap = 0) {
  const box = inflate(r, gap);
  const [[x1, y1], [x2, y2]] = s;
  if (isHorizontal(s)) {
    if (y1 <= box.y + EPS || y1 >= rectBottom(box) - EPS) return false;
    return Math.min(x1, x2) < rectRight(box) - EPS && Math.max(x1, x2) > box.x + EPS;
  }
  if (isVertical(s)) {
    if (x1 <= box.x + EPS || x1 >= rectRight(box) - EPS) return false;
    return Math.min(y1, y2) < rectBottom(box) - EPS && Math.max(y1, y2) > box.y + EPS;
  }
  return false;
}

/**
 * Cruce propio entre dos segmentos ortogonales: uno H y uno V que se atraviesan
 * en un punto interior de ambos. Un toque en un extremo no es cruce — es una
 * esquina compartida, que se lee bien.
 */
export function properCrossing(a, b) {
  const h = isHorizontal(a) ? a : (isHorizontal(b) ? b : null);
  const v = isVertical(a) ? a : (isVertical(b) ? b : null);
  if (!h || !v || h === v) return null;
  const y = h[0][1];
  const x = v[0][0];
  const hLo = Math.min(h[0][0], h[1][0]); const hHi = Math.max(h[0][0], h[1][0]);
  const vLo = Math.min(v[0][1], v[1][1]); const vHi = Math.max(v[0][1], v[1][1]);
  const inside = x > hLo + EPS && x < hHi - EPS && y > vLo + EPS && y < vHi - EPS;
  return inside ? [x, y] : null;
}

/**
 * Corredor ambiguo: dos segmentos paralelos tan cerca y con tanto solape que a
 * escala de lectura se leen como una sola línea. Devuelve la medición o null.
 */
export function parallelCorridor(a, b, { maxDistance = 12, minOverlap = 24 } = {}) {
  if (isHorizontal(a) && isHorizontal(b)) {
    const distance = Math.abs(a[0][1] - b[0][1]);
    if (distance > maxDistance) return null;
    const lo = Math.max(Math.min(a[0][0], a[1][0]), Math.min(b[0][0], b[1][0]));
    const hi = Math.min(Math.max(a[0][0], a[1][0]), Math.max(b[0][0], b[1][0]));
    const overlap = hi - lo;
    return overlap >= minOverlap ? { distance, overlap, axis: 'horizontal' } : null;
  }
  if (isVertical(a) && isVertical(b)) {
    const distance = Math.abs(a[0][0] - b[0][0]);
    if (distance > maxDistance) return null;
    const lo = Math.max(Math.min(a[0][1], a[1][1]), Math.min(b[0][1], b[1][1]));
    const hi = Math.min(Math.max(a[0][1], a[1][1]), Math.max(b[0][1], b[1][1]));
    const overlap = hi - lo;
    return overlap >= minOverlap ? { distance, overlap, axis: 'vertical' } : null;
  }
  return null;
}

/**
 * Corrida sobre el borde de un marco: el segmento viaja pegado a un lado de la
 * zona en vez de cruzarlo perpendicular. Es el defecto que hace que un diagrama
 * BTP se lea como si el servicio estuviera fuera del subaccount.
 */
export function borderRun(s, frame, { tolerance = 6, minRun = 20 } = {}) {
  const sides = [
    { name: 'top', axis: 'horizontal', at: frame.y },
    { name: 'bottom', axis: 'horizontal', at: rectBottom(frame) },
    { name: 'left', axis: 'vertical', at: frame.x },
    { name: 'right', axis: 'vertical', at: rectRight(frame) },
  ];
  for (const side of sides) {
    if (side.axis === 'horizontal' && isHorizontal(s) && Math.abs(s[0][1] - side.at) <= tolerance) {
      const lo = Math.max(Math.min(s[0][0], s[1][0]), frame.x);
      const hi = Math.min(Math.max(s[0][0], s[1][0]), rectRight(frame));
      if (hi - lo >= minRun) return { side: side.name, run: hi - lo, distance: Math.abs(s[0][1] - side.at) };
    }
    if (side.axis === 'vertical' && isVertical(s) && Math.abs(s[0][0] - side.at) <= tolerance) {
      const lo = Math.max(Math.min(s[0][1], s[1][1]), frame.y);
      const hi = Math.min(Math.max(s[0][1], s[1][1]), rectBottom(frame));
      if (hi - lo >= minRun) return { side: side.name, run: hi - lo, distance: Math.abs(s[0][0] - side.at) };
    }
  }
  return null;
}

/**
 * Ritmo de una ruta: segmentos visibles demasiado cortos. Un tramo de 3px entre
 * dos giros no se lee como un giro, se lee como un defecto de render.
 */
export function routeRhythm(points, { microPx = 8, interiorPx = 16 } = {}) {
  const segs = routeSegments(points);
  const issues = [];
  segs.forEach((s, i) => {
    const len = segmentLength(s);
    const interior = i > 0 && i < segs.length - 1;
    if (len < microPx) issues.push({ index: i, length: len, kind: 'micro', limit: microPx });
    else if (interior && len < interiorPx) issues.push({ index: i, length: len, kind: 'interior', limit: interiorPx });
  });
  return issues;
}

export function bends(points) {
  return Math.max(0, normalizeRoute(points).length - 2);
}

export function routeLength(points) {
  return routeSegments(points).reduce((sum, s) => sum + segmentLength(s), 0);
}

/**
 * Punto a la fracción `t` del largo total de la ruta.
 *
 * El ancla de etiqueta se mide por longitud de camino, no por segmento más
 * largo: el segmento más largo de una ruta H-V-H suele ser el primero, que sale
 * pegado al nodo origen — y ahí es exactamente donde la etiqueta lo tapa. Medir
 * por camino también hace que draw.io centre la etiqueta en el mismo lugar que
 * el SVG, así los dos entregables no divergen.
 */
export function pointAtFraction(points, t = 0.5) {
  const segs = routeSegments(points);
  if (!segs.length) return points[0] || [0, 0];
  const total = routeLength(points);
  if (!total) return points[0];
  const target = Math.min(1, Math.max(0, t)) * total;
  let run = 0;
  for (const s of segs) {
    const len = segmentLength(s);
    if (run + len >= target) {
      const k = len ? (target - run) / len : 0;
      return [s[0][0] + (s[1][0] - s[0][0]) * k, s[0][1] + (s[1][1] - s[0][1]) * k];
    }
    run += len;
  }
  const last = segs[segs.length - 1];
  return [last[1][0], last[1][1]];
}

/** Punto medio de la ruta por longitud de camino. */
export function routeLabelAnchor(points) {
  return pointAtFraction(points, 0.5);
}
