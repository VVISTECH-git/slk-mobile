import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Which job a button does on its screen. One primary per screen; secondary
/// for the other way out; danger only for something that can't be undone;
/// ghost for the quiet, in-line kind ("Clear", "Skip").
enum AppButtonVariant { primary, secondary, danger, ghost }

/// The one button. 48 px tall so it can be hit with a thumb on the floor,
/// same corner radius everywhere, and a [busy] state that replaces the label
/// with a spinner *and* disables the tap — the two always go together.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.compact = false,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.compact = false,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.compact = false,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.compact = false,
  }) : variant = AppButtonVariant.danger;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.compact = false,
  }) : variant = AppButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool busy;

  /// Fill the row (the default for actions at the bottom of a screen).
  final bool expand;

  /// 40 px tall, for a button inside a card or a list row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final height = compact ? 40.0 : 48.0;
    final enabled = onPressed != null && !busy;

    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      AppButtonVariant.primary => (p.primary, p.onPrimary, BorderSide.none),
      AppButtonVariant.secondary => (p.surface2, p.text, BorderSide(color: p.border, width: 1.5)),
      AppButtonVariant.danger => (p.danger, Colors.white, BorderSide.none),
      AppButtonVariant.ghost => (Colors.transparent, p.primary, BorderSide.none),
    };

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(compact ? 0 : 64, height)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: compact ? 14 : 20)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? bg.withValues(alpha: variant == AppButtonVariant.ghost ? 0 : 0.5) : bg,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? fg.withValues(alpha: 0.7) : fg,
      ),
      overlayColor: WidgetStatePropertyAll(fg.withValues(alpha: 0.08)),
      side: WidgetStatePropertyAll(side),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: compact ? 14 : 15, fontWeight: FontWeight.w700)),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final child = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final button = TextButton(style: style, onPressed: enabled ? onPressed : null, child: child);

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// An icon-only button with a 44 px hit area and an [aria]-style label for
/// screen readers — for app-bar actions and row trailers.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: color ?? context.p.textSecondary),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
