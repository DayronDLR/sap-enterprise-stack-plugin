// Validador de JSON Schema — subconjunto acotado, cero dependencias.
//
// Por qué no ajv: el motor tiene que correr con `node` a secas dentro de BAS,
// de Cloud Foundry y del plugin instalado, donde no hay `pnpm install` previo.
// archify resuelve esto compilando ajv a validadores standalone; acá el
// vocabulario de los schemas es tan chico (11 keywords) que sale más barato
// implementarlo que arrastrar el paso de codegen.
//
// Vocabulario soportado: $ref (local y a common.schema.json), type, const, enum,
// required, properties, additionalProperties, items, minItems, maxItems,
// minLength, maxLength, minimum, maximum, pattern.
//
// Cualquier keyword no soportada en un schema es un error del stack, no del
// autor del diagrama: `assertSupportedVocabulary` lo detecta en los tests.

import { diagnostic } from './diagnostics.mjs';

export const SUPPORTED_KEYWORDS = new Set([
  '$schema', '$id', 'title', 'description', '$defs', '$ref',
  'type', 'const', 'enum', 'required', 'properties', 'additionalProperties',
  'items', 'minItems', 'maxItems', 'minLength', 'maxLength',
  'minimum', 'maximum', 'pattern',
]);

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer';
  return typeof value;
}

function typeMatches(expected, value) {
  const actual = typeOf(value);
  if (expected === 'number') return actual === 'number' || actual === 'integer';
  if (expected === 'integer') return actual === 'integer';
  return actual === expected;
}

/** Resuelve `#/$defs/x` y `common.schema.json#/$defs/x` contra el store de schemas. */
function resolveRef(ref, self, store) {
  const [file, pointer] = ref.split('#');
  const root = file ? store[file] : self;
  if (!root) throw new Error(`schema-validator: $ref sin resolver "${ref}"`);
  let node = root;
  for (const raw of (pointer || '').split('/').slice(1)) {
    const seg = raw.replace(/~1/g, '/').replace(/~0/g, '~');
    node = node?.[seg];
  }
  if (!node) throw new Error(`schema-validator: $ref sin resolver "${ref}"`);
  return node;
}

/**
 * Etiqueta un path JSON con la identidad del elemento más cercano
 * (`/nodes/3` → `/nodes/3 (id: "cap-srv")`) para que el fix sea localizable
 * sin contar posiciones de array a mano.
 */
function identityAt(instancePath, data) {
  let node = data;
  let identity = null;
  for (const seg of instancePath.split('/').slice(1)) {
    if (node == null || typeof node !== 'object') break;
    node = node[/^\d+$/.test(seg) ? Number(seg) : seg];
    if (node && typeof node === 'object' && !Array.isArray(node)) {
      const tag = node.id ?? node.label;
      if (tag != null) identity = String(tag);
    }
  }
  return identity;
}

function push(out, { path, keyword, message, evidence, fixes }) {
  out.push({ path, keyword, message, evidence, fixes });
}

// const / enum / type: las keywords que miran el valor en si.
function checkValor(schema, data, path, out) {
  if (schema.const !== undefined && data !== schema.const) {
    push(out, {
      path, keyword: 'const',
      message: `debe ser ${JSON.stringify(schema.const)}`,
      evidence: { expected: schema.const, actual: data },
      fixes: [`fijar ${path} en ${JSON.stringify(schema.const)}`],
    });
    return;
  }

  if (schema.enum && !schema.enum.includes(data)) {
    push(out, {
      path, keyword: 'enum',
      message: `valor no permitido ${JSON.stringify(data)}`,
      evidence: { allowed: schema.enum, actual: data },
      fixes: [`elegir uno de ${JSON.stringify(schema.enum)}`],
    });
    return;
  }

  if (schema.type && !typeMatches(schema.type, data)) {
    push(out, {
      path, keyword: 'type',
      message: `se esperaba ${schema.type} y llegó ${typeOf(data)}`,
      evidence: { expected: schema.type, actual: typeOf(data) },
      fixes: [`usar ${schema.type} en ${path}`],
    });
    return;
  }
}

function checkString(schema, data, path, out) {
  if (typeof data !== 'string') return;
  if (schema.minLength !== undefined && data.length < schema.minLength) {
    push(out, {
      path, keyword: 'minLength',
      message: `necesita al menos ${schema.minLength} carácter(es), tiene ${data.length}`,
      evidence: { limit: schema.minLength, actual: data.length },
      fixes: [`escribir un valor de al menos ${schema.minLength} carácter(es)`],
    });
  }
  if (schema.maxLength !== undefined && data.length > schema.maxLength) {
    push(out, {
      path, keyword: 'maxLength',
      message: `excede ${schema.maxLength} caracteres (tiene ${data.length})`,
      evidence: { limit: schema.maxLength, actual: data.length },
      fixes: [
        `acortar el texto a ${schema.maxLength} caracteres conservando el significado`,
        'mover el detalle largo a `sublabel` o a una nota del documento',
      ],
    });
  }
  if (schema.pattern && !new RegExp(schema.pattern).test(data)) {
    push(out, {
      path, keyword: 'pattern',
      message: `no cumple el patrón ${schema.pattern}`,
      evidence: { pattern: schema.pattern, actual: data },
      fixes: [`ajustar el valor al patrón ${schema.pattern} (los id van en minúsculas con guiones)`],
    });
  }
}

