import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../handovers/handover_providers.dart' show coreVendorsProvider;
import '../pos/barcode_scan_screen.dart';
import 'thaan_providers.dart';

/// Scan (camera) or type a Thaan's code → see its bale, stage and status.
/// Read-only — this never moves a Thaan anywhere, unlike Handovers' own
/// scanning, which only ever adds a Thaan to a batch, never shows what it
/// actually is. Same manual-entry-plus-camera shape as Identify Item and
/// Stock Records use for pieces, so scanning works the same way everywhere
/// in the app.
class ScanThaanScreen extends ConsumerStatefulWidget {
  const ScanThaanScreen({super.key});

  @override
  ConsumerState<ScanThaanScreen> createState() => _ScanThaanScreenState();
}

class _ScanThaanScreenState extends ConsumerState<ScanThaanScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _lookingUp;
  CoreThaan? _result;
  String? _resultCode;
  String? _notFoundCode;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _lookingUp = code;
      _result = null;
      _resultCode = null;
      _notFoundCode = null;
    });
    try {
      final thaan = await ref.read(thaanRepositoryProvider).lookupByCode(code);
      setState(() {
        _result = thaan;
        _resultCode = code;
      });
    } on ApiException catch (e) {
      if (e.status == 404) {
        setState(() => _notFoundCode = code);
      } else if (mounted) {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
      _field.clear();
      _focus.requestFocus();
    }
  }

  Future<void> _cameraScan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen(title: 'Scan a Thaan')),
    );
    if (code != null) await _lookup(code);
  }

  Future<void> _flagDamaged(CoreThaan thaan, String code) async {
    final flagged = await showAppSheet<bool>(
      context,
      title: 'Flag $code damaged',
      subtitle: thaan.lastStage != null
          ? 'Last at ${thaan.lastStage}${thaan.lastVendorName != null ? ' · ${thaan.lastVendorName}' : ''}.'
          : 'No stage recorded for this Thaan yet.',
      child: _FlagDamagedSheet(code: code, thaan: thaan),
    );
    if (flagged == true && mounted) {
      showOk(context, '$code marked damaged.');
      await _lookup(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Scan a Thaan',
      actions: const [ThemeButton()],
      padded: false,
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(
            label: 'Thaan code',
            hint: 'e.g. T00002048',
            helper: "Scan a printed label's QR with the camera, or type its code.",
            controller: _field,
            focusNode: _focus,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: _lookup,
          ),
          const SizedBox(height: 16),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(24),
              child: LoadingState(message: 'Looking up ${_lookingUp ?? 'the Thaan'}…'),
            ),
          if (_notFoundCode != null && !_busy)
            EmptyState(
              compact: true,
              icon: Icons.search_off,
              title: 'No Thaan found for "$_notFoundCode".',
            ),
          if (_result != null && !_busy)
            _ThaanCard(
              thaan: _result!,
              onFlagDamaged: () => _flagDamaged(_result!, _resultCode!),
            ),
        ],
      ),
      bottomBar: BottomActionBar(
        primary: AppButton.primary(
          label: 'Scan with camera',
          icon: Icons.photo_camera_outlined,
          onPressed: _busy ? null : _cameraScan,
        ),
      ),
    );
  }
}

class _ThaanCard extends StatelessWidget {
  const _ThaanCard({required this.thaan, required this.onFlagDamaged});
  final CoreThaan thaan;
  final VoidCallback onFlagDamaged;

