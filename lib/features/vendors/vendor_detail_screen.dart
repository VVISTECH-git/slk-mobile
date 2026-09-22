import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'vendor_providers.dart';
import 'vendor_status.dart';

/// One vendor's own billing — ledger, damaged Thaans, and the actions
/// Finance takes against them: price what came back unpriced, approve,
/// settle in a payment, and address/write off damage. Mirrors slk-core's
/// own Vendors page drawer.
class VendorDetailScreen extends ConsumerStatefulWidget {
  const VendorDetailScreen({super.key, required this.vendorId, this.vendorName});
  final String vendorId;
  final String? vendorName;

  @override
  ConsumerState<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends ConsumerState<VendorDetailScreen> {
  final Set<String> _selected = {};
  bool _busy = false;

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _invalidateAll() {
    ref.invalidate(vendorLedgerProvider(widget.vendorId));
    ref.invalidate(vendorDamagedProvider(widget.vendorId));
    ref.invalidate(coreVendorsFinanceProvider);
  }

  Future<void> _run(Future<String> Function() action, {String? okMessage}) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) return;
      showOk(context, okMessage ?? message);
      setState(() => _selected.clear());
      _invalidateAll();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _priceSelected(List<CoreVendorLedgerEntry> selectedRows) async {
    final pieces = selectedRows.fold<int>(0, (s, e) => s + (e.pieceCount ?? 0));
    final rate = await showAppSheet<double>(
      context,
      title: 'Price ${selectedRows.length} transaction${selectedRows.length == 1 ? "" : "s"}',
      subtitle: '${selectedRows.first.stage} · $pieces piece${pieces == 1 ? "" : "s"} total.',
      child: _RateSheet(entries: selectedRows),
    );
    if (rate == null) return;
    await _run(
      () => ref.read(vendorRepositoryProvider).priceTransactions(
            transactionIds: selectedRows.map((e) => e.id).toList(),
            unitPrice: rate,
          ),
    );
  }

  Future<void> _approveSelected(List<CoreVendorLedgerEntry> selectedRows) => _run(
        () => ref.read(vendorRepositoryProvider).approveTransactions(selectedRows.map((e) => e.id).toList()),
      );

  Future<void> _paySelected(List<CoreVendorLedgerEntry> selectedRows) async {
    final total = selectedRows.fold<double>(0, (s, e) => s + (e.amount ?? 0));
    final draft = await showAppSheet<_PayDraft>(
      context,
      title: 'Pay ₹${total.toStringAsFixed(0)}',
      child: _PaySheet(total: total),
    );
    if (draft == null) return;
    await _run(
      () => ref.read(vendorRepositoryProvider).payTransactions(
            vendorId: widget.vendorId,
            transactionIds: selectedRows.map((e) => e.id).toList(),
            paidOn: draft.paidOn,
            method: draft.method,
            notes: draft.notes,
          ),
    );
  }

  Future<void> _recordPayment() async {
    final draft = await showAppSheet<_RecordPaymentDraft>(
      context,
      title: 'Record payment',
      subtitle: "Against this vendor's running balance — not tied to any particular transaction.",
      child: const _RecordPaymentSheet(),
    );
    if (draft == null) return;
    // One key per sheet the person filled in — a retry of this same payment
    // reuses it, a new sheet gets a new one.
    final key = idempotencyKey();
    await _run(
      () => ref.read(vendorRepositoryProvider).recordPayment(
            vendorId: widget.vendorId,
            amount: draft.amount,
            paidOn: draft.paidOn,
            method: draft.method,
            notes: draft.notes,
            key: key,
          ),
    );
  }

