import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Takes reads from a handheld scanner gun on whatever screen it wraps, with
/// nothing to tap first.
///
/// A gun paired over Bluetooth (or plugged in) is a keyboard to the phone: it
/// types the code in a burst and presses Enter. This listens to the hardware
/// keyboard directly rather than through a text field, so the read lands
/// whether or not anything has focus — the person on the floor either points
/// the camera or pulls the trigger, and both just work.
///
/// It stands aside when it should: while a text field has the cursor (the
/// field takes the typing itself), and while another screen or dialog is on
/// top of this one (that screen's own wedge, or its field, takes it).
class ScannerWedge extends StatefulWidget {
  const ScannerWedge({
    super.key,
    required this.onCode,
    required this.child,
    this.enabled = true,
  });

  final void Function(String code) onCode;
  final Widget child;

  /// Off while the screen is busy with a previous read.
  final bool enabled;

  @override
  State<ScannerWedge> createState() => _ScannerWedgeState();
}

class _ScannerWedgeState extends State<ScannerWedge> {
  final _buffer = StringBuffer();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// A gun types a whole code in a few tens of milliseconds. A longer gap
  /// means the characters so far were not one read — start again.
  static const _gap = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _textFieldHasCursor {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || !widget.enabled) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (_textFieldHasCursor) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final now = DateTime.now();
    if (now.difference(_last) > _gap) _buffer.clear();
    _last = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      if (code.isEmpty) return false;
      widget.onCode(code);
      return true;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 0x20) {
      _buffer.write(char);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
