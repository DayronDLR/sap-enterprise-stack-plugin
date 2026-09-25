// Ajuste de texto de una sola línea, compartido por los dos emisores.
//
// El fallo que este módulo cierra: un `label` largo se desborda de su caja y
// pisa al vecino, pero el diagrama "valida" igual porque nadie midió el texto.
// Dos mitades que van siempre juntas:
//   - `fittedFontSize` encoge hasta un mínimo legible, así un exceso normal
//     simplemente sale más chico en vez de solaparse;
//   - `minimumTextWidth` reporta el ancho que el texto SIGUE necesitando ya
//     encogido al máximo, para que la validación rechace lo que encoger no salva.
//
// Técnica tomada de archify (MIT, tt-a1i) — ver NOTICE.

/** px de avance por unidad de texto, por px de font-size (Arial ~0.58; 0.6 con margen). */
export const WIDTH_FACTOR = 0.6;
/** px reservados dentro de la caja para que el texto no toque el borde. */
export const HORIZONTAL_PADDING = 10;
/** Por debajo de esto el texto deja de ser legible en un A4 impreso. */
export const MIN_LEGIBLE_PX = 8;

/**
 * Unidades de texto. Las mayúsculas y los dígitos son más anchos que la
 * minúscula media; contarlos igual subestima el ancho justo en las siglas SAP
 * (IDOC, XSUAA, S/4HANA), que es donde más se desborda.
 */
export function textUnits(text) {
  const s = String(text ?? '');
  let units = 0;
  for (const ch of s) {
    if (/[mwMW]/.test(ch)) units += 1.3;
    else if (/[A-Z0-9@#%&]/.test(ch)) units += 1.15;
    else if (/[ilj.,:;'!|]/.test(ch)) units += 0.45;
    else units += 1;
  }
  return units;
}

/** Ancho de texto disponible dentro de una caja de `width` px. */
export function availableTextWidth(width) {
  return Math.max(1, width - HORIZONTAL_PADDING);
}

/** Ancho que ocupa `text` a `fontPx`. */
export function textWidth(text, fontPx) {
  return textUnits(text) * fontPx * WIDTH_FACTOR;
}

/** Mayor font-size <= `preferred` con el que `text` entra en `width`, con piso en `minimum`. */
export function fittedFontSize(text, width, preferred, minimum = MIN_LEGIBLE_PX) {
  const units = Math.max(1, textUnits(text));
  const available = availableTextWidth(width);
  const fitted = Math.min(preferred, available / (units * WIDTH_FACTOR));
  return Math.max(minimum, Math.floor(fitted * 10) / 10);
}

/** Ancho que `text` sigue necesitando ya encogido a `minimum`. */
export function minimumTextWidth(text, minimum = MIN_LEGIBLE_PX) {
  return textWidth(text, minimum);
}

/** true si ni encogiendo al mínimo legible el texto entra en `width`. */
export function overflowsEvenShrunk(text, width, minimum = MIN_LEGIBLE_PX) {
  return minimumTextWidth(text, minimum) > availableTextWidth(width);
}

/** Ancho de caja necesario para `text` a `fontPx`, redondeado a múltiplo de 10. */
export function requiredBoxWidth(text, fontPx) {
  return Math.ceil((textWidth(text, fontPx) + HORIZONTAL_PADDING) / 10) * 10;
}