function checkNumero(schema, data, path, out) {
  if (typeof data !== 'number') return;
  if (schema.minimum !== undefined && data < schema.minimum) {
    push(out, {
      path, keyword: 'minimum',
      message: `debe ser >= ${schema.minimum}`,
      evidence: { limit: schema.minimum, actual: data },
      fixes: [`usar un valor >= ${schema.minimum}`],
    });
  }
  if (schema.maximum !== undefined && data > schema.maximum) {
    push(out, {
      path, keyword: 'maximum',
      message: `debe ser <= ${schema.maximum}`,
      evidence: { limit: schema.maximum, actual: data },
      fixes: [`usar un valor <= ${schema.maximum}`],
    });
  }
}

function checkArray(schema, data, path, self, store, out) {
  if (!Array.isArray(data)) return;
  if (schema.minItems !== undefined && data.length < schema.minItems) {
    push(out, {
      path, keyword: 'minItems',
      message: `necesita al menos ${schema.minItems} elemento(s), tiene ${data.length}`,
      evidence: { limit: schema.minItems, actual: data.length },
      fixes: [`agregar elementos hasta llegar a ${schema.minItems}`],
    });
  }
  if (schema.maxItems !== undefined && data.length > schema.maxItems) {
    push(out, {
      path, keyword: 'maxItems',
      message: `admite como máximo ${schema.maxItems} elemento(s), tiene ${data.length}`,
      evidence: { limit: schema.maxItems, actual: data.length },
      fixes: [
        `reducir a ${schema.maxItems} elemento(s)`,
        'partir el diagrama en dos niveles (L1 general + L2 de detalle)',
      ],
    });
  }
  if (schema.items) {
    data.forEach((item, i) => walk(schema.items, item, `${path}/${i}`, self, store, out));
  }
}

function checkObjeto(schema, data, path, self, store, out) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return;
  for (const key of schema.required || []) {
    if (!(key in data)) {
      push(out, {
        path, keyword: 'required',
        message: `falta la propiedad obligatoria "${key}"`,
        evidence: { missingProperty: key },
        fixes: [`agregar la propiedad "${key}"`],
      });
    }
  }
  if (schema.additionalProperties === false && schema.properties) {
    for (const key of Object.keys(data)) {
      if (!(key in schema.properties)) {
        push(out, {
          path, keyword: 'additionalProperties',
          message: `propiedad no soportada "${key}"`,
          evidence: { additionalProperty: key, allowed: Object.keys(schema.properties) },
          fixes: [
            `quitar "${key}"`,
            `si buscabas otra cosa, usar una de ${JSON.stringify(Object.keys(schema.properties))}`,
          ],
        });
      }
    }
  }
  for (const [key, sub] of Object.entries(schema.properties || {})) {
    if (key in data) walk(sub, data[key], `${path}/${key}`, self, store, out);
  }
}

function walk(schema, data, path, self, store, out) {
  if (schema.$ref) {
    walk(resolveRef(schema.$ref, self, store), data, path, self, store, out);
    return;
  }

  checkValor(schema, data, path, out);
  checkString(schema, data, path, out);
  checkNumero(schema, data, path, out);
  checkArray(schema, data, path, self, store, out);
  checkObjeto(schema, data, path, self, store, out);
}

/**
 * Valida `data` contra `schema`. Devuelve un array de diagnósticos normalizados
 * (vacío si pasa). Nunca tira: un schema roto sí tira, un dato inválido no.
 */
export function validateAgainstSchema(schema, data, { store = {}, diagramType = 'unknown' } = {}) {
  const raw = [];
  walk(schema, data, '', schema, store, raw);
  return raw.map((e) => {
    const identity = identityAt(e.path, data);
    const where = e.path || '/';
    return diagnostic({
      code: `schema/${e.keyword}`,
      severity: 'error',
      message: `${where}${identity ? ` (id/label: ${JSON.stringify(identity)})` : ''} ${e.message}`,
      subject: { diagramType, path: where, ...(identity ? { identity } : {}) },
      evidence: e.evidence,
      supportedFixes: e.fixes,
    });
  });
}

/** Guarda de mantenimiento: falla si un schema usa vocabulario no implementado. */
export function assertSupportedVocabulary(schema, where = '$') {
  const unknown = [];
  const visitSchema = (node, path) => {
    if (!node || typeof node !== 'object' || Array.isArray(node)) return;
    for (const [key, value] of Object.entries(node)) {
      if (!SUPPORTED_KEYWORDS.has(key)) {
        unknown.push(`${path}/${key}`);
        continue;
      }
      if (key === 'properties' || key === '$defs') {
        for (const [name, sub] of Object.entries(value)) visitSchema(sub, `${path}/${key}/${name}`);
      } else if (key === 'items') {
        visitSchema(value, `${path}/items`);
      }
    }
  };
  visitSchema(schema, where);
  return unknown;
}
