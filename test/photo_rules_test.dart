import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/photo_rules.dart';

/// A flat colour — a wall, a table, a rendered nothing.
Grey uniform(int w, int h, int value) => Grey(w, h, Uint8List(w * h)..fillRange(0, w * h, value));

/// Cloth: fine, high-contrast texture everywhere. Neighbouring pixels
/// differ by seven levels, so the Laplacian is large and so is the spread.
Grey cloth(int w, int h, {int base = 100}) {
  final d = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      d[y * w + x] = base + (x * 7 + y * 13) % 60;
    }
  }
  return Grey(w, h, d);
}

/// Cloth in the middle, a flat table around it — the table reaching every
/// edge is what "fill the frame" exists to catch.
Grey clothOnTable(int w, int h, {double inset = 0.25}) {
  final d = Uint8List(w * h)..fillRange(0, w * h, 128);
  final x0 = (w * inset).round(), x1 = (w * (1 - inset)).round();
  final y0 = (h * inset).round(), y1 = (h * (1 - inset)).round();
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      d[y * w + x] = 100 + (x * 7 + y * 13) % 60;
    }
  }
  return Grey(w, h, d);
}

/// Cloth seen at an angle: from y = 20% to 80% of the frame, its edges
/// run from x = 35%–65% at the top out to 20%–80% at the bottom. Flat table
/// everywhere else.
Grey clothTrapezoid(int w, int h) {
  final d = Uint8List(w * h)..fillRange(0, w * h, 128);
  for (var y = 0; y < h; y++) {
    final fy = y / h;
    if (fy < 0.2 || fy >= 0.8) continue;
    final t = (fy - 0.2) / 0.6;
    final x0 = (w * (0.35 - 0.15 * t)).round();
    final x1 = (w * (0.65 + 0.15 * t)).round();
    for (var x = x0; x < x1; x++) {
      d[y * w + x] = 100 + (x * 7 + y * 13) % 60;
    }
  }
  return Grey(w, h, d);
}

/// Smooth, slow waves: plenty of spread, no edges — a blurred photograph.
Grey blurred(int w, int h) {
  final d = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      d[y * w + x] = (128 + 60 * math.sin(x / 8) * math.cos(y / 8)).round();
    }
  }
  return Grey(w, h, d);
}

const body = PhotoRule(orientation: PhotoOrientation.portrait, minLongSide: 1500, guide: '');

