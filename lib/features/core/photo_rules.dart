import 'dart:math' as math;
import 'dart:typed_data';

/// What a usable product photograph looks like, and how to tell.
///
/// A port of slk-core's `photo-rules.ts` — the same thresholds and the same
/// sentences, on purpose. A photograph that passes on the phone must pass on
/// the web and the other way round, and a person who sees "Too dark — find
/// more light" here and again there should never wonder whether they are
/// two different rules. **A change to one needs the same change to the
/// other.**
///
/// Every check runs on a small greyscale copy of the frame. Nothing here
/// needs the pixels at full size, and a phone has to run it several times a
/// second while the camera is up.

enum PhotoOrientation { portrait, landscape }

class PhotoRule {
  const PhotoRule({
    required this.orientation,
    required this.minLongSide,
    required this.guide,
  });

  /// Which way the phone is held — the long side runs the way the part does.
  final PhotoOrientation orientation;

  /// The shortest long side the photograph may have, in pixels.
  final int minLongSide;

  /// One line, for the person holding the phone.
  final String guide;
}

const _portraitGuide =
    'Hold the phone upright. Only the cloth in the frame, edge to edge.';

/// Keyed by the words in a slot's label. Master Lists names the slots; this
/// reads the name rather than an id so a renamed slot keeps its rule.
const _rules = <(String, PhotoRule)>[
  (
    'border',
    PhotoRule(
      orientation: PhotoOrientation.landscape,
      minLongSide: 1500,
      guide: 'Turn the phone sideways. The border runs left to right, its '
          'full width in the frame.',
    ),
  ),
  ('body', PhotoRule(orientation: PhotoOrientation.portrait, minLongSide: 1500, guide: _portraitGuide)),
  ('pallu', PhotoRule(orientation: PhotoOrientation.portrait, minLongSide: 1500, guide: _portraitGuide)),
  ('blouse', PhotoRule(orientation: PhotoOrientation.portrait, minLongSide: 1500, guide: _portraitGuide)),
];

const _defaultRule = PhotoRule(
  orientation: PhotoOrientation.portrait,
  minLongSide: 1200,
  guide: _portraitGuide,
);

PhotoRule ruleFor(String slotLabel) {
  final label = slotLabel.toLowerCase();
  for (final (needle, rule) in _rules) {
    if (label.contains(needle)) return rule;
  }
  return _defaultRule;
}

/// Square counts as portrait: a body shot can be square; a border strip never is.
PhotoOrientation orientationOf(int width, int height) =>
    height >= width ? PhotoOrientation.portrait : PhotoOrientation.landscape;

/// The long side of the small copy every check runs on.
const analysisWidth = 192;

/// A greyscale frame, small enough to scan several times a second.
class Grey {
  Grey(this.width, this.height, this.data)
      : assert(data.length == width * height);

  final int width;
  final int height;

  /// One byte per pixel, row-major.
  final Uint8List data;

  /// How much to stride a full-size frame so its long side lands near
  /// [analysisWidth]. Never below 1.
  static int stepFor(int width, int height) =>
      math.max(1, (math.max(width, height) / analysisWidth).ceil());

  /// From a luma plane — the Y of a YUV420 camera frame, which is exactly
  /// the greyscale wanted, with nothing to convert. Android's CameraX hands
  /// frames over in that format.
  ///
  /// [pixelStride] is 1 on every device seen so far, but the plane format
  /// allows otherwise, so it is read rather than assumed.
  factory Grey.fromLuma({
    required Uint8List plane,
    required int width,
    required int height,
    required int rowStride,
    int pixelStride = 1,
  }) {
    final step = stepFor(width, height);
    final outW = math.max(8, width ~/ step);
    final outH = math.max(8, height ~/ step);
    final out = Uint8List(outW * outH);
    for (var y = 0; y < outH; y++) {
      final row = y * step * rowStride;
      for (var x = 0; x < outW; x++) {
        out[y * outW + x] = plane[row + x * step * pixelStride];
      }
    }
    return Grey(outW, outH, out);
  }

