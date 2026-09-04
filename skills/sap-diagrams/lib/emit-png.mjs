// Rasterizado SVG → PNG para el .docx / .pptx.
//
// pandoc no embebe SVG en un .docx sin un rasterizador externo, así que el paso
// se hace acá y de forma explícita: el documento lleva un PNG del que se sabe
// de dónde salió, no una conversión implícita que falla en silencio en la
// máquina de otro.
//
// El motor NO trae rasterizador propio — sería arrastrar un binario de ~50MB al
// plugin. Usa el primero disponible del sistema, con el mismo criterio que el
// resto del stack: si no hay toolchain, se omite y se dice; no se inventa un
// fallo ni se entrega un documento con un hueco.
//
// `qlmanage` (macOS) queda deliberadamente afuera: recorta a lienzo cuadrado y
// deforma el diagrama. Sirve para previsualizar, no para un entregable.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

/** Ancho por defecto: entra nítido en un A4 apaisado a 150 dpi. */
export const DEFAULT_PNG_WIDTH = 1600;

/** Rutas donde suele vivir Chrome/Chromium, que casi siempre está y renderiza SVG fiel. */
const CHROME_PATHS = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);

/** Dimensiones intrínsecas del SVG que emite este motor. */
export function svgSize(svgPath) {
  // Un SVG ilegible no puede tumbar el pipeline con una excepción: el caller
  // tiene que poder devolver un diagnóstico como con cualquier otro fallo.
  let head;
  try {
    head = fs.readFileSync(svgPath, 'utf8').slice(0, 2048);
  } catch {
    return null;
  }
  const m = head.match(/<svg\b[^>]*\bwidth="(\d+(?:\.\d+)?)"[^>]*\bheight="(\d+(?:\.\d+)?)"/);
  return m ? { width: Number(m[1]), height: Number(m[2]) } : null;
}

const CANDIDATES = [
  {
    bin: 'rsvg-convert',
    install: 'brew install librsvg · apt install librsvg2-bin',
    args: (svg, png, w) => ['-w', String(w), '-f', 'png', '-o', png, svg],
  },
  {
    bin: 'magick',
    install: 'brew install imagemagick · apt install imagemagick',
    args: (svg, png, w) => ['-background', 'white', '-density', '150', svg, '-resize', `${w}x`, png],
  },
  {
    bin: 'convert',
    install: 'brew install imagemagick · apt install imagemagick',
    args: (svg, png, w) => ['-background', 'white', '-density', '150', svg, '-resize', `${w}x`, png],
  },
  {
    bin: 'cairosvg',
    install: 'pip install cairosvg',
    args: (svg, png, w) => [svg, '-o', png, '--output-width', String(w)],
  },
  {
    bin: 'inkscape',
    install: 'brew install inkscape · apt install inkscape',
    args: (svg, png, w) => [svg, '--export-type=png', `--export-filename=${png}`, `--export-width=${w}`],
  },
  {
    // Chrome NO escala el SVG para llenar la ventana: lo dibuja a su tamaño
    // intrínseco. Así que la ventana va al tamaño del SVG y el aumento se pide
    // por device-scale-factor. Al revés queda el diagrama chico en una banda
    // blanca, que es exactamente lo que no se quiere en un .docx.
    bin: 'chrome',
    install: 'Google Chrome o Chromium ya instalado (o CHROME_PATH=/ruta/al/binario)',
    resolve: () => CHROME_PATHS.find((p) => { try { return fs.statSync(p).isFile(); } catch { return false; } }),
    args: (svg, png, w, { svg: intrinsic }) => [
      '--headless', '--disable-gpu', '--hide-scrollbars', '--no-sandbox',
      `--force-device-scale-factor=${(w / intrinsic.width).toFixed(4)}`,
      '--default-background-color=FFFFFFFF',
      `--window-size=${Math.round(intrinsic.width)},${Math.round(intrinsic.height)}`,
      `--screenshot=${png}`,
      `file://${path.resolve(svg)}`,
    ],
  },
];

/** ¿Está el binario en el PATH? Sin shell: un ENOENT es la respuesta. */
function resolveBin(candidate) {
  if (candidate.resolve) return candidate.resolve() || null;
  const probe = spawnSync(candidate.bin, ['--version'], { encoding: 'utf8' });
  return probe.error ? null : candidate.bin;
}

/** Primer rasterizador disponible, o null. */
export function detectRasterizer() {
  for (const candidate of CANDIDATES) {
    const bin = resolveBin(candidate);
    if (bin) return { ...candidate, resolved: bin };
  }
  return null;
}

/** Texto de ayuda cuando no hay ninguno instalado. */
export function rasterizerHelp() {
  return ['Ningún rasterizador SVG→PNG disponible. Instalá uno:',
    ...CANDIDATES.map((c) => `  ${c.bin.padEnd(14)} ${c.install}`)].join('\n');
}

/**
 * Convierte `svgPath` a `pngPath`. Escritura atómica: rasteriza a un temporal y
 * renombra, para que un pandoc concurrente nunca embeba un PNG a medio escribir.
 */
export function svgToPng(svgPath, pngPath, { width = DEFAULT_PNG_WIDTH, tool } = {}) {
  const rasterizer = tool || detectRasterizer();
  if (!rasterizer) return { ok: false, tool: null, error: rasterizerHelp() };
  // Sin esto Chrome fotografía su propia página de error y sale con 0: un PNG
  // perfectamente válido de un diagrama que no existe.
  if (!fs.existsSync(svgPath)) {
    return { ok: false, tool: rasterizer.bin, error: `No existe el SVG de origen: ${svgPath}` };
  }

  // Algunos rasterizadores necesitan el tamaño intrínseco del SVG, no solo el
  // ancho de salida. Si no se puede leer, se asume un apaisado razonable.
  const intrinsic = svgSize(svgPath) || { width, height: Math.round(width * 0.62) };
  const height = Math.round((width * intrinsic.height) / intrinsic.width);

  const dir = path.dirname(pngPath);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${path.basename(pngPath)}.${process.pid}.tmp.png`);
  const run = spawnSync(rasterizer.resolved || rasterizer.bin,
    rasterizer.args(svgPath, tmp, width, { height, svg: intrinsic }), { encoding: 'utf8' });

  if (run.error || run.status !== 0 || !fs.existsSync(tmp)) {
    try { fs.unlinkSync(tmp); } catch { /* el temporal puede no existir */ }
    return {
      ok: false,
      tool: rasterizer.bin,
      error: `${rasterizer.bin} falló (exit ${run.status ?? 'n/d'}): `
        + `${(run.stderr || run.stdout || run.error?.message || '').trim().slice(0, 400)}`,
    };
  }
  fs.renameSync(tmp, pngPath);
  return { ok: true, tool: rasterizer.bin, path: pngPath, bytes: fs.statSync(pngPath).size };
}