void main() {
  group('ruleFor', () {
    test('reads the part off the slot label, whatever else the label says', () {
      expect(ruleFor('Border').orientation, PhotoOrientation.landscape);
      expect(ruleFor('Saree Body').orientation, PhotoOrientation.portrait);
      expect(ruleFor('PALLU').minLongSide, 1500);
      expect(ruleFor('Blouse piece').orientation, PhotoOrientation.portrait);
    });

    test('an unknown slot gets the lenient default', () {
      final rule = ruleFor('Full length');
      expect(rule.orientation, PhotoOrientation.portrait);
      expect(rule.minLongSide, 1200);
    });
  });

  test('square counts as portrait', () {
    expect(orientationOf(1000, 1000), PhotoOrientation.portrait);
    expect(orientationOf(1000, 999), PhotoOrientation.landscape);
  });

  group('checkFrame — one instruction at a time, in the order it can be acted on', () {
    test('orientation first: a border held upright', () {
      final v = checkFrame(cloth(108, 192), 1080, 1920, ruleFor('Border'), null);
      expect(v.ok, isFalse);
      expect(v.message, 'Turn the phone sideways');
    });

    test('too dark', () {
      final v = checkFrame(uniform(108, 192, 30), 1080, 1920, body, null);
      expect(v.message, 'Too dark — find more light');
    });

    test('too bright', () {
      final v = checkFrame(uniform(108, 192, 240), 1080, 1920, body, null);
      expect(v.message, 'Too bright — move out of direct sun');
    });

    test('table showing at the edges', () {
      final v = checkFrame(clothOnTable(108, 192), 1080, 1920, body, null);
      expect(v.message, 'Fill the frame with the cloth');
    });

    test('the phone moved since the last frame', () {
      final v = checkFrame(cloth(108, 192), 1080, 1920, body, cloth(108, 192, base: 140));
      expect(v.message, 'Hold still');
    });

    test('out of focus: spread without edges', () {
      final v = checkFrame(blurred(108, 192), 1080, 1920, body, null);
      expect(v.message, 'Out of focus — hold steady, tap to focus');
    });

    test('cloth, lit, still, sharp: passes', () {
      final now = cloth(108, 192);
      final v = checkFrame(now, 1080, 1920, body, cloth(108, 192));
      expect(v.ok, isTrue);
      expect(v.message, isEmpty);
    });
  });

  group('checkStill — what can still be fixed after the fact', () {
    test('wrong way round is refused, with the part named', () {
      final v = checkStill(cloth(192, 108), 1920, 1080, body);
      expect(v.ok, isFalse);
      expect(v.message, contains('upright'));
    });

    test('too small is refused, with the numbers', () {
      final v = checkStill(cloth(108, 192), 800, 1000, body);
      expect(v.ok, isFalse);
      expect(v.message, 'Too small: 800 × 1000. At least 1500 pixels on the long side.');
    });

    test('dark is only a warning — the photograph still goes', () {
      final v = checkStill(cloth(108, 192, base: 20), 1080, 1920, body);
      expect(v.ok, isTrue);
      expect(v.warning, isTrue);
      expect(v.message, startsWith('Looks dark'));
    });

    test('table at the edge is only a warning', () {
      final v = checkStill(clothOnTable(108, 192), 1080, 1920, body);
      expect(v.ok, isTrue);
      expect(v.warning, isTrue);
      expect(v.message, contains('Something other than the cloth'));
    });

    test('a good file passes silently', () {
      final v = checkStill(cloth(108, 192), 1080, 1920, body);
      expect(v.ok, isTrue);
      expect(v.warning, isFalse);
    });
  });

  group('motion', () {
    test('identical frames do not move', () {
      expect(motion(cloth(20, 20), cloth(20, 20)), 0);
    });

    test('black to white is the whole range', () {
      expect(motion(uniform(20, 20, 0), uniform(20, 20, 255)), 255);
    });

    test('a different size can only be movement', () {
      expect(motion(uniform(20, 20, 0), uniform(10, 10, 0)), 255);
    });
  });

  group('Grey.fromLuma', () {
    test('strides a 1080p plane down to the analysis size', () {
      const w = 1920, h = 1080;
      final plane = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        plane.fillRange(y * w, (y + 1) * w, y % 256);
      }
      final g = Grey.fromLuma(plane: plane, width: w, height: h, rowStride: w);

      expect(Grey.stepFor(w, h), 10);
      expect(g.width, 192);
      expect(g.height, 108);
      // Row y of the small copy is row 10y of the plane.
      expect(g.data[5 * g.width], 50);
    });

    test('honours a padded row stride', () {
      const w = 100, h = 50, stride = 128;
      final plane = Uint8List(stride * h);
      for (var y = 0; y < h; y++) {
        plane.fillRange(y * stride, y * stride + w, y);
      }
      final g = Grey.fromLuma(plane: plane, width: w, height: h, rowStride: stride);
      expect(g.width, 100);
      expect(g.data[7 * g.width + 3], 7);
    });
  });

  group('clothQuad — where the cloth is, corner by corner', () {
    test('cloth square to the camera: the four corners of the cloth', () {
      final q = clothQuad(clothOnTable(192, 192, inset: 0.25));
      expect(q, isNotNull);
      expect(q!.tl.x, closeTo(0.25, 0.04));
      expect(q.tl.y, closeTo(0.25, 0.04));
      expect(q.tr.x, closeTo(0.75, 0.04));
      expect(q.tr.y, closeTo(0.25, 0.04));
      expect(q.br.x, closeTo(0.75, 0.04));
      expect(q.br.y, closeTo(0.75, 0.04));
      expect(q.bl.x, closeTo(0.25, 0.04));
      expect(q.bl.y, closeTo(0.75, 0.04));
    });

    test('cloth seen at an angle: a trapezoid, not its bounding box', () {
      // Narrow at the top, wide at the bottom — a saree on a table shot
      // from a little in front of it. The bounding box would be
      // 0.20–0.80 across the whole height; the corners are not.
      final q = clothQuad(clothTrapezoid(192, 192));
      expect(q, isNotNull);
      expect(q!.tl.x, closeTo(0.35, 0.05));
      expect(q.tl.y, closeTo(0.20, 0.04));
      expect(q.tr.x, closeTo(0.65, 0.05));
      expect(q.tr.y, closeTo(0.20, 0.04));
      expect(q.bl.x, closeTo(0.20, 0.05));
      expect(q.bl.y, closeTo(0.80, 0.04));
      expect(q.br.x, closeTo(0.80, 0.05));
      expect(q.br.y, closeTo(0.80, 0.04));
    });

    test('a speck of lint on the table does not become a corner', () {
      final g = clothOnTable(192, 192, inset: 0.25);
      // A lone textured block near the top-left of the frame.
      for (var y = 8; y < 12; y++) {
        for (var x = 8; x < 12; x++) {
          g.data[y * g.width + x] = 100 + (x * 7 + y * 13) % 60;
        }
      }
      final q = clothQuad(g);
      expect(q, isNotNull);
      expect(q!.tl.x, closeTo(0.25, 0.04));
      expect(q.tl.y, closeTo(0.25, 0.04));
    });

    test('cloth filling the frame needs no straightening', () {
      expect(clothQuad(cloth(192, 192)), isNull);
    });

    test('nothing textured is not a saree', () {
      expect(clothQuad(uniform(192, 192, 128)), isNull);
    });
  });
}
