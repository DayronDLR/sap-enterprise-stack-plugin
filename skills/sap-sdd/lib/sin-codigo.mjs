/**
 * Código en un artefacto funcional.
 *
 * C1 dice QUÉ necesita el negocio; el CÓMO se decide en C3. Una regla como
 * «RQ-04 El sistema hace SELECT SINGLE sobre KNA1» ya decidió la implementación
 * antes del diseño, y todas las fases que la citan la heredan sin evaluarla.
 *
 * Esta lista es la MISMA que usa el eval de `sap-req` como `must_not_contain`
 * (sin los marcadores de borrador). `tests/unit/eval-vocabulario-antifiltracion.test.js`
 * exige que coincidan: si se agrega una aguja acá, se agrega allá, y al revés.
 *
 * Lo que se prohíbe es el código, no el nombre de la tecnología: «CDS
 * analítico + Fiori», una transacción (FBL5N) o una tabla (BSID) describen el
 * requerimiento sin decidir cómo se programa. Por eso las agujas son formas que
 * sólo aparecen en código: `SELECT SINGLE` y no `SELECT` (que atrapaba
 * `SELECT-OPTIONS`), `CL_SALV_` y no `CL_` (que atrapaba `INCL_`).
 */
export const CODIGO = Object.freeze([
  // Bloques de código cercados (por prefijo: ```js cubre ```javascript).
  '```abap', '```sql', '```js', '```ts', '```json', '```xml', '```cds',
  '```yaml', '```yml', '```java', '```python', '```bash', '```sh', '```groovy',
  // Sentencias ABAP.
  'SELECT SINGLE', 'SELECT *', 'INTO TABLE', 'DATA(', 'LOOP AT', 'ENDLOOP',
  'CALL FUNCTION', 'ENDMETHOD',
  // Clases ABAP.
  'ZCL_', 'CL_SALV_', 'CL_GUI_', 'CL_ABAP_',
  // CDS / RAP.
  'define view', '@AbapCatalog', '@UI.',
  // Endpoints OData.
  '/sap/opu/odata', '$filter',
]);

// Una sola regex en vez de un `includes` por aguja: con 31 agujas y un fs.md de
// 2 MB, buscar aguja por aguja costaba ~8 ms de p95 (lo midió el Gate 3). Las
// alternativas van de la más larga a la más corta: ```js es prefijo de ```json,
// y en la misma posición gana la primera que matchea, así que el mensaje nombra
// lo que de verdad está en la línea.
const escapar = (a) => a.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const RE_CODIGO = new RegExp([...CODIGO].sort((a, b) => b.length - a.length).map(escapar).join('|'));
const RE_CODIGO_G = new RegExp(RE_CODIGO.source, 'g');

// Una URL es una referencia, no código pegado: `https://…/sap/opu/odata/…` o
// un enlace a la documentación de SAP no deciden la implementación.
const RE_URL = /\bhttps?:\/\/\S+/g;

// Un bloque cercado se nombra por su marca completa: ```javascript contiene
// ```java, y el mensaje decía «```java» ante un bloque de JavaScript. Con tope:
// una marca de 1 MB no puede terminar entera en el hallazgo.
const RE_CERCA = /^```[\w+#-]{0,20}/;
const nombreDe = (linea, aguja) => (aguja.startsWith('```') ? RE_CERCA.exec(linea.slice(linea.indexOf(aguja)))[0] : aguja);

/**
 * Las líneas de `texto` que traen código: `[{ linea, aguja }]`, una por línea.
 * La comparación es por subcadena y sensible a mayúsculas, igual que la del eval,
 * salvo que las URLs no cuentan.
 *
 * Lo que va entre backticks SÍ cuenta, al revés que en el chequeo de citas: ahí
 * un backtick muestra un ejemplo de cita; acá `LOOP AT` entre backticks sigue
 * siendo una sentencia en un documento que describe el negocio. Y una regla
 * negativa («no usar SELECT *») también: se escribe en palabras («las lecturas
 * no traen columnas que el proceso no usa»).
 */
export function codigoEn(texto) {
  // Una sola pasada sobre el texto entero, sin partirlo en líneas: se salta de
  // coincidencia en coincidencia y sólo se mira la línea donde cayó cada una.
  // Una captura sin código, que es el caso normal, sale en el primer `exec`.
  // Los saltos de línea se cuentan una vez, avanzando.
  const hallados = [];
  const re = new RegExp(RE_CODIGO_G);
  let linea = 1;
  let contadoHasta = 0;
  for (let m = re.exec(texto); m; m = re.exec(texto)) {
    const ini = texto.lastIndexOf('\n', m.index) + 1;
    const salto = texto.indexOf('\n', m.index);
    const fin = salto === -1 ? texto.length : salto;
    for (let k = texto.indexOf('\n', contadoHasta); k !== -1 && k < ini; k = texto.indexOf('\n', k + 1)) linea += 1;
    contadoHasta = ini;
    // La coincidencia puede estar dentro de una URL: la línea se evalúa sin ellas.
    const l = texto.slice(ini, fin).replace(RE_URL, '');
    const r = RE_CODIGO.exec(l);
    if (r) hallados.push({ linea, aguja: nombreDe(l, r[0]) });
    re.lastIndex = fin + 1;
  }
  return hallados;
}
