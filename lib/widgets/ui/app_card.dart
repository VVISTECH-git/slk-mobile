import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A bordered, flat surface. Radius 14, 1 px border, no shadow — the app
/// separates things with borders and spacing, never with elevation. Tappable
/// when [onTap] is given (full-card ripple, 56 px minimum so it's a target).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.emphasis = false,
    this.tone,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// A soft tint of the brand colour — for the one card on a screen that
  /// is the thing being worked on (the pile being scanned, the Thaan found).
  final bool emphasis;

  /// A fixed background instead of the surface colour (a status tone).
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final bg = tone ?? (emphasis ? p.primary.withValues(alpha: 0.08) : p.surface2);
    final border = emphasis ? p.primary.withValues(alpha: 0.35) : p.border;

    final box = Ink(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return box;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 56), child: box),
      ),
    );
  }
}

/// One "label: value" line inside a card — the scan card, the bale summary,
/// the vendor balance. Label muted on the left, value on the right, wrapping
/// rather than clipping when a value is long.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.mono = false, this.strong = false});

  final String label;
  final String value;

  /// Codes and amounts read better fixed-width.
  final bool mono;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label, style: TextStyle(color: p.textSecondary, fontSize: 13.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: p.text,
                fontSize: 14,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card's title line with an optional trailing widget (a badge, a count).
class CardTitle extends StatelessWidget {
  const CardTitle(this.title, {super.key, this.subtitle, this.trailing, this.mono = false});

  final String title;

  /// Codes read better fixed-width.
  final bool mono;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text, fontFamily: mono ? 'monospace' : null)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(fontSize: 13, color: p.textSecondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}
