import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'photo_rules.dart';

/// One photograph this screen is asked for.
class CaptureSlot {
  const CaptureSlot({required this.id, required this.label});
  final String id;
  final String label;
}

/// A camera that knows what a saree photograph should look like.
///
/// The system camera hands back a file and nothing else — no say while the
/// frame is being lined up, which is the only moment a sideways border or a
/// half-table body shot can be prevented. This runs [checkFrame] on the live
/// stream several times a second and says, one line at a time, what to
/// change: turn the phone, find light, fill the frame, hold still. Once the
/// frame has been right for most of a second it takes the photograph itself,
/// the way a face-authentication screen does the moment you blink — nobody
/// has to hold a saree steady with one hand and find a shutter with the
/// other.
///
/// Each capture is then cut down to the cloth ([textureBounds]), checked as
/// a still ([checkStill]), and handed to [onCaptured]; the screen moves on
/// to the next slot by itself and pops after the last. The caller decides
/// what a captured file means — upload it now, or hold it until a record
/// exists.
class GuidedCaptureScreen extends StatefulWidget {
  const GuidedCaptureScreen({
    super.key,
    required this.slots,
    required this.onCaptured,
  });

  /// In the order they will be shot. Empty is a programming error.
  final List<CaptureSlot> slots;

  /// Called once per accepted photograph, before the screen moves on. Any
  /// error thrown is shown and the slot is offered again.
  final Future<void> Function(CaptureSlot slot, File file) onCaptured;

  @override
  State<GuidedCaptureScreen> createState() => _GuidedCaptureScreenState();
}

enum _Phase { starting, live, processing, review, failed }

