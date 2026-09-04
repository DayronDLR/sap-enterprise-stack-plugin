// Acceso a la librería de iconos SAP BTP.
//
// `sap-btp-icons/extracted-icons.json` es un asset propietario de SAP y NO se
// redistribuye con el stack (ver NOTICE). Todo el motor tiene que funcionar sin
// él: cuando falta, los nodos salen como cajas rotuladas con el mismo color y
// la misma geometría. El diagrama sigue siendo correcto; pierde el pictograma.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { familiaDe, pathDeFamilia, svgDeFamilia } from '../assets/fallback-icons.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

const CANDIDATES = [
  process.env.SAP_BTP_ICONS,
  path.resolve(HERE, '../../../agents/11-documentation/sap-btp-icons/extracted-icons.json'),
  path.resolve(HERE, '../assets/extracted-icons.json'),
  path.resolve(process.cwd(), 'agents/11-documentation/sap-btp-icons/extracted-icons.json'),
].filter(Boolean);

let cache = null;

/** Mapa clave→base64 del SVG. `{}` si la librería no está disponible. */
export function iconLibrary() {
  if (cache) return cache;
  for (const file of CANDIDATES) {
    try {
      if (fs.existsSync(file)) {
        cache = JSON.parse(fs.readFileSync(file, 'utf8'));
        return cache;
      }
    } catch {
      // Un JSON corrupto no puede tumbar el render: se degrada a sin iconos.
    }
  }
  cache = {};
  return cache;
}

export function iconBase64(key) {
  if (!key) return null;
  const entry = iconLibrary()[key];
  return entry?.svg_base64 || null;
}

export function iconsAvailable() {
  return Object.keys(iconLibrary()).length > 0;
}

/**
 * Glifo propio para un tipo, cuando la librería SAP no está o no cubre ese tipo.
 *
 * No reemplaza al icono oficial: solo evita que un consumidor del plugin público
 * reciba una lámina de cajas vacías mientras el stack interno entrega la misma
 * lámina con pictogramas. Dos calidades de entregable según quién lo corra era
 * el problema real.
 */
export function fallbackPath(tipo) {
  return pathDeFamilia(familiaDe(tipo));
}

export function fallbackSvgBase64(tipo, color) {
  return Buffer.from(svgDeFamilia(familiaDe(tipo), color), 'utf8').toString('base64');
}
