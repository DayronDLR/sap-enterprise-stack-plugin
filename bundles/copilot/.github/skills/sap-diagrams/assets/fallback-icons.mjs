// Pictogramas propios, dibujados para este stack (GPL-3.0, como el resto).
//
// Existen por una razón concreta: la librería de iconos SAP BTP es un asset
// propietario que NO se redistribuye (ver NOTICE), así que quien instala el
// plugin público veía todos los nodos como cajas rotuladas. Un diagrama sin
// pictogramas se lee peor y, sobre todo, se lee distinto del que produce el
// stack interno — dos calidades de entregable según quién lo corra.
//
// No imitan los iconos de SAP: son glifos genéricos de trazo, por familia. La
// intención es que un servidor se distinga de una base y de un escudo de un
// vistazo, no parecerse a la iconografía oficial.
//
// Cada glifo es un `path` en un viewBox de 24×24, con `currentColor` para que
// tome el color del nodo. Trazo y no relleno: escala bien y no compite con el texto.

/** Trazos por familia. Deliberadamente simples: a 28px un glifo detallado es ruido. */
export const GLYPHS = Object.freeze({
  usuario:     'M12 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4ZM5 19.5c0-3.6 3.1-5.6 7-5.6s7 2 7 5.6',
  navegador:   'M3.5 5.5h17v13h-17zM3.5 9.5h17M6 7.5h.01M8.5 7.5h.01',
  servicio:    'M12 8.2v-2M12 17.8v2M15.4 9.6 16.8 8.2M7.2 15.8l-1.4 1.4M17.8 12h2M4.2 12h2M15.4 14.4l1.4 1.4M7.2 8.2 5.8 6.8M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z',
  base:        'M12 4.5c4 0 7 1.1 7 2.5s-3 2.5-7 2.5-7-1.1-7-2.5 3-2.5 7-2.5ZM5 7v10c0 1.4 3 2.5 7 2.5s7-1.1 7-2.5V7M5 12c0 1.4 3 2.5 7 2.5s7-1.1 7-2.5',
  seguridad:   'M12 4.2 5.5 6.8v5.1c0 3.6 2.6 6.6 6.5 7.9 3.9-1.3 6.5-4.3 6.5-7.9V6.8L12 4.2ZM9.4 12.1l1.9 1.9 3.4-3.9',
  conector:    'M10.2 13.8 7.4 16.6a3.4 3.4 0 0 1-4.8-4.8l2.8-2.8M13.8 10.2l2.8-2.8a3.4 3.4 0 0 1 4.8 4.8l-2.8 2.8M9.2 14.8l5.6-5.6',
  eventos:     'M12 13.6a1.6 1.6 0 1 0 0-3.2 1.6 1.6 0 0 0 0 3.2ZM8.1 8.1a5.5 5.5 0 0 0 0 7.8M15.9 15.9a5.5 5.5 0 0 0 0-7.8M5.3 5.3a9.5 9.5 0 0 0 0 13.4M18.7 18.7a9.5 9.5 0 0 0 0-13.4',
  servidor:    'M4.5 5h15v5.5h-15zM4.5 13.5h15V19h-15zM7.5 7.8h.01M7.5 16.3h.01',
  externo:     'M12 20a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM4 12h16M12 4c2.1 2.3 3.2 5 3.2 8s-1.1 5.7-3.2 8c-2.1-2.3-3.2-5-3.2-8s1.1-5.7 3.2-8Z',
  analitica:   'M5 19V11M9.7 19V6M14.3 19v-5.5M19 19V8.5',
  integracion: 'M4 8.5h11.5M12.5 5.5 15.5 8.5 12.5 11.5M20 15.5H8.5M11.5 12.5 8.5 15.5l3 3',
  documento:   'M7 4.5h7l4 4V19.5H7ZM14 4.5v4h4M9.5 12.5h6M9.5 15.5h6',
});

/**
 * Familia de glifo por tipo de nodo o de paso.
 *
 * Un tipo sin entrada cae en `servicio`, que es el genérico honesto: una caja
 * con engranaje dice "es un servicio" sin afirmar de qué clase.
 */
export const FAMILIA = Object.freeze({
  user: 'usuario', client: 'usuario',
  fiori: 'navegador', 'work-zone': 'navegador', bas: 'navegador',
  cap: 'servicio', 'cf-runtime': 'servicio', kyma: 'servicio', 'abap-cloud': 'servicio',
  's4-cloud': 'servicio', 'process-call': 'servicio', script: 'servicio',
  hana: 'base', database: 'base', persist: 'base',
  ias: 'seguridad', xsuaa: 'seguridad', 'audit-log': 'seguridad',
  'cloud-connector': 'conector', connectivity: 'conector', destination: 'conector',
  'private-link': 'conector',
  'event-mesh': 'eventos', 'job-scheduler': 'eventos', timer: 'eventos',
  's4-onprem': 'servidor', ecc: 'servidor', bw: 'servidor',
  'sender-system': 'servidor', 'receiver-system': 'servidor',
  external: 'externo', 'external-system': 'externo',
  sac: 'analitica',
  'integration-suite': 'integracion', iflow: 'integracion', 'api-management': 'integracion',
  mapping: 'integracion', router: 'integracion', converter: 'integracion',
  dms: 'documento', 'content-modifier': 'documento',
});

export function familiaDe(tipo) {
  return FAMILIA[tipo] || 'servicio';
}

/** SVG standalone del glifo, para embeber como data URI en draw.io. */
export function svgDeFamilia(familia, color = '#1D2D3E') {
  const d = GLYPHS[familia] || GLYPHS.servicio;
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
    + `<path d="${d}" fill="none" stroke="${color}" stroke-width="1.6" `
    + 'stroke-linecap="round" stroke-linejoin="round"/></svg>';
}

/** Solo el `path`, para inlinear dentro del SVG que ya estamos emitiendo. */
export function pathDeFamilia(familia) {
  return GLYPHS[familia] || GLYPHS.servicio;
}