  Future<void> _writeOff(CoreDamagedThaan d) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Write off this Thaan?',
      message: '${d.thaanCode ?? "This Thaan"} from bale ${d.baleCode} will be written off. This cannot be undone.',
      confirmLabel: 'Write off',
      danger: true,
    );
    if (!ok) return;
    await _run(
      () => ref.read(vendorRepositoryProvider).writeOffDamaged(d.id),
      okMessage: 'Written off.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(vendorLedgerProvider(widget.vendorId));
    final damaged = ref.watch(vendorDamagedProvider(widget.vendorId));

    // The selection bar is pinned under the page, so what it can do is
    // worked out here from whatever the ledger currently holds.
    final loadedRows = ledger.valueOrNull ?? const <CoreVendorLedgerEntry>[];
    final txns = loadedRows.where((r) => r.isTransaction).toList();
    final selectedRows = txns.where((r) => _selected.contains(r.id)).toList();

    final canPrice = selectedRows.isNotEmpty &&
        selectedRows.every((r) => r.status == 'needs_pricing') &&
        selectedRows.every((r) => r.stage == selectedRows.first.stage);
    final canApprove = selectedRows.isNotEmpty && selectedRows.every((r) => r.status == 'unapproved');
    final canPay = selectedRows.isNotEmpty && selectedRows.every((r) => r.status == 'approved');
    final payTotal = selectedRows.fold<double>(0, (s, r) => s + (r.amount ?? 0));

    return AppPage(
      title: widget.vendorName ?? 'Vendor',
      actions: const [ThemeButton()],
      padded: false,
      bottomBar: _selected.isEmpty
          ? null
          : _SelectionBar(
              count: _selected.length,
              total: payTotal,
              busy: _busy,
              canPrice: canPrice,
              canApprove: canApprove,
              canPay: canPay,
              onClear: () => setState(() => _selected.clear()),
              onPrice: () => _priceSelected(selectedRows),
              onApprove: () => _approveSelected(selectedRows),
              onPay: () => _paySelected(selectedRows),
            ),
      body: AsyncView(
        value: ledger,
        onRetry: () => ref.invalidate(vendorLedgerProvider(widget.vendorId)),
        data: (rows) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              SectionHeader(
                'Ledger',
                trailing: AppButton.ghost(
                  label: 'Record payment',
                  icon: Icons.add,
                  onPressed: _busy ? null : _recordPayment,
                ),
              ),
              if (rows.isEmpty)
                const EmptyState(title: 'Nothing recorded yet.', icon: Icons.receipt_long_outlined, compact: true)
              else
                AppListGroup(
                  children: [
                    for (final e in rows)
                      _LedgerRow(entry: e, selected: _selected, onToggle: () => _toggleSelected(e.id)),
                  ],
                ),
              const SectionHeader('Damaged Thaans', top: 24),
              AsyncView(
                value: damaged,
                onRetry: () => ref.invalidate(vendorDamagedProvider(widget.vendorId)),
                isEmpty: (rows) => rows.isEmpty,
                emptyMessage: 'Nothing flagged damaged for this vendor.',
                data: (rows) => Column(
                  children: [
                    for (final d in rows)
                      _DamagedRow(
                        entry: d,
                        busy: _busy,
                        onAddress: () => _run(
                          () => ref.read(vendorRepositoryProvider).addressDamaged(d.id),
                          okMessage: 'Marked addressed.',
                        ),
                        onWriteOff: () => _writeOff(d),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.selected, required this.onToggle});
  final CoreVendorLedgerEntry entry;
  final Set<String> selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isSel = selected.contains(entry.id);

    final title = entry.isTransaction
        ? '${entry.stage} · ${entry.pieceCount} pcs'
        : 'Payment${entry.notes != null ? " — ${entry.notes}" : ""}';
    final subtitle = entry.baleCodes != null && entry.baleCodes!.isNotEmpty
        ? '${entry.date} · Bale ${entry.baleCodes!.join(", ")}'
        : entry.date;

    // The row itself has no "selected" look, so the tint sits behind it.
    return ColoredBox(
      color: isSel ? p.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: AppListRow(
        onTap: entry.isTransaction ? onToggle : null,
        title: title,
        subtitle: subtitle,
        leading: entry.isTransaction
            ? Icon(
                isSel ? Icons.check_box : Icons.check_box_outline_blank,
                size: 22,
                color: isSel ? p.primary : p.textMuted,
              )
            : null,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              entry.amount == null
                  ? 'Not priced'
                  : '${entry.isTransaction ? "+" : "−"}₹${entry.amount!.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                fontStyle: entry.amount == null ? FontStyle.italic : FontStyle.normal,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: entry.amount == null
                    ? p.textMuted
                    : entry.isTransaction
                        ? p.danger
                        : p.success,
              ),
            ),
            if (entry.isTransaction) ...[
              const SizedBox(height: 4),
              vendorTxnStatusBadge(entry.status),
            ],
          ],
        ),
      ),
    );
  }
}

class _DamagedRow extends StatelessWidget {
  const _DamagedRow({required this.entry, required this.busy, required this.onAddress, required this.onWriteOff});
  final CoreDamagedThaan entry;
  final bool busy;
  final VoidCallback onAddress;
  final VoidCallback onWriteOff;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardTitle(
              '${entry.thaanCode ?? "no code yet"} · Bale ${entry.baleCode}${entry.stage != null ? " · ${entry.stage}" : ""}',
              subtitle: 'Flagged ${entry.flaggedAt}${entry.flaggedByName != null ? " by ${entry.flaggedByName}" : ""}',
              trailing: damagedStatusBadge(entry.status),
            ),
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.notes!, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            ],
            if (entry.status != 'written_off') ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: entry.status == 'flagged'
                    ? AppButton.secondary(label: 'Mark addressed', expand: false, onPressed: busy ? null : onAddress)
                    : AppButton.danger(label: 'Write off', expand: false, onPressed: busy ? null : onWriteOff),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the selection can have done to it, pinned at the bottom. One
