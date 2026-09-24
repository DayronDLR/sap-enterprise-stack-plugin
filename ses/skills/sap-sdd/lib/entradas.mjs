/**
 * La regla de «esto es documentación de un cliente y no entra a un repo»
 * (ADR-014 §3), en UN solo lugar.
 *
 * La usan dos consumidores: el Gate 1 local (via `sdd vigilar-entradas`, sobre
 * el disco) y `ses gates --ci` (commit por commit, sobre git). Una regla escrita
 * dos veces diverge; ya pasó con el trailer de la DoD.
 *
 * Una ruta es una entrada protegida si alguno de sus ancestros se llama
 * `entradas` y el directorio que lo contiene es un proyecto SDD: tiene
 * `estado.json`. Sin ese ancla, cualquier carpeta llamada `entradas` en el repo
 * de un cliente bloquearía commits que no tienen nada que ver.
 */

/**
 * Los directorios de proyecto candidatos de una ruta: el padre de cada segmento
 * `entradas` que tenga algo debajo. `''` es la raíz del repo.
 */
export function proyectosCandidatos(ruta) {
  const partes = ruta.split('/');
  const out = [];
  for (let i = 0; i < partes.length - 1; i += 1) {
    if (partes[i] === 'entradas') out.push(partes.slice(0, i).join('/'));
  }
  return out;
}

/**
 * Las rutas de `rutas` que son entradas de un proyecto SDD. `existe(rel)` dice
 * si un archivo existe en el árbol que se evalúa: el disco en local, un commit
 * en CI.
 */
export function entradasProhibidas(rutas, existe) {
  return rutas.filter((r) => proyectosCandidatos(r)
    .some((d) => existe(d ? `${d}/estado.json` : 'estado.json')));
}

/**
 * La misma regla sobre un rango de git: se evalúa el ÁRBOL COMPLETO de cada
 * commit, no su diff.
 *
 * Con el diff se escapaban dos casos, medidos por los gates:
 *   - un MERGE: `diff-tree` no lista nada para un merge commit, así que un
 *     documento agregado al resolver un conflicto pasaba;
 *   - el ORDEN: con `entradas/` en un commit y el `estado.json` que la ancla en
 *     el siguiente, ningún commit tenía las dos cosas en su diff.
 * Mirando el árbol de cada commit los dos desaparecen, y también el
 * add-and-revert: el commit que la agregó la tiene en su árbol aunque el
 * siguiente la borre. Un rename o una copia son lo mismo que agregar.
 *
 * `git(...args)` devuelve `{ status, stdout, stderr }` (el de `spawnSync`); se
 * inyecta para no depender de dónde está el binario ni del repo.
 *
 * Devuelve `{ error }` si git falló —falla cerrado: sin rango no hay veredicto—
 * o `{ malas: ['<sha12> <ruta>', ...] }`, una por ruta: la primera vez que
 * aparece en el recorrido.
 */
export function entradasEnRango(git, rango) {
  const rl = git('rev-list', rango);
  if (rl.status !== 0) return { error: `no se pudo resolver el rango ${rango}: ${(rl.stderr || '').trim()}` };
  const malas = [];
  const vistas = new Set();
  for (const sha of rl.stdout.trim().split('\n').filter(Boolean)) {
    // `-z` ya evita que git cite los nombres, y `core.quotePath=false` lo deja
    // explícito: un `entradas/cotización.pdf` citado dejaría de matchear.
    const lt = git('-c', 'core.quotePath=false', 'ls-tree', '-r', '-z', '--name-only', sha);
    if (lt.status !== 0) return { error: `no se pudo listar el árbol de ${sha.slice(0, 12)}: ${(lt.stderr || '').trim()}` };
    const arbol = new Set(lt.stdout.split('\0').filter(Boolean));
    const rutas = [...arbol].filter((r) => /(^|\/)entradas\//.test(r) && !vistas.has(r));
    for (const r of entradasProhibidas(rutas, (rel) => arbol.has(rel))) {
      vistas.add(r);
      malas.push(`${sha.slice(0, 12)} ${r}`);
    }
  }
  return { malas };
}
