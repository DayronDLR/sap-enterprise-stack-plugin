// Escapado XML compartido por los dos emisores.
//
// Estaba duplicado y divergía: el emisor SVG escapaba el apóstrofe y el de
// draw.io no. Hoy no rompe nada porque los atributos usan comillas dobles, pero
// es una trampa esperando a que alguien cambie un delimitador.
//
// Hay DOS funciones y la diferencia importa:
//
//   escapeXml      → texto que el consumidor trata como texto (SVG <text>).
//   escapeXmlText  → texto que el consumidor trata como HTML.
//
// draw.io renderiza el atributo `value` de una celda con `html=1` como HTML.
// El parser XML decodifica `&lt;img&gt;` a `<img>` ANTES de que draw.io lo mire,
// así que un solo escape deja pasar `<img src=x onerror=...>` desde un label y
// lo ejecuta al abrir el archivo. Por eso el texto de usuario que va a una celda
// HTML se escapa dos veces: primero como HTML, después como XML. El lector ve
// los caracteres literales y el editor no ejecuta nada.

const XML = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' };

/** Escapa para un atributo o contenido XML. */
export function escapeXml(text) {
  return String(text ?? '').replace(/[&<>"']/g, (c) => XML[c]);
}

/**
 * Escapa texto de usuario destinado a una celda con `html=1`.
 *
 * Doble pasada a propósito: HTML primero, XML después. El resultado se decodifica
 * a entidades HTML literales, que el editor pinta como texto en vez de ejecutar.
 */
export function escapeXmlText(text) {
  return escapeXml(escapeXml(String(text ?? '')));
}
