/**
 * Qué produce cada fase del ciclo SDD (ADR-014 §1 y §4).
 *
 * Es la whitelist del gate: lo obligatorio tiene que estar y no ser esqueleto,
 * lo opcional puede estar, y cualquier otra cosa en la carpeta de la fase es un
 * artefacto que nadie pidió.
 *
 * `citas` dice qué archivos tienen que citar el requerimiento y con qué rigor:
 *   'por-seccion' → cada sección (`##` / `###` / `####`) con contenido lleva al menos una
 *   'alguna'      → el archivo lleva al menos una
 */
export const CONTRATO = {
  C1: {
    obligatorios: ['requerimiento.md', 'fs.md', 'handoff.md'],
    opcionales: ['gap-analysis.md', 'preguntas.md'],
    citas: { 'fs.md': 'alguna' },
  },
  C2: {
    obligatorios: ['escenarios.md', 'casos-prueba.md', 'handoff.md'],
    opcionales: [],
    citas: { 'escenarios.md': 'por-seccion', 'casos-prueba.md': 'alguna' },
  },
  C3: {
    obligatorios: ['diseno.md', 'arquitectura.sapdiag.json', 'handoff.md'],
    opcionales: ['arquitectura.drawio', 'arquitectura.svg', 'prototipo.html'],
    citas: { 'diseno.md': 'alguna' },
  },
  C4: {
    obligatorios: ['plan.md', 'estimacion.md', 'handoff.md'],
    opcionales: [],
    citas: { 'plan.md': 'alguna' },
  },
};

/** Lo que se cita. Las fases posteriores a C1 citan esto, nunca `entradas/`. */
export const REQUERIMIENTO = 'C1-captura/requerimiento.md';

/**
 * Un artefacto con menos que esto no es un artefacto: es la plantilla, un
 * título suelto o un archivo que el agente creó para cumplir.
 */
export const MINIMO_CARACTERES = 100;

/** Marca explícita de "esto está sin terminar", para plantillas y borradores. */
export const MARCA_PENDIENTE = '<!-- sdd:pendiente -->';

/**
 * Ruido del sistema operativo y temporales propios que no cuentan como
 * artefacto no pedido. El temporal es el de `escribirEntero` (proyecto.mjs):
 * uno de menos de un minuto puede ser de una escritura en curso.
 */
export function esIgnorable(nombre) {
  return nombre === '.DS_Store' || nombre === 'Thumbs.db' || nombre === '.sdd.lock' ||
    /^\..+\.[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.tmp$/.test(nombre);
}
