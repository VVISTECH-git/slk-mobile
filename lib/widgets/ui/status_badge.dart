import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// What a badge means, not what colour it is. The palette decides the colour,
/// so a badge is right in every theme, dark ones included.
enum BadgeTone { neutral, brand, success, warning, danger, info }

/// A small pill that names a state: "Active", "Out for Salava", "Draft",
/// "Needs motif". Never the only place a state is shown to a screen reader —
/// the text is the meaning; the colour just makes it scannable.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = BadgeTone.neutral, this.icon});

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  /// The badge for a Thaan's pipeline status, from the prefix the server uses.
  factory StatusBadge.pipeline(String status) {
    final tone = switch (status) {
      'Finished' => BadgeTone.success,
      'QR Pending' => BadgeTone.neutral,
      'QR Generated' => BadgeTone.info,
      _ when status.startsWith('Out for') => BadgeTone.warning,
      _ when status.startsWith('Ready for') => BadgeTone.brand,
      _ => BadgeTone.neutral,
    };
    return StatusBadge(status, tone: tone);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (Color fg, Color bg) = switch (tone) {
      BadgeTone.neutral => (p.textSecondary, p.surface3),
      BadgeTone.brand => (p.primary, p.primary.withValues(alpha: 0.12)),
      BadgeTone.success => (p.success, p.success.withValues(alpha: 0.14)),
      BadgeTone.warning => (p.accent, p.accent.withValues(alpha: 0.18)),
      BadgeTone.danger => (p.danger, p.danger.withValues(alpha: 0.12)),
      BadgeTone.info => (p.textSecondary, p.border.withValues(alpha: 0.6)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

/// A big number with a small label under it — the count at the top of a
/// summary. Tabular figures so a column of them lines up.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.tone = BadgeTone.neutral});

  final String value;
  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final color = switch (tone) {
      BadgeTone.brand => p.primary,
      BadgeTone.success => p.success,
      BadgeTone.warning => p.accent,
      BadgeTone.danger => p.danger,
      _ => p.text,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color, height: 1, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textSecondary)),
      ],
    );
  }
}