/// action at a time — Price, Approve or Pay, whichever the whole selection
/// qualifies for — beside Clear; just Clear when it qualifies for nothing.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.busy,
    required this.canPrice,
    required this.canApprove,
    required this.canPay,
    required this.onClear,
    required this.onPrice,
    required this.onApprove,
    required this.onPay,
  });
  final int count;
  final double total;
  final bool busy;
  final bool canPrice;
  final bool canApprove;
  final bool canPay;
  final VoidCallback onClear;
  final VoidCallback onPrice;
  final VoidCallback onApprove;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final note = '$count selected · ₹${total.toStringAsFixed(0)}';
    final clear = AppButton.secondary(label: 'Clear', onPressed: onClear);

    final AppButton? action = canPrice
        ? AppButton.primary(label: 'Price', busy: busy, onPressed: onPrice)
        : canApprove
            ? AppButton.primary(label: 'Approve', busy: busy, onPressed: onApprove)
            : canPay
                ? AppButton.primary(label: 'Pay', busy: busy, onPressed: onPay)
                : null;

    if (action == null) return BottomActionBar(note: note, primary: clear);
    return BottomActionBar(note: note, secondary: clear, primary: action);
  }
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.entries});
  final List<CoreVendorLedgerEntry> entries;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  final _rate = TextEditingController();

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pieces = widget.entries.fold<int>(0, (s, e) => s + (e.pieceCount ?? 0));
    final rateValue = double.tryParse(_rate.text);
    final preview = rateValue != null ? rateValue * pieces : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Rate per piece (₹)',
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        AppButton.primary(
          label: preview != null ? 'Price ₹${preview.toStringAsFixed(0)}' : 'Price',
          onPressed: rateValue == null || rateValue < 0 ? null : () => Navigator.pop(context, rateValue),
        ),
      ],
    );
  }
}

class _PayDraft {
  const _PayDraft({required this.paidOn, required this.method, required this.notes});
  final String paidOn;
  final String method;
  final String notes;
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.total});
  final double total;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

/// The API takes the date as YYYY-MM-DD; the field shows it the way the app does.
String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

class _PaySheetState extends State<_PaySheet> {
  DateTime _paidOn = DateTime.now();
  final _method = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _method.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDateField(
          label: 'Date',
          value: _paidOn,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          onChanged: (d) => setState(() => _paidOn = d),
        ),
        const SizedBox(height: 12),
        AppTextField(label: 'Method', controller: _method, hint: 'Cash, bank transfer — optional'),
        const SizedBox(height: 12),
        AppTextField(label: 'Notes', controller: _notes),
        const SizedBox(height: 16),
        AppButton.primary(
          label: 'Pay ₹${widget.total.toStringAsFixed(0)}',
          onPressed: () => Navigator.pop(
            context,
            _PayDraft(paidOn: _iso(_paidOn), method: _method.text.trim(), notes: _notes.text.trim()),
          ),
        ),
      ],
    );
  }
}

class _RecordPaymentDraft {
  const _RecordPaymentDraft({required this.amount, required this.paidOn, required this.method, required this.notes});
  final String amount;
  final String paidOn;
  final String method;
  final String notes;
}

class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet();

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final _amount = TextEditingController();
  DateTime _paidOn = DateTime.now();
  final _method = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _method.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Amount (₹)',
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        AppDateField(
          label: 'Date',
          value: _paidOn,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          onChanged: (d) => setState(() => _paidOn = d),
        ),
        const SizedBox(height: 12),
        AppTextField(label: 'Method', controller: _method, hint: 'Cash, bank transfer — optional'),
        const SizedBox(height: 12),
        AppTextField(label: 'Notes', controller: _notes),
        const SizedBox(height: 16),
        AppButton.primary(
          label: 'Add payment',
          onPressed: _amount.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _RecordPaymentDraft(
                      amount: _amount.text.trim(),
                      paidOn: _iso(_paidOn),
                      method: _method.text.trim(),
                      notes: _notes.text.trim(),
                    ),
                  ),
        ),
      ],
    );
  }
}