class _GuidedCaptureScreenState extends State<GuidedCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  _Phase _phase = _Phase.starting;
  String? _failure;

  int _index = 0;
  final Map<String, File> _done = {};

  Verdict _verdict = const Verdict.fail('Starting the camera…');
  Grey? _previous;
  DateTime? _greenSince;
  DateTime _lastAnalysed = DateTime.fromMillisecondsSinceEpoch(0);
  bool _analysing = false;
  bool _shooting = false;

  /// While [onCaptured] runs — an upload, on the record's photo screen.
  /// Both review buttons are held until it returns: a second "Use it
  /// anyway" on slow wifi used to send the file twice and skip a slot.
  bool _accepting = false;

  /// The photograph waiting for a decision, and what the still check said.
  File? _reviewFile;
  Verdict? _reviewVerdict;

  CaptureSlot get _slot => widget.slots[_index];
  PhotoRule get _rule => ruleFor(_slot.label);

  @override
  void initState() {
    super.initState();
    assert(widget.slots.isNotEmpty);
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  /// The camera has to be given up when the app goes to the background and
  /// taken again on return — Android reclaims it, and a controller left
  /// holding a dead camera throws on the next frame.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      camera.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // Y is the greyscale the checks want, straight off the sensor, and
        // BGRA is what iOS gives regardless — Grey reads either.
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      await camera.startImageStream(_onFrame);
      setState(() => _phase = _Phase.live);

      if (!await _CaptureGuide.seen()) {
        if (mounted) await _CaptureGuide.show(context);
      }
    } on CameraException catch (e) {
      // Permission refused is the common one on a shared floor phone. Said
      // plainly, with the way out, rather than a blank black screen.
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _failure = e.code == 'CameraAccessDenied' ||
                e.code == 'CameraAccessDeniedWithoutPrompt'
            ? 'The camera is switched off for this app. Allow it in the '
                "phone's settings and come back."
            : 'The camera could not start (${e.description ?? e.code}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _failure = 'The camera could not start. $e';
      });
    }
  }

  // ── The live loop ──────────────────────────────────────────────────────

  void _onFrame(CameraImage image) {
    // Four times a second is plenty: the checks are for a hand holding a
    // phone, not a conveyor belt, and every frame skipped is battery kept.
    final now = DateTime.now();
    if (_analysing ||
        _shooting ||
        _phase != _Phase.live ||
        now.difference(_lastAnalysed).inMilliseconds < 250) {
      return;
    }
    _analysing = true;
    _lastAnalysed = now;

    try {
      final grey = _greyOf(image);
      final upright = MediaQuery.orientationOf(context) == Orientation.portrait;
      // The stream comes in sensor orientation on Android — landscape
      // whichever way the phone is held — so the phone's own orientation is
      // what the rule is checked against, not the buffer's.
      final verdict = checkFrame(
        grey,
        upright ? 1 : 2,
        upright ? 2 : 1,
        _rule,
        _previous,
      );
      _previous = grey;

      if (verdict.ok) {
        _greenSince ??= now;
        // Green for most of a second: long enough to be sure, short enough
        // that nobody has to hold a saree steady for long.
        if (now.difference(_greenSince!).inMilliseconds > 800) {
          _shooting = true;
          unawaited(_take());
        }
      } else {
        _greenSince = null;
      }

      if (mounted && (verdict.message != _verdict.message || verdict.ok != _verdict.ok)) {
        setState(() => _verdict = verdict);
      }
    } finally {
      _analysing = false;
    }
  }

  static Grey _greyOf(CameraImage image) {
    final plane = image.planes[0];
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return Grey.fromBgra(
        bytes: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
      );
    }
    return Grey.fromLuma(
      plane: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
      pixelStride: plane.bytesPerPixel ?? 1,
    );
  }

  // ── Taking, cropping, checking ─────────────────────────────────────────

  Future<void> _take() async {
    final camera = _camera;
    if (camera == null) return;
    setState(() => _phase = _Phase.processing);

    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      final result = await compute(_prepare, (bytes, _rule));

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/slk-${_slot.id}-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(result.jpeg, flush: true);

      if (!mounted) return;
      final verdict = result.verdict;
      if (verdict.ok && !verdict.warning) {
        // Nothing to decide — it is a good photograph. A moment of green so
        // the capture is seen to happen, then on to the next part.
        setState(() {
          _reviewFile = file;
          _reviewVerdict = verdict;
          _phase = _Phase.review;
        });
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) await _accept();
      } else {
        setState(() {
          _reviewFile = file;
          _reviewVerdict = verdict;
          _phase = _Phase.review;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: context.p.danger),
      );
      _resume();
    }
  }

  /// Runs off the main isolate: decoding a 12-megapixel JPEG takes most of
  /// a second, and the preview underneath would freeze for all of it.
  static ({Uint8List jpeg, Verdict verdict}) _prepare((Uint8List, PhotoRule) args) {
    final (bytes, rule) = args;
    var image = img.decodeImage(bytes);
    if (image == null) {
      return (jpeg: bytes, verdict: const Verdict.fail('That photograph could not be read.'));
    }
    // The camera writes the sensor's orientation into EXIF rather than the
    // pixels; everything downstream reads pixels.
    image = img.bakeOrientation(image);

    // Straighten and cut down to the cloth, where its four corners can be
    // found — the way a scan app squares a page. The result keeps the
    // cloth's own proportions (each side the average of the two edges it
    // came from) rather than being stretched to the frame. Only if what is
    // left still clears the slot's minimum: a straightening that would drop
    // it under is a shot with too much table in it, and the edge warning
    // below says that; "Too small" after a silent crop would send somebody
    // looking for a better camera.
    final quad = clothQuad(_greyOfImage(image));
    if (quad != null) {
      final w = image.width, h = image.height;
      img.Point at(FramePoint p) => img.Point(p.x * w, p.y * h);
      final tl = at(quad.tl), tr = at(quad.tr), br = at(quad.br), bl = at(quad.bl);
      double len(img.Point a, img.Point b) =>
          math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
      final outW = ((len(tl, tr) + len(bl, br)) / 2).round();
      final outH = ((len(tl, bl) + len(tr, br)) / 2).round();
      if (outW > 0 && outH > 0 && math.max(outW, outH) >= rule.minLongSide) {
        image = img.copyRectify(
          image,
          topLeft: tl,
          topRight: tr,
          bottomLeft: bl,
          bottomRight: br,
          interpolation: img.Interpolation.linear,
          toImage: img.Image(width: outW, height: outH),
        );
      }
    }

    // Big enough to keep every rule's minimum, small enough to send from a
    // warehouse — 2400 on the long side is well under the API's 12MB.
    const maxLong = 2400;
    if (image.width > maxLong || image.height > maxLong) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxLong, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxLong, interpolation: img.Interpolation.average);
    }

    final verdict = checkStill(_greyOfImage(image), image.width, image.height, rule);
    return (jpeg: img.encodeJpg(image, quality: 88), verdict: verdict);
  }

  static Grey _greyOfImage(img.Image image) {
    final step = Grey.stepFor(image.width, image.height);
    final outW = image.width ~/ step;
    final outH = image.height ~/ step;
    final data = Uint8List(outW * outH);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final p = image.getPixel(x * step, y * step);
        data[y * outW + x] = ((p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000).clamp(0, 255);
      }
    }
    return Grey(outW, outH, data);
  }

  Future<void> _accept() async {
    final file = _reviewFile;
    if (file == null || _accepting) return;
    setState(() => _accepting = true);
    try {
      await widget.onCaptured(_slot, file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: context.p.danger),
      );
      _accepting = false;
      _resume();
      return;
    }
    if (!mounted) return;
    _accepting = false;

    _done[_slot.id] = file;
    if (_index + 1 >= widget.slots.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _resume();
  }

  void _retake() {
    if (_accepting) return;
    _resume();
  }

  void _resume() {
    _reviewFile = null;
    _reviewVerdict = null;
    _previous = null;
    _greenSince = null;
    _shooting = false;
    if (mounted) setState(() => _phase = _Phase.live);
  }

  Future<void> _manualShutter() async {
    if (_phase != _Phase.live || _shooting) return;
    _shooting = true;
    await _take();
  }

  Future<void> _focusAt(TapDownDetails details, BoxConstraints box) async {
    final camera = _camera;
    if (camera == null) return;
    final offset = Offset(
      (details.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
    );
    try {
      await camera.setFocusPoint(offset);
      await camera.setExposurePoint(offset);
    } catch (_) {
      // Not every camera can; the tap was still the right instinct.
    }
  }

  // ── Screen ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final camera = _camera;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              slot: _slot,
              index: _index,
              total: widget.slots.length,
              done: _done,
              onHelp: () => _CaptureGuide.show(context),
            ),
            Expanded(
              child: switch (_phase) {
                _Phase.failed => _Failed(message: _failure ?? ''),
                _Phase.starting => const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  ),
                _ => LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      onTapDown: (d) => _focusAt(d, box),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (camera != null && camera.value.isInitialized)
                            FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: camera.value.previewSize?.height ?? 1,
                                height: camera.value.previewSize?.width ?? 1,
                                child: CameraPreview(camera),
                              ),
                            ),
                          if (_phase == _Phase.review && _reviewFile != null)
                            Image.file(_reviewFile!, fit: BoxFit.contain),
                          _Frame(
                            colour: switch (_phase) {
                              _Phase.review => p.success,
                              _Phase.processing => Colors.white70,
                              _ => _verdict.ok ? p.success : p.danger,
                            },
                          ),
                          if (_phase == _Phase.processing)
                            const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
              },
            ),
            _Footer(
              phase: _phase,
              verdict: _verdict,
              guide: _rule.guide,
              review: _reviewVerdict,
              accepting: _accepting,
              onShutter: _manualShutter,
              onRetake: _retake,
              onAccept: _accept,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pieces of the screen ────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.slot,
    required this.index,
    required this.total,
    required this.done,
    required this.onHelp,
  });

  final CaptureSlot slot;
  final int index;
  final int total;
  final Map<String, File> done;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Stop photographing',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${index + 1} of $total'
                  '${done.isEmpty ? '' : '  ·  ${done.length} done'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            tooltip: 'How to photograph',
            onPressed: onHelp,
          ),
        ],
      ),
    );
  }
}