  /// From interleaved 8-bit BGRA — what iOS hands over.
  factory Grey.fromBgra({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    final step = stepFor(width, height);
    final outW = math.max(8, width ~/ step);
    final outH = math.max(8, height ~/ step);
    final out = Uint8List(outW * outH);
    for (var y = 0; y < outH; y++) {
      final row = y * step * bytesPerRow;
      for (var x = 0; x < outW; x++) {
        final i = row + x * step * 4;
        out[y * outW + x] =
            (bytes[i + 2] * 299 + bytes[i + 1] * 587 + bytes[i] * 114) ~/ 1000;
      }
    }
    return Grey(outW, outH, out);
  }
}

class _Stats {
  const _Stats(this.mean, this.std);
  final double mean;
  final double std;
}

_Stats _stats(Grey g, int x0, int y0, int x1, int y1) {
  var sum = 0;
  var sumSq = 0;
  var n = 0;
  for (var y = y0; y < y1; y++) {
    final row = y * g.width;
    for (var x = x0; x < x1; x++) {
      final v = g.data[row + x];
      sum += v;
      sumSq += v * v;
      n++;
    }
  }
  if (n == 0) return const _Stats(0, 0);
  final mean = sum / n;
  return _Stats(mean, math.sqrt(math.max(0, sumSq / n - mean * mean)));
}

/// Fraction of pixels at the very top or bottom of the range — blown out or
/// crushed.
({double bright, double dark}) _clipped(Grey g) {
  var bright = 0;
  var dark = 0;
  for (final v in g.data) {
    if (v >= 250) {
      bright++;
    } else if (v <= 8) {
      dark++;
    }
  }
  return (bright: bright / g.data.length, dark: dark / g.data.length);
}

/// Variance of a Laplacian: how much each pixel differs from its neighbours.
/// A sharp photograph of cloth is full of edges; a blurred one is smooth.
double _sharpness(Grey g) {
  final width = g.width;
  final height = g.height;
  final data = g.data;
  var sum = 0.0;
  var sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      final lap = 4 * data[i] -
          data[i - 1] -
          data[i + 1] -
          data[i - width] -
          data[i + width];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// Whether the cloth reaches every edge.
///
/// Cloth has texture; a table, a floor or a wall next to it does not, or has
/// a different one. Each edge band is compared with the centre: a band that
/// is nearly flat while the centre is not is something other than the saree.
/// Judged relative to the centre so that a plain silk with little texture is
/// not failed for being what it is.
bool _edgesFilled(Grey g) {
  final band = math.max(4, (math.min(g.width, g.height) * 0.1).round());
  final cx0 = (g.width * 0.3).round();
  final cx1 = (g.width * 0.7).round();
  final cy0 = (g.height * 0.3).round();
  final cy1 = (g.height * 0.7).round();
  final centre = _stats(g, cx0, cy0, cx1, cy1);
  // Camera noise alone gives a real photograph a spread of two or three
  // levels; only a rendered flat colour sits below that.
  final floor = math.max(1.5, centre.std * 0.3);

  final bands = [
    _stats(g, 0, 0, g.width, band),
    _stats(g, 0, g.height - band, g.width, g.height),
    _stats(g, 0, 0, band, g.height),
    _stats(g, g.width - band, 0, g.width, g.height),
  ];
  return bands.every((b) => b.std >= floor && (b.mean - centre.mean).abs() < 90);
}

/// Mean absolute difference between two frames of the same size.
double motion(Grey a, Grey b) {
  if (a.data.length != b.data.length) return 255;
  var sum = 0;
  for (var i = 0; i < a.data.length; i++) {
    sum += (a.data[i] - b.data[i]).abs();
  }
  return sum / a.data.length;
}

class Verdict {
  const Verdict._(this.ok, this.message, this.warning);

  const Verdict.pass() : this._(true, '', false);
  const Verdict.fail(String message) : this._(false, message, false);
  const Verdict.warn(String message) : this._(true, message, true);

  final bool ok;

  /// Why not, for the screen. Empty when ok and nothing to say.
  final String message;

  /// Advisory only: a warning does not stop the photograph.
  final bool warning;
}

/// The live checks, in the order a person can act on them. The first failure
/// is the one shown — one instruction at a time, like a face frame that says
/// "remove glasses" before it says "blink".
Verdict checkFrame(
  Grey g,
  int frameWidth,
  int frameHeight,
  PhotoRule rule,
  Grey? previous,
) {
  if (orientationOf(frameWidth, frameHeight) != rule.orientation) {
    return Verdict.fail(rule.orientation == PhotoOrientation.landscape
        ? 'Turn the phone sideways'
        : 'Hold the phone upright');
  }
  final whole = _stats(g, 0, 0, g.width, g.height);
  final clip = _clipped(g);
  if (whole.mean < 60 || clip.dark > 0.25) {
    return const Verdict.fail('Too dark — find more light');
  }
  if (whole.mean > 215 || clip.bright > 0.06) {
    return const Verdict.fail('Too bright — move out of direct sun');
  }
  if (!_edgesFilled(g)) return const Verdict.fail('Fill the frame with the cloth');
  if (previous != null && motion(g, previous) > 6) {
    return const Verdict.fail('Hold still');
  }
  if (_sharpness(g) < 25) {
    return const Verdict.fail('Out of focus — hold steady, tap to focus');
  }
  return const Verdict.pass();
}

/// The checks for a file someone already has, where only some can be fixed.
Verdict checkStill(Grey g, int width, int height, PhotoRule rule) {
  if (orientationOf(width, height) != rule.orientation) {
    return Verdict.fail(rule.orientation == PhotoOrientation.landscape
        ? 'A border is photographed sideways — wider than tall. Turn it.'
        : 'This part is photographed upright — taller than wide. Turn it.');
  }
  if (math.max(width, height) < rule.minLongSide) {
    return Verdict.fail('Too small: $width × $height. At least '
        '${rule.minLongSide} pixels on the long side.');
  }
  final whole = _stats(g, 0, 0, g.width, g.height);
  if (whole.mean < 60) {
    return const Verdict.warn('Looks dark. A brighter retake will reproduce better.');
  }
  if (whole.mean > 215) {
    return const Verdict.warn(
        'Looks washed out. A retake out of direct light will reproduce better.');
  }
  if (!_edgesFilled(g)) {
    return const Verdict.warn('Something other than the cloth reaches the edge. '
        'Crop or retake so only the cloth is in the frame.');
  }
  return const Verdict.pass();
}

/// A point in the frame, as fractions of its width and height.
typedef FramePoint = ({double x, double y});

/// The four corners of the cloth, clockwise from top-left.
typedef ClothQuad = ({FramePoint tl, FramePoint tr, FramePoint br, FramePoint bl});

/// Where the cloth is in the frame — the four corners a scan app draws
/// before it straightens the page.
///
/// The frame is cut into small blocks and each is judged textured or flat
/// by the same rule [_edgesFilled] uses for its bands. A block only counts
/// if its neighbours mostly do too, which is what stops a printed table mat
/// or a speck of lint pulling a corner out to itself. The corners are the
/// textured blocks furthest along each diagonal — top-left is the least
/// x+y, bottom-right the most, and so on — which for a flat cloth seen at
/// an angle is its outline: a convex four-sided shape, not a box.
///
/// Null when too little of the frame is textured to be a saree at all
/// (under a fifth), or when the cloth already reaches every corner — there
/// is nothing to straighten. The web checks *that* the cloth fills the
/// frame; this finds *where* it is, so a shot taken a little off-square
/// with a strip of table showing comes out square and cloth-only instead
/// of retaken.
ClothQuad? clothQuad(Grey g) {
  const block = 4;
  final cols = g.width ~/ block;
  final rows = g.height ~/ block;
  if (cols < 8 || rows < 8) return null;

  final centre = _stats(
    g,
    (g.width * 0.3).round(),
    (g.height * 0.3).round(),
    (g.width * 0.7).round(),
    (g.height * 0.7).round(),
  );
  final floor = math.max(1.5, centre.std * 0.3);

  final raw = List<bool>.filled(cols * rows, false);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final s = _stats(g, c * block, r * block, (c + 1) * block, (r + 1) * block);
      raw[r * cols + c] = s.std >= floor && (s.mean - centre.mean).abs() < 90;
    }
  }

