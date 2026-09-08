import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One selectable option. [color] renders a swatch dot (used for colours).
class PickerOption {
  const PickerOption(this.value, this.label, {this.color, this.subtitle});
  final String value;
  final String label;
  final Color? color;

  /// Secondary line shown below the wheel when this item is centred
  /// (e.g. the full category path), so the wheel itself stays uncluttered.
  final String? subtitle;
}

/// A form-field-styled selector that opens an iOS-style drum-roll wheel
/// picker instead of a flat list. Used app-wide so every selector matches.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.allowClear = false,
  });

  final String label;
  final String? value;
  final List<PickerOption> options;
  final ValueChanged<String?> onChanged;
  final String? hint;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    PickerOption? sel;
    for (final o in options) {
      if (o.value == value) {
        sel = o;
        break;
      }
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final result = await showModalBottomSheet<_PickResult>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.p.surface2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _WheelPickerSheet(
            title: label,
            options: options,
            current: value,
            allowClear: allowClear,
          ),
        );
        if (result != null) onChanged(result.cleared ? null : result.value);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: Row(
          children: [
            if (sel?.color != null) ...[
              _Swatch(color: sel!.color!),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                sel?.label ?? (hint ?? 'Select'),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: sel == null ? context.p.textMuted : context.p.text,
                  fontWeight: sel == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Internal result ───────────────────────────────────────────────────────────

class _PickResult {
  const _PickResult(this.value, {this.cleared = false});
  final String? value;
  final bool cleared;
}

// ── Wheel picker sheet ────────────────────────────────────────────────────────

class _WheelPickerSheet extends StatefulWidget {
  const _WheelPickerSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.allowClear,
  });
  final String title;
  final List<PickerOption> options;
  final String? current;
  final bool allowClear;

  @override
  State<_WheelPickerSheet> createState() => _WheelPickerSheetState();
}

class _WheelPickerSheetState extends State<_WheelPickerSheet> {
  late final FixedExtentScrollController _ctrl;
  late int _idx;

  @override
  void initState() {
    super.initState();
    _idx = widget.options.indexWhere((o) => o.value == widget.current);
    if (_idx < 0) _idx = 0;
    _ctrl = FixedExtentScrollController(initialItem: _idx);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (widget.options.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, _PickResult(widget.options[_idx].value));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final opt = widget.options.isNotEmpty ? widget.options[_idx] : null;
    final hasSubtitles = widget.options.any(
      (o) => o.subtitle != null && o.subtitle!.isNotEmpty,
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),

          // Grabber
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: Cancel | Title | Clear/Done
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: p.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                /*
                  Clear and Done are different actions, not two names for one
                  button. This used to show only whichever of the two an
                  if/else picked — a field that already carried a value and
                  allowed clearing got Clear alone, so scrolling the wheel to
                  a new choice had nothing to confirm it with: Cancel discards,
                  Clear wipes to nothing, and neither one saves what the wheel
                  is actually sitting on. Changing an already-answered
                  optional field took two separate visits to this sheet —
                  clear it, reopen, then pick — because only the second visit
                  ever showed Done.
                */
                if (widget.allowClear && widget.current != null)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _PickResult(null, cleared: true),
                    ),
                    style: TextButton.styleFrom(foregroundColor: p.danger),
                    child: const Text('Clear'),
                  ),
                TextButton(
                  onPressed: _confirm,
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Subtitle hint — shows full category path for the centred item
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: (hasSubtitles && opt?.subtitle != null && opt!.subtitle!.isNotEmpty)
                ? Padding(
                    key: ValueKey(opt.subtitle),
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
                    child: Text(
                      opt.subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), height: 14),
          ),

          // ── Wheel ─────────────────────────────────────────────────────────
          SizedBox(
            height: 216,
            child: Stack(
              children: [
                // Selection highlight band (sits behind the wheel text)
                Center(
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: p.primary.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                  ),
                ),

                // Wheel
                ListWheelScrollView.useDelegate(
                  controller: _ctrl,
                  itemExtent: 54,
                  physics: const FixedExtentScrollPhysics(),
                  perspective: 0.002,
                  magnification: 1.18,
                  useMagnifier: true,
                  overAndUnderCenterOpacity: 0.3,
                  onSelectedItemChanged: (i) => setState(() => _idx = i),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: widget.options.length,
                    builder: (context, i) {
                      final o = widget.options[i];
                      final selected = i == _idx;
                      // Long labels (e.g. full saree names) scale down to fit
                      // the wheel width so the WHOLE name stays visible instead
                      // of being clipped at the edges.
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (o.color != null) ...[
                                  _Swatch(color: o.color!, size: 22),
                                  const SizedBox(width: 10),
                                ],
                                Text(
                                  o.label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight:
                                        selected ? FontWeight.w700 : FontWeight.w400,
                                    color: selected ? p.primary : p.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Swatch dot ────────────────────────────────────────────────────────────────

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.size = 18});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.p.border),
      ),
    );
  }
}

// ── Colour helpers ────────────────────────────────────────────────────────────

/// Standard saree colour → swatch colour. Unknown names get a neutral dot.
const Map<String, int> _colourHex = {
  'red': 0xFFD32F2F, 'maroon': 0xFF800000, 'rani pink': 0xFFE30B5C, 'pink': 0xFFFF80AB,
  'peach': 0xFFFFCBA4, 'orange': 0xFFFB8C00, 'rust': 0xFFB7410E, 'mustard': 0xFFE1AD01,
  'yellow': 0xFFFDD835, 'gold': 0xFFD4AF37, 'cream': 0xFFFFF1C1, 'off white': 0xFFF3EEDD,
  'white': 0xFFFFFFFF, 'beige': 0xFFE8DCB5, 'brown': 0xFF795548, 'coffee': 0xFF6F4E37,
  'green': 0xFF388E3C, 'mehendi': 0xFF6B8E23, 'teal': 0xFF008080, 'sea green': 0xFF2E8B57,
  'blue': 0xFF1976D2, 'sky blue': 0xFF87CEEB, 'navy': 0xFF001F5B, 'indigo': 0xFF3F51B5,
  'purple': 0xFF8E24AA,
};

Color colourSwatch(String name) {
  final hex = _colourHex[name.trim().toLowerCase()];
  return Color(hex ?? 0xFFBDBDBD);
}

/// Build colour options (with swatches) from a list of colour names.
List<PickerOption> colourOptions(List<String> names) =>
    [for (final n in names) PickerOption(n, n, color: colourSwatch(n))];

/// Build plain options where value == label.
List<PickerOption> plainOptions(List<String> values) =>
    [for (final v in values) PickerOption(v, v)];
