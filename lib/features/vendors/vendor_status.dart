import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Colour and label for `CoreVendorLedgerEntry.status` and
/// `CoreDamagedThaan.status` — the phone has no separate "warn" token in
/// its palette (see `theme/app_theme.dart`'s `AppPalette`), so these reuse
/// `primary`/`danger`/`success`/`textMuted` rather than inventing a new one.

Color vendorTxnStatusColor(BuildContext context, String? status) {
  final p = context.p;
  switch (status) {
    case 'needs_pricing':
      return p.danger;
    case 'approved':
      return p.primary;
    case 'paid':
      return p.success;
    default:
      return p.textMuted;
  }
}

String vendorTxnStatusLabel(String? status) {
  switch (status) {
    case 'needs_pricing':
      return 'Needs pricing';
    case 'approved':
      return 'Approved · unpaid';
    case 'paid':
      return 'Paid';
    default:
      return 'Unapproved';
  }
}

Color damagedStatusColor(BuildContext context, String status) {
  final p = context.p;
  switch (status) {
    case 'flagged':
      return p.danger;
    case 'addressed':
      return p.primary;
    default:
      return p.textMuted;
  }
}

String damagedStatusLabel(String status) {
  switch (status) {
    case 'flagged':
      return 'Flagged';
    case 'addressed':
      return 'Addressed';
    default:
      return 'Written off';
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