  // One pass of erosion: a block stays only if at least three of its four
  // neighbours are textured too (fewer at the frame's own edge, where there
  // are fewer neighbours to have).
  bool at(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols && raw[r * cols + c];
  int? minSum, maxSum, minDiff, maxDiff;
  FramePoint? tl, br, tr, bl;
  var kept = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      if (!raw[r * cols + c]) continue;
      var have = 0;
      var textured = 0;
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final rr = r + dr, cc = c + dc;
        if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) continue;
        have++;
        if (at(rr, cc)) textured++;
      }
      if (textured < have - 1) continue;
      kept++;

      // Each candidate is the block's own outer corner in that direction,
      // so the quad hugs the cloth rather than stopping a block short.
      final x0 = c * block, x1 = (c + 1) * block;
      final y0 = r * block, y1 = (r + 1) * block;
      if (minSum == null || x0 + y0 < minSum) {
        minSum = x0 + y0;
        tl = (x: x0 / g.width, y: y0 / g.height);
      }
      if (maxSum == null || x1 + y1 > maxSum) {
        maxSum = x1 + y1;
        br = (x: x1 / g.width, y: y1 / g.height);
      }
      if (maxDiff == null || x1 - y0 > maxDiff) {
        maxDiff = x1 - y0;
        tr = (x: x1 / g.width, y: y0 / g.height);
      }
      if (minDiff == null || x0 - y1 < minDiff) {
        minDiff = x0 - y1;
        bl = (x: x0 / g.width, y: y1 / g.height);
      }
    }
  }
  if (tl == null || kept < cols * rows * 0.2) return null;

  // Reaching the outermost block on every side is reaching the edge: the
  // frame is rarely a whole number of blocks, and the few pixels left over
  // are not a strip of table.
  final edge = block / math.min(g.width, g.height);
  bool near(double v, double target) => (v - target).abs() <= edge * 1.5;
  if (near(tl.x, 0) && near(tl.y, 0) &&
      near(tr!.x, 1) && near(tr.y, 0) &&
      near(br!.x, 1) && near(br.y, 1) &&
      near(bl!.x, 0) && near(bl.y, 1)) {
    return null;
  }

  return (
    tl: (x: tl.x.clamp(0, 1), y: tl.y.clamp(0, 1)),
    tr: (x: tr!.x.clamp(0, 1), y: tr.y.clamp(0, 1)),
    br: (x: br!.x.clamp(0, 1), y: br.y.clamp(0, 1)),
    bl: (x: bl!.x.clamp(0, 1), y: bl.y.clamp(0, 1)),
  );
}
