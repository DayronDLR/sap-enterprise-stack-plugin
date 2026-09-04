// Sistema visual SAP BTP Solution Diagrams (Horizon 2023).
//
// Los colores salen de agents/11-documentation/sap-btp-diagram-guidelines.md y
// coinciden con los del generador Python histórico, para que un diagrama nuevo
// y uno viejo puedan convivir en el mismo documento sin que se note el corte.

export const COLORS = Object.freeze({
  btpBorder: '#0070F2', btpFill: '#EBF8FF',
  extBorder: '#475E75', extFill: '#F5F6F7',
  titleColor: '#1D2D3E', textColor: '#556B82',
  greenBorder: '#188918', greenFill: '#F5FAE5',
  orangeBorder: '#C35500', orangeFill: '#FFF8D6',
  redBorder: '#D20A0A', redFill: '#FFEAF4',
  tealBorder: '#07838F', tealFill: '#DAFDF5',
  indigoBorder: '#5D36FF', indigoFill: '#F1ECFF',
  pinkBorder: '#CC00DC', pinkFill: '#FFF0FA',
  legendBorder: '#EAECEE', white: '#FFFFFF',
});

/** Color de trazo por semántica de relación. La leyenda se deriva de acá. */
export const EDGE_COLOR = Object.freeze({
  data: COLORS.btpBorder,
  auth: COLORS.greenBorder,
  deploy: COLORS.indigoBorder,
  event: COLORS.pinkBorder,
  access: COLORS.extBorder,
  replication: COLORS.tealBorder,
});

/** Etiqueta por defecto de cada semántica, en la leyenda. */
export const EDGE_LABEL = Object.freeze({
  data: 'Datos / API',
  auth: 'Autenticación',
  deploy: 'Deployment',
  event: 'Eventos',
  access: 'Acceso de usuario',
  replication: 'Replicación',
});

/**
 * Tipo de nodo → icono SAP BTP + paleta.
 *
 * `icon` es la clave en sap-btp-icons/extracted-icons.json. Esa librería es un
 * asset propietario de SAP y NO se distribuye (ver NOTICE): cuando falta, el
 * emisor degrada a caja rotulada con el mismo color. El diagrama sigue siendo
 * correcto, solo pierde el pictograma.
 */
export const NODE_STYLE = Object.freeze({
  user:                { icon: 'user-client-0',           palette: 'ext' },
  client:              { icon: 'user-client-1',           palette: 'ext' },
  fiori:               { icon: 'html5-app-repo',          palette: 'btp' },
  'work-zone':         { icon: 'build-work-zone',         palette: 'btp' },
  bas:                 { icon: 'business-app-studio',     palette: 'btp' },
  cap:                 { icon: 'cap-model',               palette: 'btp' },
  'abap-cloud':        { icon: 'btp-abap',                palette: 'btp' },
  'cf-runtime':        { icon: 'cloud-foundry-runtime',   palette: 'btp' },
  kyma:                { icon: null,                      palette: 'btp' },
  hana:                { icon: 'hana-cloud',              palette: 'btp' },
  sac:                 { icon: 'analytics-cloud',         palette: 'btp' },
  dms:                 { icon: 'document-management',     palette: 'btp' },
  'job-scheduler':     { icon: 'job-scheduling',          palette: 'btp' },
  'event-mesh':        { icon: 'event-mesh',              palette: 'pink' },
  'integration-suite': { icon: null,                      palette: 'btp' },
  iflow:               { icon: null,                      palette: 'btp' },
  'api-management':    { icon: null,                      palette: 'btp' },
  destination:         { icon: 'destination-service',     palette: 'btp' },
  connectivity:        { icon: 'connectivity-service',    palette: 'btp' },
  'cloud-connector':   { icon: 'cloud-connector',         palette: 'orange' },
  'private-link':      { icon: 'private-link',            palette: 'orange' },
  ias:                 { icon: 'identity-authentication', palette: 'green' },
  xsuaa:               { icon: 'authorization-trust',     palette: 'green' },
  'audit-log':         { icon: 'audit-log',               palette: 'green' },
  's4-onprem':         { icon: null,                      palette: 'ext' },
  's4-cloud':          { icon: null,                      palette: 'btp' },
  ecc:                 { icon: null,                      palette: 'ext' },
  bw:                  { icon: null,                      palette: 'ext' },
  external:            { icon: '3rd-party',               palette: 'ext' },
  database:            { icon: null,                      palette: 'ext' },
  note:                { icon: null,                      palette: 'note' },
});

