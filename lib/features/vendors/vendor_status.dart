import '../../widgets/ui/ui.dart';

/// Tone and label for `CoreVendorLedgerEntry.status` and
/// `CoreDamagedThaan.status`. The badge itself is the library's
/// [StatusBadge]; these only say what each server status *means*
/// ([BadgeTone]) so the palette decides the colour in every theme.

BadgeTone vendorTxnStatusTone(String? status) {
  switch (status) {
    case 'needs_pricing':
      return BadgeTone.danger;
    case 'approved':
      return BadgeTone.brand;
    case 'paid':
      return BadgeTone.success;
    default:
      return BadgeTone.neutral;
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

BadgeTone damagedStatusTone(String status) {
  switch (status) {
    case 'flagged':
      return BadgeTone.danger;
    case 'addressed':
      return BadgeTone.brand;
    default:
      return BadgeTone.neutral;
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

/// The badge for a ledger transaction's status.
StatusBadge vendorTxnStatusBadge(String? status) =>
    StatusBadge(vendorTxnStatusLabel(status), tone: vendorTxnStatusTone(status));

/// The badge for a damaged Thaan's status.
StatusBadge damagedStatusBadge(String status) =>
    StatusBadge(damagedStatusLabel(status), tone: damagedStatusTone(status));
