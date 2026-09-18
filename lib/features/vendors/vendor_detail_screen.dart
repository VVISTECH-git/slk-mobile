import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
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
    final rate = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RateSheet(entries: selectedRows),
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
    final draft = await showModalBottomSheet<_PayDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaySheet(total: total),
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
    final draft = await showModalBottomSheet<_RecordPaymentDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RecordPaymentSheet(),
    );
    if (draft == null) return;
    await _run(
      () => ref.read(vendorRepositoryProvider).recordPayment(
            vendorId: widget.vendorId,
            amount: draft.amount,
            paidOn: draft.paidOn,
            method: draft.method,
            notes: draft.notes,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final ledger = ref.watch(vendorLedgerProvider(widget.vendorId));
    final damaged = ref.watch(vendorDamagedProvider(widget.vendorId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.vendorName ?? 'Vendor'), actions: const [ThemeButton()]),
      body: AsyncView(
        value: ledger,
        onRetry: () => ref.invalidate(vendorLedgerProvider(widget.vendorId)),
        data: (rows) {
          final txns = rows.where((r) => r.isTransaction).toList();
          final selectedRows = txns.where((r) => _selected.contains(r.id)).toList();

          final canPrice = selectedRows.isNotEmpty &&
              selectedRows.every((r) => r.status == 'needs_pricing') &&
              selectedRows.every((r) => r.stage == selectedRows.first.stage);
          final canApprove = selectedRows.isNotEmpty && selectedRows.every((r) => r.status == 'unapproved');
          final canPay = selectedRows.isNotEmpty && selectedRows.every((r) => r.status == 'approved');
          final payTotal = selectedRows.fold<double>(0, (s, r) => s + (r.amount ?? 0));

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ledger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.text)),
                        TextButton.icon(
                          onPressed: _busy ? null : _recordPayment,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Record payment'),
                        ),
                      ],
                    ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Nothing recorded yet.', style: TextStyle(color: p.textSecondary)),
                      )
                    else
                      for (final e in rows)
                        _LedgerRow(entry: e, selected: _selected, onToggle: () => _toggleSelected(e.id)),
                    const SizedBox(height: 24),
                    Text('Damaged Thaans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.text)),
                    const SizedBox(height: 6),
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
                              onWriteOff: () => _run(
                                () => ref.read(vendorRepositoryProvider).writeOffDamaged(d.id),
                                okMessage: 'Written off.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_selected.isNotEmpty)
                _SelectionBar(
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
    return InkWell(
      onTap: entry.isTransaction ? onToggle : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? p.primary.withValues(alpha: 0.08) : p.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? p.primary : p.border),
        ),
        child: Row(
          children: [
            if (entry.isTransaction)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  isSel ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: isSel ? p.primary : p.textMuted,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.isTransaction
                        ? '${entry.stage} · ${entry.pieceCount} pcs'
                        : 'Payment${entry.notes != null ? " — ${entry.notes}" : ""}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: p.text, fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.baleCodes != null && entry.baleCodes!.isNotEmpty
                        ? '${entry.date} · Bale ${entry.baleCodes!.join(", ")}'
                        : entry.date,
                    style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Column(
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
                    color: entry.amount == null
                        ? p.textMuted
                        : entry.isTransaction
                            ? p.danger
                            : p.success,
                  ),
                ),
                if (entry.isTransaction) ...[
                  const SizedBox(height: 3),
                  StatusChip(
                    label: vendorTxnStatusLabel(entry.status),
                    color: vendorTxnStatusColor(context, entry.status),
                  ),
                ],
              ],
            ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${entry.thaanCode ?? "no code yet"} · Bale ${entry.baleCode}${entry.stage != null ? " · ${entry.stage}" : ""}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.text),
                ),
              ),
              StatusChip(label: damagedStatusLabel(entry.status), color: damagedStatusColor(context, entry.status)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Flagged ${entry.flaggedAt}${entry.flaggedByName != null ? " by ${entry.flaggedByName}" : ""}',
            style: TextStyle(color: p.textSecondary, fontSize: 11.5),
          ),
          if (entry.notes != null && entry.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(entry.notes!, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
          ],
          if (entry.status != 'written_off') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: busy ? null : (entry.status == 'flagged' ? onAddress : onWriteOff),
                child: Text(entry.status == 'flagged' ? 'Mark addressed' : 'Write off'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
    final p = context.p;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: p.surface2,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count selected · ₹${total.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: p.text),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Clear')),
            if (canPrice)
              FilledButton.tonal(onPressed: busy ? null : onPrice, child: const Text('Price'))
            else if (canApprove)
              FilledButton.tonal(onPressed: busy ? null : onApprove, child: const Text('Approve'))
            else if (canPay)
              FilledButton(onPressed: busy ? null : onPay, child: const Text('Pay')),
          ],
        ),
      ),
    );
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
    final p = context.p;
    final pieces = widget.entries.fold<int>(0, (s, e) => s + (e.pieceCount ?? 0));
    final rateValue = double.tryParse(_rate.text);
    final preview = rateValue != null ? rateValue * pieces : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Price ${widget.entries.length} transaction${widget.entries.length == 1 ? "" : "s"}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          Text('${widget.entries.first.stage} · $pieces piece${pieces == 1 ? "" : "s"} total.',
              style: TextStyle(color: p.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Rate per piece (₹)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: rateValue == null || rateValue < 0 ? null : () => Navigator.pop(context, rateValue),
              child: Text(preview != null ? 'Price ₹${preview.toStringAsFixed(0)}' : 'Price'),
            ),
          ),
        ],
      ),
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

class _PaySheetState extends State<_PaySheet> {
  late String _paidOn = DateTime.now().toIso8601String().substring(0, 10);
  final _method = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _method.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_paidOn) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paidOn = picked.toIso8601String().substring(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pay ₹${widget.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
              child: Text(_paidOn),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _method,
            decoration: const InputDecoration(labelText: 'Method', hintText: 'Cash, bank transfer — optional', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _PayDraft(paidOn: _paidOn, method: _method.text.trim(), notes: _notes.text.trim()),
              ),
              child: Text('Pay ₹${widget.total.toStringAsFixed(0)}'),
            ),
          ),
        ],
      ),
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
  late String _paidOn = DateTime.now().toIso8601String().substring(0, 10);
  final _method = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _method.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_paidOn) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paidOn = picked.toIso8601String().substring(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Record payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          Text(
            "Against this vendor's running balance — not tied to any particular transaction.",
            style: TextStyle(color: context.p.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
              child: Text(_paidOn),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _method,
            decoration: const InputDecoration(labelText: 'Method', hintText: 'Cash, bank transfer — optional', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _amount.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        _RecordPaymentDraft(
                          amount: _amount.text.trim(),
                          paidOn: _paidOn,
                          method: _method.text.trim(),
                          notes: _notes.text.trim(),
                        ),
                      ),
              child: const Text('Add payment'),
            ),
          ),
        ],
      ),
    );
  }
}