/** Relleno y trazo de cada paleta de nodo. */
export const PALETTE = Object.freeze({
  btp:    { stroke: COLORS.btpBorder,    fill: COLORS.white,       text: COLORS.titleColor },
  ext:    { stroke: COLORS.extBorder,    fill: COLORS.white,       text: COLORS.titleColor },
  green:  { stroke: COLORS.greenBorder,  fill: COLORS.greenFill,   text: COLORS.titleColor },
  orange: { stroke: COLORS.orangeBorder, fill: COLORS.orangeFill,  text: COLORS.titleColor },
  pink:   { stroke: COLORS.pinkBorder,   fill: COLORS.pinkFill,    text: COLORS.titleColor },
  red:    { stroke: COLORS.redBorder,    fill: COLORS.redFill,     text: COLORS.titleColor },
  note:   { stroke: COLORS.legendBorder, fill: COLORS.white,       text: COLORS.textColor },
});

/** Marco de cada tipo de zona. */
export const ZONE_STYLE = Object.freeze({
  btp:            { stroke: COLORS.btpBorder, fill: COLORS.btpFill, label: 'SAP BTP' },
  subaccount:     { stroke: COLORS.extBorder, fill: COLORS.white,   label: 'Subaccount' },
  'service-area': { stroke: COLORS.btpBorder, fill: COLORS.white,   label: '' },
  onpremise:      { stroke: COLORS.extBorder, fill: COLORS.extFill, label: 'On-Premise' },
  external:       { stroke: COLORS.extBorder, fill: COLORS.extFill, label: 'External' },
  network:        { stroke: COLORS.extBorder, fill: COLORS.extFill, label: 'NETWORK' },
});

/**
 * Tipo de paso de iFlow → icono + paleta.
 *
 * La Integration Suite no publica una librería de iconos redistribuible, así que
 * los pasos salen como cajas rotuladas con color por familia. El color hace el
 * trabajo que haría el pictograma: se distingue de un vistazo un router de un
 * mapping, y la rama de excepción del camino feliz.
 */
export const STEP_STYLE = Object.freeze({
  start:              { icon: null, palette: 'green' },
  end:                { icon: null, palette: 'green' },
  timer:              { icon: 'job-scheduling', palette: 'green' },
  mapping:            { icon: null, palette: 'btp' },
  router:             { icon: null, palette: 'orange' },
  splitter:           { icon: null, palette: 'orange' },
  aggregator:         { icon: null, palette: 'orange' },
  gather:             { icon: null, palette: 'orange' },
  script:             { icon: null, palette: 'btp' },
  'request-reply':    { icon: null, palette: 'btp' },
  'content-modifier': { icon: null, palette: 'btp' },
  filter:             { icon: null, palette: 'btp' },
  converter:          { icon: null, palette: 'btp' },
  encoder:            { icon: null, palette: 'btp' },
  persist:            { icon: 'hana-cloud', palette: 'btp' },
  'process-call':     { icon: null, palette: 'btp' },
  'exception-start':  { icon: null, palette: 'red' },
  'external-system':  { icon: '3rd-party', palette: 'ext' },
  'sender-system':    { icon: null, palette: 'ext' },
  'receiver-system':  { icon: null, palette: 'ext' },
});

