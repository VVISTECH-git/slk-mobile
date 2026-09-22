import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../skeleton.dart';
import 'app_button.dart';

/// The four states every screen has to answer for. Same layout for all of
/// them — icon, title, one line of plain explanation, at most one action —
/// so nobody has to learn a new screen to find out nothing is there.
class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.iconColor,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(color: p.surface3, shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 24 : 30, color: iconColor ?? p.textSecondary),
            ),
            SizedBox(height: compact ? 10 : 14),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text)),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.45, color: p.textSecondary)),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Nothing to show — and what would put something here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.title = 'Nothing here yet',
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => _StateLayout(
        icon: icon,
        title: title,
        message: message,
        compact: compact,
        action: actionLabel == null ? null : AppButton.secondary(label: actionLabel!, expand: false, onPressed: onAction),
      );
}

/// Something went wrong — what, in the server's own words, and a way to try
/// again. The message is the API's `error` text, which is written for people.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.title = "Couldn't load this", this.compact = false});

  final String message;
  final VoidCallback? onRetry;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) => _StateLayout(
        icon: Icons.cloud_off_outlined,
        iconColor: context.p.danger,
        title: title,
        message: message,
        compact: compact,
        action: onRetry == null ? null : AppButton.secondary(label: 'Try again', icon: Icons.refresh, expand: false, onPressed: onRetry),
      );
}

/// It worked — said once, clearly, with the next thing to do.
class SuccessState extends StatelessWidget {
  const SuccessState({super.key, required this.title, this.message, this.actionLabel, this.onAction, this.secondaryLabel, this.onSecondary});

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => _StateLayout(
        icon: Icons.check_rounded,
        iconColor: context.p.success,
        title: title,
        message: message,
        action: actionLabel == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton.primary(label: actionLabel!, expand: false, onPressed: onAction),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: 8),
                    AppButton.ghost(label: secondaryLabel!, onPressed: onSecondary),
                  ],
                ],
              ),
      );
}

/// Waiting. Skeleton rows for a list that is coming; a centred spinner with
/// a line of text for a single thing (a scan resolving, a save). Never a bare
/// spinner in the middle of nothing.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message, this.rows});

  /// Text under the spinner, e.g. "Looking up T00002001…".
  final String? message;

  /// Show skeleton rows instead of a spinner (a list is loading).
  final int? rows;

  @override
  Widget build(BuildContext context) {
    if (rows != null) return SkeletonList(rows: rows!);
    final p = context.p;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6, color: p.primary)),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: TextStyle(fontSize: 14, color: p.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// A single-line inline notice inside a screen — a hint, a warning, a count
/// that matters. Quieter than a dialog, more visible than helper text.
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.text, {super.key, this.icon = Icons.info_outline, this.warning = false});

  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final fg = warning ? p.danger : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? p.danger.withValues(alpha: 0.08) : p.surface3,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: fg))),
        ],
      ),
    );
  }
}
