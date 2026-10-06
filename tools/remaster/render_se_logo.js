// JXA: draw the Square Enix logo as vector shapes (traced from the reference the user supplied, 2000x1333 artboard)
// in white with red bars on a transparent ground, so it sits on the movie's black background.
// usage: osascript -l JavaScript render_se_logo.js <out.png> <width_px>
ObjC.import('AppKit');
const X0 = 231, Y0 = 587, LW = 1538, LH = 159;   // logo bounds on the reference artboard (Q tail reaches y=746)
const S = [[235,587,22],[378,587,18],[378,622,0],[350,622,0],[350,610,0],[261,610,0],[261,642,0],[380,642,22],[380,727,22],
           [231,727,22],[231,701,0],[354,701,0],[354,668,0],[235,668,22]];
const Q = [[406,587,22],[553,587,22],[553,727,22],[406,727,22]], QH = [[436,610,0],[521,610,0],[521,701,0],[436,701,0]], QT = [[463,687,0],[494,687,0],[494,746,0],[463,746,0]];
const U = [[578,587,0],[609,587,0],[609,701,0],[685,701,0],[685,587,0],[716,587,0],[716,727,22],[578,727,22]];
const A = [[722,727,0],[794,587,0],[823,587,0],[895,727,0],[864,727,0],[849,697,0],[768,697,0],[753,727,0]], AH = [[808,619,0],[836,672,0],[780,672,0]];
const R = [[909,587,0],[1040,587,22],[1040,675,22],[1001,675,0],[1052,727,0],[1012,727,0],[960,675,0],[940,675,0],[940,727,0],[909,727,0]],
      RH = [[940,610,0],[1010,610,6],[1010,650,6],[940,650,0]];
const E = (x) => [[x,587,0],[x+119,587,0],[x+119,610,0],[x+31,610,0],[x+31,701,0],[x+119,701,0],[x+119,727,0],[x,727,0]];
const EBAR = (x) => [[x+57,642,0],[x+109,642,0],[x+109,668,0],[x+57,668,0]];
const N = [[1397,587,0],[1420,587,0],[1500,681,0],[1500,587,0],[1531,587,0],[1531,727,0],[1510,727,0],[1426,628,0],[1426,727,0],[1397,727,0]];
const I = [[1556,587,0],[1588,587,0],[1588,727,0],[1556,727,0]];
const XX = [[1605,587,0],[1642,587,0],[1685,633,0],[1724,587,0],[1761,587,0],[1704,655,0],[1769,727,0],[1732,727,0],[1686,676,0],[1641,727,0],[1604,727,0],[1666,655,0]];
function run(argv) {
  const out = argv[0], W = parseInt(argv[1]); const k = W / LW, H = Math.ceil(LH * k), pad = Math.ceil(8 * k);
  const pt = (x, y) => $.NSMakePoint(pad + (x - X0) * k, pad + H - (y - Y0) * k);   // flip: artboard y grows down
  const poly = (path, P) => {   // closed polygon with an optional rounding radius per vertex
    const n = P.length, mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    const m = mid(P[n - 1], P[0]); path.moveToPoint(pt(m[0], m[1]));
    for (let i = 0; i < n; i++) { const v = P[i], w = P[(i + 1) % n];
      if (v[2] > 0) path.appendBezierPathWithArcFromPointToPointRadius(pt(v[0], v[1]), pt(w[0], w[1]), v[2] * k); else path.lineToPoint(pt(v[0], v[1])); }
    path.closePath; };
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, W + 2 * pad, H + 2 * pad, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
  $.NSGraphicsContext.saveGraphicsState;
  const g = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep); g.shouldAntialias = true; $.NSGraphicsContext.setCurrentContext(g);
  const fill = (shapes, color, evenOdd) => { const p = $.NSBezierPath.bezierPath; shapes.forEach((s) => poly(p, s));
    if (evenOdd) p.windingRule = $.NSWindingRuleEvenOdd; color.setFill; p.fill; };
  const white = $.NSColor.colorWithSRGBRedGreenBlueAlpha(1, 1, 1, 1), red = $.NSColor.colorWithSRGBRedGreenBlueAlpha(230 / 255, 0, 18 / 255, 1);
  fill([S], white); fill([Q, QH], white, true); fill([QT], white); fill([U], white); fill([A, AH], white, true);
  fill([R, RH], white, true); fill([E(1068)], white); fill([E(1253)], white); fill([N], white); fill([I], white); fill([XX], white);
  fill([EBAR(1068), EBAR(1253)], red);
  $.NSGraphicsContext.restoreGraphicsState;
  rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({})).writeToFileAtomically($(out), true);
  return `${W + 2 * pad}x${H + 2 * pad}`;
}
