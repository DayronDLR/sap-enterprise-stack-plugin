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
 * o `{ malas: ['<sha12> <ruta>', ...] }`, una por ruta, en el commit MÁS VIEJO
 * del rango que la tiene. Si ese commit ya la heredó de su padre, se dice: el
 * autor de la rama no la agregó, y lo que hay que limpiar es la base.
 */
export function entradasEnRango(git, rango) {
  const rl = git('rev-list', '--reverse', '--parents', rango);
  if (rl.status !== 0) return { error: `no se pudo resolver el rango ${rango}: ${(rl.stderr || '').trim()}` };
  const commits = rl.stdout.trim().split('\n').filter(Boolean).map((l) => l.split(' '));
  const enRango = new Set(commits.map(([sha]) => sha));

  // Un árbol por commit, una sola vez: los padres de fuera del rango se
  // consultan para cada ruta marcada, y sin caché eran dos procesos git por ruta.
  const arboles = new Map();
  const arbolDe = (sha) => {
    if (!arboles.has(sha)) {
      const lt = git('-c', 'core.quotePath=false', 'ls-tree', '-r', '-z', '--name-only', sha);
      if (lt.status !== 0) throw new Error(`no se pudo listar el árbol de ${sha.slice(0, 12)}: ${(lt.stderr || '').trim()}`);
      arboles.set(sha, new Set(lt.stdout.split('\0').filter(Boolean)));
    }
    return arboles.get(sha);
  };
  const prohibidaEn = (arbol, r) => entradasProhibidas([r], (rel) => arbol.has(rel)).length === 1;

  // Heredada = ALGÚN padre de fuera del rango ya la tenía prohibida: con la
  // ruta Y con su ancla. Mirar sólo el primer padre fallaba en un merge que la
  // trae por el segundo; mirar sólo la ruta, cuando la base tenía el archivo sin
  // `estado.json` y es la rama la que agrega el ancla.
  const heredada = (padres, r) => padres.some((p) => !enRango.has(p) && prohibidaEn(arbolDe(p), r));

  const malas = [];
  const vistas = new Set();
  try {
    for (const [sha, ...padres] of commits) {
      const arbol = arbolDe(sha);
      const rutas = [...arbol].filter((r) => /(^|\/)entradas\//.test(r) && !vistas.has(r));
      for (const r of entradasProhibidas(rutas, (rel) => arbol.has(rel))) {
        vistas.add(r);
        malas.push(`${sha.slice(0, 12)} ${r}${heredada(padres, r) ? ' (heredada: ya estaba antes del rango)' : ''}`);
      }
      arboles.delete(sha);  // ya no se necesita: sólo se reconsultan padres de fuera del rango
    }
  } catch (e) {
    return { error: e.message };
  }
  return { malas };
}
