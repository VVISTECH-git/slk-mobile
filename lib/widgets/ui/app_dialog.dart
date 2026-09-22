import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_button.dart';

/// "Are you sure?" the one way. Returns true only on the confirm button.
/// [danger] makes the confirm red, for things that can't be undone (void a
/// Thaan, write off damage) — never for a plain save.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final p = context.p;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
      content: Text(message, style: TextStyle(fontSize: 14.5, height: 1.45, color: p.textSecondary)),
      actions: [
        AppButton.secondary(label: cancelLabel, expand: false, onPressed: () => Navigator.of(ctx).pop(false)),
        if (danger)
          AppButton.danger(label: confirmLabel, expand: false, onPressed: () => Navigator.of(ctx).pop(true))
        else
          AppButton.primary(label: confirmLabel, expand: false, onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    ),
  );
  return result ?? false;
}

/// A message with one button, for something the person just needs to know.
Future<void> showMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'OK',
}) {
  final p = context.p;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
      content: Text(message, style: TextStyle(fontSize: 14.5, height: 1.45, color: p.textSecondary)),
      actions: [AppButton.primary(label: buttonLabel, expand: false, onPressed: () => Navigator.of(ctx).pop())],
    ),
  );
}

/// The bottom sheet every form-in-a-sheet uses: grabber, title, the content,
/// and room for the keyboard. Returns whatever the content pops with.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  String? subtitle,
}) {
  final p = context.p;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.text)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 13.5, color: p.textSecondary)),
              ],
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}