  @override
  Widget build(BuildContext context) {
    final t = thaan;

    return AppCard(
      emphasis: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitle(t.code ?? '—', trailing: StatusBadge.pipeline(t.pipelineStatus)),
          if (t.voidedAt != null) ...[
            const SizedBox(height: 10),
            InlineNotice('Voided on ${t.voidedAt}', icon: Icons.block, warning: true),
          ],
          const Divider(height: 20),
          KeyValueRow('Bale', t.baleCode, mono: true),
          KeyValueRow('Supplier', t.supplierName),
          KeyValueRow('Item', '${t.itemName} · ${t.baleType}'),
          if (t.gradeCode != null) KeyValueRow('Grade', t.gradeCode!),
          ..._clothRows(),
          KeyValueRow('Bale status', _baleStatusLabel(t.baleStatus)),
          KeyValueRow('Bale received', t.billEntryDate),
          if (t.transporter != null) KeyValueRow('Transporter', t.transporter!),
          if (t.invoiceNumber != null) KeyValueRow('Invoice', t.invoiceNumber!),
          if (t.invoiceDate != null) KeyValueRow('Invoice date', t.invoiceDate!),
          if (t.invoiceAmount != null) KeyValueRow('Invoice amount', '₹${t.invoiceAmount!.toStringAsFixed(2)}'),
          KeyValueRow('Bale total', '${_num(t.metresReceived)} ${t.uom}${t.baleCount > 1 ? ' · ${t.baleCount} bales' : ''}'),
          if (t.perThaanMetres != null) KeyValueRow('This Thaan\'s share', '${_num(t.perThaanMetres!)} ${t.uom}'),
          KeyValueRow('Second print', t.needsSecondPrint ? 'Yes' : 'No'),
          if (t.baleNotes != null && t.baleNotes!.isNotEmpty) KeyValueRow('Bale notes', t.baleNotes!),
          KeyValueRow('QR generated', t.qrGeneratedAt ?? 'Not yet'),
          if (t.voidedAt == null) ...[
            const SizedBox(height: 14),
            AppButton.danger(
              label: 'Flag as damaged',
              icon: Icons.report_gmailerrorred_outlined,
              onPressed: onFlagDamaged,
            ),
          ],
        ],
      ),
    );
  }

  /// The cloth item's properties — only the ones it actually fixed.
  List<Widget> _clothRows() {
    final t = thaan;
    final rows = <(String, String?)>[
      ('Fibre', t.fibre),
      ('Textile material', t.textileMaterial),
      ('Weave', t.weave),
      ('Production', t.productionMethod),
      ('Audience', t.audience),
      ('Border', [t.borderStyle, t.borderHeight].whereType<String>().join(', ')),
      ('Pallu', t.pallu),
      (
        'Blouse',
        t.hasBlouse == null
            ? null
            : t.hasBlouse!
                ? ([t.blouseStyle, t.blouseMaterial].whereType<String>().join(', ').isEmpty
                    ? 'Yes'
                    : [t.blouseStyle, t.blouseMaterial].whereType<String>().join(', '))
                : 'No'
      ),
      ('Saree length', t.sareeLengthCm == null ? null : '${_num(t.sareeLengthCm!)} cm'),
      ('Saree width', t.sareeWidthCm == null ? null : '${_num(t.sareeWidthCm!)} cm'),
      ('Pallu length', t.palluLengthCm == null ? null : '${_num(t.palluLengthCm!)} cm'),
      ('Blouse length', t.blouseLengthCm == null ? null : '${_num(t.blouseLengthCm!)} cm'),
    ];
    return [
      for (final (k, v) in rows)
        if (v != null && v.isNotEmpty) KeyValueRow(k, v),
    ];
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static String _baleStatusLabel(String s) => switch (s) {
        'awaiting_cutting' => 'Awaiting cutting',
        'cutting_in_progress' => 'Cutting in progress',
        'cut' => 'Cut',
        'returned' => 'Returned',
        _ => s,
      };
}

/// Flags [code] damaged. Pre-fills the vendor from [thaan]'s own
/// `lastVendorId` (whoever most recently held it) — auto-derived, but
/// changeable here, since the derived guess isn't always who's actually
/// responsible.
///
/// Rendered inside [showAppSheet], which supplies the grabber, title,
/// last-stage subtitle and keyboard inset — this is only the content.
class _FlagDamagedSheet extends ConsumerStatefulWidget {
  const _FlagDamagedSheet({required this.code, required this.thaan});
  final String code;
  final CoreThaan thaan;

  @override
  ConsumerState<_FlagDamagedSheet> createState() => _FlagDamagedSheetState();
}

class _FlagDamagedSheetState extends ConsumerState<_FlagDamagedSheet> {
  String? _vendorId;
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _vendorId = widget.thaan.lastVendorId;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(thaanRepositoryProvider).flagDamaged(
            code: widget.code,
            vendorId: _vendorId,
            notes: _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = ref.watch(coreVendorsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        vendors.when(
          loading: () => const Skeleton(height: 48, radius: 12),
          error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
          data: (rows) => PickerField(
            label: 'Vendor',
            value: _vendorId,
            hint: 'None (in-house or unknown)',
            allowClear: true,
            options: [for (final v in rows) PickerOption(v.id, v.name)],
            onChanged: (v) => setState(() => _vendorId = v),
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: 'Notes',
          hint: "What's wrong with it — optional",
          controller: _notes,
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        AppButton.danger(
          label: 'Flag as damaged',
          icon: Icons.report_gmailerrorred,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