/// The ring — Aadhaar's face frame, squared off for cloth. Red until the
/// frame is right, green once it is, and nothing else drawn inside it: the
/// rule is that the cloth fills the frame, so the frame *is* the guide.
class _Frame extends StatelessWidget {
  const _Frame({required this.colour});
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            border: Border.all(color: colour, width: 4),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.phase,
    required this.verdict,
    required this.guide,
    required this.review,
    required this.accepting,
    required this.onShutter,
    required this.onRetake,
    required this.onAccept,
  });

  final _Phase phase;
  final Verdict verdict;
  final String guide;
  final Verdict? review;
  final bool accepting;
  final VoidCallback onShutter;
  final VoidCallback onRetake;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    final Widget line;
    final Widget actions;

    switch (phase) {
      case _Phase.review:
        final r = review;
        if (accepting) {
          line = const _Line('Sending…', colour: Colors.white70);
          actions = const SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
          );
        } else if (r == null || (r.ok && !r.warning)) {
          line = _Line('Captured', colour: p.success);
          actions = const SizedBox(height: 56);
        } else {
          line = _Line(r.message, colour: r.ok ? Colors.amber : p.danger);
          actions = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onRetake,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Retake'),
              ),
              if (r.ok) ...[
                const SizedBox(width: 12),
                FilledButton(onPressed: onAccept, child: const Text('Use it anyway')),
              ],
            ],
          );
        }
      case _Phase.processing:
        line = const _Line('Checking…', colour: Colors.white70);
        actions = const SizedBox(height: 56);
      case _Phase.failed:
        line = const SizedBox.shrink();
        actions = const SizedBox(height: 56);
      case _Phase.starting:
      case _Phase.live:
        line = _Line(
          verdict.ok ? 'Hold it there…' : verdict.message,
          colour: verdict.ok ? p.success : Colors.white,
        );
        actions = Center(
          child: IconButton.filled(
            onPressed: phase == _Phase.live ? onShutter : null,
            iconSize: 30,
            padding: const EdgeInsets.all(13),
            tooltip: 'Take it now',
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          line,
          const SizedBox(height: 4),
          Text(
            guide,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          actions,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.colour});
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: Text(
        text,
        key: ValueKey(text),
        textAlign: TextAlign.center,
        style: TextStyle(color: colour, fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 44),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// The do-and-don't page — shown once, then behind the "?".
///
/// Three things, because three is what a person reads while holding a
/// saree: fill the frame, lay it flat in daylight, hold it still. Each is
/// what one of the live checks will otherwise say a moment later, so
/// nobody meets a rule for the first time as a red frame.
class _CaptureGuide {
  static const _key = 'guided_capture_seen';

  static Future<bool> seen() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return true; // No storage — don't nag every time.
    }
  }

  static Future<void> show(BuildContext context) async {
    final p = context.p;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Photograph a saree easily',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
              ),
              const SizedBox(height: 6),
              Text(
                'The frame turns green when the shot is right, and takes '
                'itself. Until then it says what to change.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
              const SizedBox(height: 18),
              const _Tip(
                icon: Icons.crop_free,
                title: 'Fill the frame with the cloth',
                detail: 'Edge to edge — no table, floor or wall showing. '
                    'The border goes sideways, everything else upright.',
              ),
              const _Tip(
                icon: Icons.wb_sunny_outlined,
                title: 'Flat, in daylight',
                detail: 'Spread it out under even light. Not in direct sun, '
                    'not in a dim corner.',
              ),
              const _Tip(
                icon: Icons.back_hand_outlined,
                title: 'Hold still for a moment',
                detail: 'Green means hold it there — the photograph is taken '
                    'for you within a second.',
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(sheet).pop(),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Start photographing'),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: p.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 12.5, color: p.textSecondary, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