/** Marco de cada carril de iFlow. */
export const LANE_STYLE = Object.freeze({
  sender:          { stroke: COLORS.extBorder, fill: COLORS.extFill, label: COLORS.titleColor },
  process:         { stroke: COLORS.btpBorder, fill: COLORS.btpFill, label: COLORS.btpBorder },
  'local-process': { stroke: COLORS.btpBorder, fill: COLORS.white, label: COLORS.btpBorder },
  exception:       { stroke: COLORS.redBorder, fill: COLORS.redFill, label: COLORS.redBorder },
  receiver:        { stroke: COLORS.extBorder, fill: COLORS.extFill, label: COLORS.titleColor },
});

export function stepStyle(type) {
  return STEP_STYLE[type] || STEP_STYLE['content-modifier'];
}

export function stepPalette(type) {
  return PALETTE[stepStyle(type).palette] || PALETTE.btp;
}

export function laneStyle(kind) {
  return LANE_STYLE[kind] || LANE_STYLE.process;
}

/**
 * Rol de sistema → color del marco. El landscape se lee por color antes que por
 * texto: verde es donde se desarrolla, ámbar donde se prueba, rojo producción.
 * Si PRD no salta a la vista, el diagrama no está haciendo su trabajo.
 */
export const SYSTEM_ROLE_STYLE = Object.freeze({
  development: { stroke: COLORS.greenBorder,  fill: COLORS.greenFill,  label: 'Desarrollo' },
  quality:     { stroke: COLORS.orangeBorder, fill: COLORS.orangeFill, label: 'Calidad / QAS' },
  production:  { stroke: COLORS.redBorder,    fill: COLORS.redFill,    label: 'Producción' },
  sandbox:     { stroke: COLORS.extBorder,    fill: COLORS.extFill,    label: 'Sandbox' },
  training:    { stroke: COLORS.tealBorder,   fill: COLORS.tealFill,   label: 'Capacitación' },
});

/** Semántica del transporte → color de la flecha. */
export const TRANSPORT_COLOR = Object.freeze({
  workbench:   COLORS.btpBorder,
  customizing: COLORS.indigoBorder,
  gcts:        COLORS.tealBorder,
  'cts-plus':  COLORS.pinkBorder,
  manual:      COLORS.orangeBorder,
});

export const TRANSPORT_LABEL = Object.freeze({
  workbench:   'Workbench (SE09)',
  customizing: 'Customizing (SE10)',
  gcts:        'gCTS',
  'cts-plus':  'CTS+',
  manual:      'Manual / fuera de CTS',
});

export function systemRoleStyle(role) {
  return SYSTEM_ROLE_STYLE[role] || SYSTEM_ROLE_STYLE.sandbox;
}

export function transportColor(kind) {
  return TRANSPORT_COLOR[kind || 'workbench'] || TRANSPORT_COLOR.workbench;
}

export function nodeStyle(type) {
  return NODE_STYLE[type] || NODE_STYLE.external;
}

export function nodePalette(type) {
  return PALETTE[nodeStyle(type).palette] || PALETTE.ext;
}

export function edgeColor(kind) {
  return EDGE_COLOR[kind || 'data'] || EDGE_COLOR.data;
}

/** Color de relación según el tipo de diagrama: un landscape habla de transportes. */
export function relationColor(kind, diagramType) {
  return diagramType === 'landscape' ? transportColor(kind) : edgeColor(kind || 'data');
}

/** Etiqueta por defecto de la leyenda, según el tipo de diagrama. */
export function relationLabel(kind, diagramType) {
  if (diagramType === 'landscape') return TRANSPORT_LABEL[kind] || kind;
  return EDGE_LABEL[kind] || kind;
}

/** Leyenda derivada: solo las semánticas que el diagrama realmente usa. */
export function derivedLegend(edges, override, diagramType) {
  if (Array.isArray(override) && override.length) return override;
  const porDefecto = diagramType === 'landscape' ? 'workbench' : 'data';
  const used = [];
  for (const e of edges || []) {
    const kind = e.kind || porDefecto;
    if (!used.includes(kind)) used.push(kind);
  }
  return used.map((kind) => ({ kind, label: relationLabel(kind, diagramType) }));
}
