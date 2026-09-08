// Contrato de diagnóstico del motor de diagramas.
//
// Un diagnóstico no es un mensaje de error: es una instrucción de reparación.
// El agente que autoró el `.sapdiag.json` no ve el SVG — lo único que tiene para
// corregir es este objeto. Por eso los cuatro campos son obligatorios en la
// práctica: `subject` dice DÓNDE, `evidence` dice CUÁNTO falta medido en px, y
// `supportedFixes` acota QUÉ se puede tocar. Sin `supportedFixes` el modelo
// improvisa geometría a mano, que es exactamente el fallo que este motor cierra.
//
// Técnica tomada de archify (MIT, tt-a1i) — ver NOTICE.

/** Severidades ordenadas de mayor a menor gravedad. */
export const SEVERITY = Object.freeze({ ERROR: 'error', WARNING: 'warning' });

function plainObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).filter(([, v]) => v !== undefined));
}

/** Normaliza un diagnóstico crudo al contrato estable que consume el agente. */
export function diagnostic({ code, severity, message, subject, evidence, supportedFixes } = {}) {
  return {
    code: String(code || 'internal/unclassified'),
    severity: severity === SEVERITY.WARNING ? SEVERITY.WARNING : SEVERITY.ERROR,
    message: String(message || 'El motor no pudo clasificar este fallo.').trim(),
    subject: plainObject(subject),
    evidence: plainObject(evidence),
    supportedFixes: Array.isArray(supportedFixes)
      ? [...new Set(supportedFixes.map((f) => String(f).trim()).filter(Boolean))]
      : [],
  };
}

/**
 * Acumulador de diagnósticos. Deduplica por `code + subject` para que una misma
 * causa (un nodo con label largo tocado por tres rutas) no inunde el receipt con
 * variantes del mismo arreglo.
 */
export class DiagnosticBag {
  constructor() {
    this.items = [];
    this._seen = new Set();
  }

  add(raw) {
    const d = diagnostic(raw);
    const key = `${d.code}|${JSON.stringify(d.subject)}`;
    if (this._seen.has(key)) return d;
    this._seen.add(key);
    this.items.push(d);
    return d;
  }

  get errors() {
    return this.items.filter((d) => d.severity === SEVERITY.ERROR);
  }

  get warnings() {
    return this.items.filter((d) => d.severity === SEVERITY.WARNING);
  }

  /** Resumen de conteos: es el número que gobierna el criterio de corte del loop. */
  summary() {
    return { errors: this.errors.length, warnings: this.warnings.length };
  }

  /** Diagnósticos ordenados: errores primero, luego por código. */
  sorted() {
    return [...this.items].sort((a, b) => {
      if (a.severity !== b.severity) return a.severity === SEVERITY.ERROR ? -1 : 1;
      return a.code.localeCompare(b.code) || JSON.stringify(a.subject).localeCompare(JSON.stringify(b.subject));
    });
  }
}

/** Error portador de diagnósticos, para cortar el pipeline sin perder el detalle. */
export class DiagramError extends Error {
  constructor(message, diagnostics = []) {
    super(message);
    this.name = 'DiagramError';
    this.diagnostics = diagnostics.map((d) => diagnostic(d));
  }
}
