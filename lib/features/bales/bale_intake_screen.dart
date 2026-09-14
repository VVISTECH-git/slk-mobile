import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import '../../widgets/theme_button.dart';
import 'bale_providers.dart';

/// Kora to Shelf, step one: log a bale of raw cloth as it arrives.
///
/// Field-for-field parity with the web's Bale Intake drawer
/// (apps/web/src/app/bales/bales.tsx) — supplier, bill entry date, type,
/// transporter, invoice details, quantity, unit, bale count, item, notes.
/// Cutting, QR codes and the vendor/handover pipeline are not built on
/// either client yet — this is the one step both have.
class BaleIntakeScreen extends ConsumerStatefulWidget {
  const BaleIntakeScreen({super.key});

  @override
  ConsumerState<BaleIntakeScreen> createState() => _BaleIntakeScreenState();
}

class _BaleIntakeScreenState extends ConsumerState<BaleIntakeScreen> {
  String? _supplierId;
  String? _type;
  String _uom = 'Mtrs';
  String? _itemId;
  DateTime _billEntryDate = DateTime.now();

  final _transporter = TextEditingController();
  final _invoiceNumber = TextEditingController();
  DateTime? _invoiceDate;
  final _invoiceAmount = TextEditingController();
  final _metresReceived = TextEditingController();
  final _baleCount = TextEditingController(text: '1');
  final _notes = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _transporter.dispose();
    _invoiceNumber.dispose();
    _invoiceAmount.dispose();
    _metresReceived.dispose();
    _baleCount.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid =>
      _supplierId != null &&
      _type != null &&
      _itemId != null &&
      (double.tryParse(_metresReceived.text) ?? 0) > 0;

  Future<void> _save() async {
    if (!_valid) {
      showError(context, 'Choose a supplier, type, item, and how much was received.');
      return;
    }

    setState(() => _busy = true);
    try {
      final message = await ref.read(baleRepositoryProvider).create(
            supplierId: _supplierId!,
            billEntryDate: DateFormat('yyyy-MM-dd').format(_billEntryDate),
            type: _type!,
            metresReceived: _metresReceived.text.trim(),
            uom: _uom,
            itemId: _itemId!,
            transporter: _transporter.text.trim(),
            invoiceNumber: _invoiceNumber.text.trim(),
            invoiceDate: _invoiceDate == null ? '' : DateFormat('yyyy-MM-dd').format(_invoiceDate!),
            invoiceAmount: _invoiceAmount.text.trim(),
            baleCount: _baleCount.text.trim().isEmpty ? '1' : _baleCount.text.trim(),
            notes: _notes.text.trim(),
          );
      if (!mounted) return;
      showOk(context, message);
      ref.invalidate(coreBalesProvider);
      _resetForNext();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Only what changes bale to bale is cleared — the supplier and item a
  /// delivery arrives with usually stay the same for the next one too.
  void _resetForNext() {
    setState(() {
      _metresReceived.clear();
      _baleCount.text = '1';
      _invoiceNumber.clear();
      _invoiceAmount.clear();
      _invoiceDate = null;
      _notes.clear();
    });
  }

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(coreSuppliersProvider);
    final items = ref.watch(coreClothItemsProvider);
    final bales = ref.watch(coreBalesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bale Intake'),
        actions: [
          const ThemeButton(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(coreSuppliersProvider);
              ref.invalidate(coreClothItemsProvider);
              ref.invalidate(coreBalesProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SupplierField(suppliers: suppliers, value: _supplierId, onChanged: (v) => setState(() => _supplierId = v)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _DateField(label: 'Bill entry date', value: _billEntryDate, onTap: () => _pickDate(_billEntryDate, (d) => setState(() => _billEntryDate = d)))),
              const SizedBox(width: 12),
              Expanded(
                child: PickerField(
                  label: 'Type',
                  value: _type,
                  options: [for (final t in kBaleTypes) PickerOption(t, t)],
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _transporter,
            decoration: const InputDecoration(labelText: 'Transporter', helperText: 'Optional — who delivered it.'),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _invoiceNumber,
                  decoration: const InputDecoration(labelText: 'Invoice number', helperText: "Blank if it hasn't arrived."),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _DateField(label: 'Invoice date', value: _invoiceDate, onTap: () => _pickDate(_invoiceDate ?? DateTime.now(), (d) => setState(() => _invoiceDate = d)), optional: true)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invoiceAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Invoice amount', prefixText: '₹ ', helperText: "The bill's own total."),
          ),
          const Divider(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _metresReceived,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Quantity received *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PickerField(
                  label: 'Unit',
                  value: _uom,
                  options: [for (final u in kBaleUoms) PickerOption(u, u)],
                  onChanged: (v) => setState(() => _uom = v ?? 'Mtrs'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baleCount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Number of bales'),
          ),
          const SizedBox(height: 12),
          _ItemField(items: items, value: _itemId, onChanged: (v) => setState(() => _itemId = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes', helperText: 'Anything else worth recording.'),
          ),
          const Divider(height: 32),
          Text('Recent bales', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.p.text)),
          const SizedBox(height: 8),
          AsyncView<List<CoreBale>>(
            value: bales,
            emptyMessage: 'No bales logged yet.',
            isEmpty: (d) => d.isEmpty,
            loading: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator())),
            onRetry: () => ref.invalidate(coreBalesProvider),
            data: (rows) => Column(children: [for (final b in rows.take(10)) _BaleRow(bale: b)]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_box_outlined),
            label: Text(_busy ? 'Saving…' : 'Save bale'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}

class _SupplierField extends StatelessWidget {
  const _SupplierField({required this.suppliers, required this.value, required this.onChanged});

  final AsyncValue<List<CoreSupplier>> suppliers;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return suppliers.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e', style: TextStyle(color: context.p.danger)),
      data: (rows) => PickerField(
        label: 'Supplier',
        value: value,
        options: [
          for (final s in rows.where((s) => s.status == 'active' || s.id == value))
            PickerOption(s.id, s.status == 'inactive' ? '${s.name} (inactive)' : s.name),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _ItemField extends StatelessWidget {
  const _ItemField({required this.items, required this.value, required this.onChanged});

  final AsyncValue<List<CoreClothItem>> items;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return items.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e', style: TextStyle(color: context.p.danger)),
      data: (rows) => PickerField(
        label: 'Item',
        hint: 'Not on the list? Add it from slk-core first.',
        value: value,
        options: [
          for (final i in rows.where((i) => i.status == 'active' || i.id == value))
            PickerOption(i.id, i.status == 'inactive' ? '${i.name} (inactive)' : i.name),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.optional = false});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today, size: 18)),
        child: Text(
          value == null ? (optional ? 'Not yet' : 'Choose…') : DateFormat('d MMM yyyy').format(value!),
          style: TextStyle(color: value == null ? context.p.textMuted : context.p.text, fontWeight: value == null ? FontWeight.w400 : FontWeight.w600),
        ),
      ),
    );
  }
}

class _BaleRow extends StatelessWidget {
  const _BaleRow({required this.bale});

  final CoreBale bale;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final statusColor = switch (bale.status) {
      'cut' => p.success,
      'returned' => p.danger,
      _ => p.textSecondary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${bale.code} · ${bale.supplierName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${bale.itemName} · ${bale.metresReceived} ${bale.uom} · ${bale.billEntryDate}',
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Text(bale.status.replaceAll('_', ' '), style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
