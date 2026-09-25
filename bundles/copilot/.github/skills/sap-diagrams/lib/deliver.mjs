// Entrega con congelamiento y receipt.
//
// `render` sirve para iterar; `deliver` es el único comando que cierra. Congela
// los bytes exactos del spec, renderiza DESDE ese congelado, escribe los
// artefactos de forma atómica y devuelve SHA-256 + bytes de todo.
//
// Por qué importa en un entregable SAP: el .drawio que va al cliente y el PNG
// que va al .docx tienen que ser demostrablemente el mismo diagrama que pasó el
// gate. El receipt es esa prueba, y es reproducible seis meses después.
//
// Idea de artefacto congelado + receipt tomada de archify (MIT, tt-a1i) — ver NOTICE.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

import { renderDiagram } from './render.mjs';
import { detectRasterizer, svgToPng, rasterizerHelp, DEFAULT_PNG_WIDTH } from './emit-png.mjs';

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

/** Escritura atómica: se escribe a un temporal y se renombra. */
function writeAtomic(file, content) {
  const dir = path.dirname(file);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, content);
  fs.renameSync(tmp, file);
  const bytes = Buffer.from(content);
  return { path: file, sha256: sha256(bytes), bytes: bytes.length };
}

/**
 * Entrega los artefactos de un spec ya leído.
 *
 * Una entrega fallida NO toca los artefactos previos: el último bueno sigue en
 * su lugar. Reportar éxito con exit distinto de cero es la única cosa que este
 * módulo no permite hacer.
 */
// Rasteriza el PNG desde el .svg ya escrito. Devuelve el resultado de fallo, o
// `null` si salió bien — el artefacto se agrega a `artifacts` in situ.
function rasterizar({ base, svgPath, formats, pngWidth, rasterizer, artifacts, result }) {
  const png = svgToPng(svgPath, `${base}.png`, { width: pngWidth, tool: rasterizer });
  if (png.ok) {
    artifacts.push({ path: png.path, sha256: sha256(fs.readFileSync(png.path)), bytes: png.bytes });
    if (!formats.includes('svg')) fs.unlinkSync(svgPath);
    return null;
  }
  // El .svg era el intermediario para rasterizar. Si nadie lo pidió como
  // entregable, no puede quedar en disco haciéndose pasar por uno.
  if (!formats.includes('svg')) {
    try { fs.unlinkSync(svgPath); } catch { /* puede no haberse llegado a escribir */ }
  }
  return {
    ok: false,
    stage: 'rasterizer',
    profile: result.profile,
    summary: { errors: 1, warnings: 0 },
    diagnostics: [{
      code: 'output/rasterize-failed',
      severity: 'error',
      message: png.error,
      subject: { format: 'png', tool: png.tool },
      evidence: { source: svgPath },
      supportedFixes: ['instalar otro rasterizador de la lista', 'entregar sin --png y convertir a mano'],
    }],
    artifacts,
    note: `Se escribieron ${artifacts.map((a) => a.path).join(', ') || 'ningún artefacto'}; el PNG no.`,
  };
}

export function deliver(spec, {
  specPath, outBase, profile, formats = ['drawio', 'svg'], pngWidth = DEFAULT_PNG_WIDTH,
  // Inyectable para poder ejercitar el camino "el rasterizador existe y falla",
  // que es justo donde vivía el .svg huérfano y que no se puede provocar de
  // otra forma en una máquina que sí tiene rasterizador.
  rasterizer: injectedRasterizer,
} = {}) {
  // El PNG necesita un rasterizador del sistema. Se comprueba ANTES de escribir
  // nada: media entrega es peor que ninguna, porque el .docx siguiente embebe
  // un PNG viejo sin que nadie note que el diagrama cambió.
  const rasterizer = formats.includes('png') ? (injectedRasterizer || detectRasterizer()) : null;
  if (formats.includes('png') && !rasterizer) {
    return {
      ok: false,
      stage: 'rasterizer',
      profile: profile || spec?.meta?.quality_profile || 'standard',
      summary: { errors: 1, warnings: 0 },
      diagnostics: [{
        code: 'output/no-rasterizer',
        severity: 'error',
        message: 'Se pidió PNG y no hay rasterizador SVG→PNG en el sistema.',
        subject: { format: 'png' },
        evidence: { probed: ['rsvg-convert', 'magick', 'convert', 'cairosvg', 'inkscape', 'chrome'] },
        supportedFixes: rasterizerHelp().split('\n').slice(1).map((l) => l.trim()),
      }],
      artifacts: [],
      note: 'Entrega rechazada: no se escribió ningún artefacto. Los anteriores quedan intactos.',
    };
  }

  const result = renderDiagram(spec, { profile });
  if (!result.ok) {
    return {
      ok: false,
      stage: result.stage,
      profile: result.profile,
      summary: result.summary,
      diagnostics: result.diagnostics,
      artifacts: [],
      note: 'Entrega rechazada: no se escribió ningún artefacto. Los anteriores quedan intactos.',
    };
  }

  const frozenBytes = Buffer.from(`${JSON.stringify(spec, null, 2)}\n`);
  const base = outBase || (specPath ? specPath.replace(/\.sapdiag\.json$/, '') : 'diagram');
  // El congelado es un archivo de trabajo, no un entregable: va oculto y
  // gitignorado. Solo existe para que el render salga de bytes inmutables y
  // para que el receipt sea reproducible.
  const frozenPath = path.join(path.dirname(base), `.${path.basename(base)}.frozen.json`);
  const frozen = writeAtomic(frozenPath, frozenBytes);

  const artifacts = [frozen];
  if (formats.includes('drawio')) artifacts.push(writeAtomic(`${base}.drawio`, result.drawio()));

  // El PNG se rasteriza DESDE el .svg entregado, no desde otro render: así el
  // que va al Word es literalmente el mismo diagrama que el que abre el cliente.
  const svgPath = `${base}.svg`;
  if (formats.includes('svg') || formats.includes('png')) {
    const svgArtifact = writeAtomic(svgPath, result.svg());
    if (formats.includes('svg')) artifacts.push(svgArtifact);
  }
  if (formats.includes('png')) {
    const fallo = rasterizar({ base, svgPath, formats, pngWidth, rasterizer, artifacts, result });
    if (fallo) return fallo;
  }


  return {
    ok: true,
    stage: 'delivered',
    profile: result.profile,
    summary: result.summary,
    diagnostics: result.diagnostics,
    metrics: result.metrics,
    spec: {
      path: specPath || null,
      sha256: sha256(frozenBytes),
      bytes: frozenBytes.length,
    },
    artifacts,
    canvas: result.scene.size,
    rasterizer: rasterizer ? rasterizer.bin : null,
    generatedAt: new Date().toISOString(),
  };
}

export { sha256, writeAtomic };
