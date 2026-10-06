// JXA + Core Image: replace the SquareSoft logo (frames 10-59 of the 4K opening movie) with the Square Enix logo (render_se_logo.js).
// usage: osascript -l JavaScript swap_logo.js <jpg4k_dir> <out_dir> <logo.png> <logo_width_px> [first last [no_logo_from fade_frames]]
// no_logo_from: frames from this index on carry no logo; fade_frames: also write fade_NN.jpg (logo alone on black, fading out).
// Frames 10-31: the original's wave spells SQUARESOFT, so frame 9's plain line of light is held and the logo unfolds
// vertically out of it with a blue glow while the line fades (no frame with SquareSoft letters is used).
// Frames 32-59: SquareSoft's letters (mask from frame 35, dilated) are blacked out and the wordmark is drawn at the original's
// brightness (band luminance relative to frame 35), so it fades with the star exactly as the original logo did.
ObjC.import('AppKit'); ObjC.import('CoreImage');
const S = 2160 / 224;                      // source (320x224) -> 4K scale
const LOGO_CY = 2160 - 107.5 * S;          // logo centre, Core Image coordinates (origin bottom-left)
function img(p) { return $.CIImage.imageWithContentsOfURL($.NSURL.fileURLWithPath(p)); }
function f(name, params) { const x = $.CIFilter.filterWithName(name); x.setDefaults; for (const k in params) x.setValueForKey(params[k], k); return x.outputImage; }
function vec(a, b, c, d) { return $.CIVector.vectorWithXYZW(a, b, c, d); }
function run(argv) {
  const [src, out, logoPath, logoW] = argv; const first = parseInt(argv[4] || 10), last = parseInt(argv[5] || 59);
  const noLogoFrom = parseInt(argv[6] || 9999), fadeN = parseInt(argv[7] || 0);
  const ctx = $.CIContext.contextWithOptions($());
  const fr = (i) => img(`${src}/f${String(i).padStart(4, '0')}.jpg`);
  const ext = fr(35).extent; const W = ext.size.width, H = ext.size.height;
  // wordmark, scaled to logoW and centred on the old logo
  let logo = img(logoPath); const ls = parseFloat(logoW) / logo.extent.size.width;
  logo = logo.imageByApplyingTransform($.CGAffineTransformMakeScale(ls, ls));
  logo = logo.imageByApplyingTransform($.CGAffineTransformMakeTranslation(W / 2 - logo.extent.size.width / 2 - logo.extent.origin.x, LOGO_CY - logo.extent.size.height / 2 - logo.extent.origin.y));
  const glowBase = f('CIGaussianBlur', { inputImage: f('CIColorMatrix', { inputImage: logo, inputRVector: vec(0.35, 0, 0, 0), inputGVector: vec(0, 0.5, 0, 0), inputBVector: vec(0, 0, 1, 0) }), inputRadius: $(28) });
  // text mask: bright pixels of frame 35 inside the logo band, dilated
  const band = $.CGRectMake(20 * S, H - 124 * S, 280 * S, 32 * S);
  const lum = f('CIColorMatrix', { inputImage: fr(35), inputRVector: vec(0.33, 0.33, 0.33, 0), inputGVector: vec(0.33, 0.33, 0.33, 0), inputBVector: vec(0.33, 0.33, 0.33, 0) });
  const textMask = (lumImg) => {
    let m = f('CIColorThreshold', { inputImage: lumImg, inputThreshold: $(0.035) }).imageByCroppingToRect(band);
    m = f('CIMorphologyMaximum', { inputImage: m, inputRadius: $(24) });
    return f('CIGaussianBlur', { inputImage: m, inputRadius: $(4) }).imageByCroppingToRect(ext); };
  const mask = textMask(lum);
  const black = $.CIImage.imageWithColor($.CIColor.colorWithRedGreenBlue(0, 0, 0)).imageByCroppingToRect(ext);
  // per-frame brightness of the old logo band, relative to frame 35 (drives the fade-out)
  const cs = fr(35).colorSpace; const log = [];
  const ref = bandLevel(ctx, fr(35), S, H);
  for (let i = first; i <= last; i++) {
    let base = fr(i), a, unfold = 1;
    if (i <= 31) {
      // the original's wave spells SQUARESOFT from frame 11 on: keep frame 9's plain line of light and unfold the logo out of it
      const t = (i - 9) / 22, e = 1 - Math.pow(1 - Math.min(1, t / 0.7), 3);      // ease-out over the first 70%
      a = Math.min(1, 3 * t); unfold = Math.max(0.02, e);
      const lineA = 1 - Math.max(0, (t - 0.45) / 0.55);
      const ln = f('CIColorMatrix', { inputImage: fr(9), inputRVector: vec(lineA, 0, 0, 0), inputGVector: vec(0, lineA, 0, 0), inputBVector: vec(0, 0, lineA, 0) });
      base = f('CISourceOverCompositing', { inputImage: ln, inputBackgroundImage: black }).imageByCroppingToRect(ext);
    } else {
      a = i >= noLogoFrom ? 0 : Math.min(1, bandLevel(ctx, base, S, H) / ref);
      // the SquareSoft letters drift ~3 source px after frame 41 (as the star appears): logo-free frames mask their own letters
      const m = i >= noLogoFrom ? f('CIMaximumCompositing', { inputImage: textMask(f('CIColorMatrix', { inputImage: base, inputRVector: vec(0.33, 0.33, 0.33, 0), inputGVector: vec(0.33, 0.33, 0.33, 0), inputBVector: vec(0.33, 0.33, 0.33, 0) })), inputBackgroundImage: mask }) : mask;
      // 32 up to the fade: plain black behind the logo (the original's rainbow halo and orange ring flash at 37-41 popped up around it)
      base = i < noLogoFrom ? black : f('CIBlendWithMask', { inputImage: black, inputBackgroundImage: base, inputMaskImage: m });
      if (i >= noLogoFrom) base = f('CIBlendWithMask', { inputImage: black, inputBackgroundImage: base, inputMaskImage: m });   // mask peaks ~0.985: twice leaves 0
    }
    const glowA = a * 0.45;   // steady: the glow only follows the logo's own opacity
    const uf = $.CGAffineTransformMake(1, 0, 0, unfold, 0, LOGO_CY * (1 - unfold));
    const glow = f('CIColorMatrix', { inputImage: glowBase.imageByApplyingTransform(uf), inputRVector: vec(glowA, 0, 0, 0), inputGVector: vec(0, glowA, 0, 0), inputBVector: vec(0, 0, glowA, 0), inputAVector: vec(0, 0, 0, glowA) });
    const lg = f('CIColorMatrix', { inputImage: logo.imageByApplyingTransform(uf), inputAVector: vec(0, 0, 0, a) });
    let o = f('CIAdditionCompositing', { inputImage: glow, inputBackgroundImage: base });
    o = f('CISourceOverCompositing', { inputImage: lg, inputBackgroundImage: o }).imageByCroppingToRect(ext);
    const url = $.NSURL.fileURLWithPath(`${out}/f${String(i).padStart(4, '0')}.jpg`);
    ctx.writeJPEGRepresentationOfImageToURLColorSpaceOptionsError(o, url, cs, $({ 'kCGImageDestinationLossyCompressionQuality': 0.92 }), null);
    log.push(`${i}:${a.toFixed(2)}`);
  }
  for (let k = 1; k <= fadeN; k++) {
    const a = Math.pow(1 - k / fadeN, 1.6);
    const glow = f('CIColorMatrix', { inputImage: glowBase, inputRVector: vec(a * 0.45, 0, 0, 0), inputGVector: vec(0, a * 0.45, 0, 0), inputBVector: vec(0, 0, a * 0.45, 0), inputAVector: vec(0, 0, 0, a * 0.45) });
    let o = f('CIAdditionCompositing', { inputImage: glow, inputBackgroundImage: black });
    o = f('CISourceOverCompositing', { inputImage: f('CIColorMatrix', { inputImage: logo, inputAVector: vec(0, 0, 0, a) }), inputBackgroundImage: o }).imageByCroppingToRect(ext);
    ctx.writeJPEGRepresentationOfImageToURLColorSpaceOptionsError(o, $.NSURL.fileURLWithPath(`${out}/fade_${String(k).padStart(2, '0')}.jpg`), cs, $({ 'kCGImageDestinationLossyCompressionQuality': 0.92 }), null);
    log.push(`fade${k}:${a.toFixed(2)}`);
  }
  return log.join(' ');
}
function bandLevel(ctx, im, S, H) {
  // mean luminance (0..1) of the old logo's box, via a 1x1 render of CIAreaAverage
  const a = f('CIAreaAverage', { inputImage: im, inputExtent: $.CIVector.vectorWithCGRect($.CGRectMake(33 * S, H - 119 * S, 254 * S, 23 * S)) });
  const rep = $.NSBitmapImageRep.alloc.initWithCIImage(a.imageByCroppingToRect($.CGRectMake(0, 0, 1, 1)));
  const c = rep.colorAtXY(0, 0); return (c.redComponent + c.greenComponent + c.blueComponent) / 3;
}
