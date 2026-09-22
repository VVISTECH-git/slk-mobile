import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'bale_providers.dart';

/// Kora to Shelf, step one: log a bale of raw cloth as it arrives.
///
/// Field-for-field parity with the web's Bale Intake drawer
/// (apps/web/src/app/bales/bales.tsx) — supplier, bill entry date, type,
/// bill details, quantity, unit, bale count, item, code, remarks. No
/// transporter field: the web dropped it as unused, so this does too.
///
/// Purely intake — finding a bale already on file to record Thaans cut
/// from it is a different job on a different screen, [RecordCuttingScreen]
/// (record_cutting_screen.dart): the two used to share one screen and that
/// read as one long form with an unrelated search box bolted to the
/// bottom of it, buried under fields that had nothing to do with cutting.
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

  final _invoiceNumber = TextEditingController();
  DateTime? _invoiceDate;
  final _invoiceAmount = TextEditingController();
  final _metresReceived = TextEditingController();
  final _baleCount = TextEditingController(text: '1');
  final _gradeCode = TextEditingController();
  final _notes = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _invoiceNumber.dispose();
    _invoiceAmount.dispose();
    _metresReceived.dispose();
    _baleCount.dispose();
    _gradeCode.dispose();
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
            invoiceNumber: _invoiceNumber.text.trim(),
            invoiceDate: _invoiceDate == null ? '' : DateFormat('yyyy-MM-dd').format(_invoiceDate!),
            invoiceAmount: _invoiceAmount.text.trim(),
            gradeCode: _gradeCode.text.trim(),
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
      _gradeCode.clear();
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

    return AppPage(
      title: 'Bale Intake',
      actions: [
        const ThemeButton(),
        AppIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(coreSuppliersProvider);
            ref.invalidate(coreClothItemsProvider);
          },
        ),
      ],
      padded: false,
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SupplierField(suppliers: suppliers, value: _supplierId, onChanged: (v) => setState(() => _supplierId = v)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DateField(
                  label: 'Bill entry date',
                  value: _billEntryDate,
                  onTap: () => _pickDate(_billEntryDate, (d) => setState(() => _billEntryDate = d)),
                ),
              ),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Bill No',
                  controller: _invoiceNumber,
                  helper: "Blank if it hasn't arrived.",
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: 'Bill Date',
                  value: _invoiceDate,
                  optional: true,
                  onTap: () => _pickDate(_invoiceDate ?? DateTime.now(), (d) => setState(() => _invoiceDate = d)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Bill amount',
            controller: _invoiceAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            prefixText: '₹ ',
            helper: "The bill's own total.",
          ),
          const Divider(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AppTextField(
                  label: 'Quantity received',
                  required: true,
                  controller: _metresReceived,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
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
          AppTextField(
            label: 'Number of bales',
            controller: _baleCount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _ItemField(items: items, value: _itemId, onChanged: (v) => setState(() => _itemId = v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Code',
                  controller: _gradeCode,
                  helper: 'identifier',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Remarks',
            controller: _notes,
            maxLines: 2,
            helper: 'Anything else worth recording.',
          ),
        ],
      ),
      bottomBar: BottomActionBar(
        primary: AppButton.primary(
          label: 'Save bale',
          icon: Icons.add_box_outlined,
          busy: _busy,
          onPressed: _save,
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
      loading: () => const Skeleton(height: 48, radius: 12),
      error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
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
      loading: () => const Skeleton(height: 48, radius: 12),
      error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
      data: (rows) => PickerField(
        label: 'Item',
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

/// A tappable date box with the same label-above shape as [AppTextField],
/// so a date and a text field side by side line up.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.optional = false});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              suffixIcon: Icon(Icons.calendar_today, size: 18, color: p.textSecondary),
            ),
            child: Text(
              value == null ? (optional ? 'Not yet' : 'Choose…') : DateFormat('d MMM yyyy').format(value!),
              style: TextStyle(
                fontSize: 16,
                color: value == null ? p.textMuted : p.text,
                fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
