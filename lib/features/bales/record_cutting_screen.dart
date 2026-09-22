import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'bale_providers.dart';
import 'thaan_labels_screen.dart';

/// Kora to Shelf: recording Thaans cut from a bale already on file.
///
/// Its own screen, not a section bolted onto [BaleIntakeScreen] —
/// cutting is a different job, done at a different time (often days after
/// the bale was received), by whoever is standing at the cutting table
/// rather than whoever received the delivery. Sharing one screen meant
/// scrolling past an entire, unrelated intake form to reach a search box.
///
/// Shows the bales actually waiting on cutting by default — nobody should
/// have to already know a bale's code just to see what's left to cut —
/// and narrows to a code search only once something is typed, the same
/// way a phone number contact search works.
class RecordCuttingScreen extends ConsumerStatefulWidget {
  const RecordCuttingScreen({super.key});

  @override
  ConsumerState<RecordCuttingScreen> createState() => _RecordCuttingScreenState();
}

class _RecordCuttingScreenState extends ConsumerState<RecordCuttingScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openRecordSheet(CoreBale bale) {
    if (bale.status == 'cut' || bale.status == 'returned') {
      showError(context, '${bale.code} is already ${bale.status == 'cut' ? 'cut' : 'returned'} — nothing more to record.');
      return;
    }
    showAppSheet<void>(
      context,
      title: '${bale.code} · ${bale.supplierName}',
      subtitle: '${bale.itemName} · ${bale.metresReceived} ${bale.uom}',
      child: _RecordThaansSheet(bale: bale),
    ).then((_) => ref.invalidate(coreBalesProvider));
  }

  @override
  Widget build(BuildContext context) {
    final bales = ref.watch(coreBalesProvider);

    return AppPage(
      title: 'Record Cutting',
      actions: [
        const ThemeButton(),
        AppIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(coreBalesProvider),
        ),
      ],
      padded: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: AppTextField(
              label: 'Search',
              hint: 'Search any bale by code',
              controller: _search,
              textCapitalization: TextCapitalization.characters,
              suffix: _query.isEmpty
                  ? null
                  : AppIconButton(
                      icon: Icons.clear,
                      tooltip: 'Clear',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: AsyncView<List<CoreBale>>(
              value: bales,
              onRetry: () => ref.invalidate(coreBalesProvider),
              data: (rows) {
                final List<CoreBale> shown;
                final String emptyMessage;
                if (_query.isEmpty) {
                  shown = rows.where((b) => b.status == 'awaiting_cutting' || b.status == 'cutting_in_progress').toList();
                  emptyMessage = 'Nothing is waiting on cutting right now.';
                } else {
                  final q = _query.toLowerCase();
                  shown = rows.where((b) => b.code.toLowerCase().contains(q)).toList();
                  emptyMessage = 'No bale matches "$_query".';
                }

                if (shown.isEmpty) {
                  return EmptyState(icon: Icons.content_cut, title: emptyMessage);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (_query.isEmpty) SectionHeader('Waiting on cutting', top: 4, trailing: Text('${shown.length}')),
                    AppListGroup(
                      children: [for (final b in shown) _BaleRow(bale: b, onTap: () => _openRecordSheet(b))],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BaleRow extends StatelessWidget {
  const _BaleRow({required this.bale, this.onTap});

  final CoreBale bale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (bale.status) {
      'cut' => BadgeTone.success,
      'returned' => BadgeTone.danger,
      'cutting_in_progress' => BadgeTone.warning,
      _ => BadgeTone.neutral,
    };

    return AppListRow(
      title: '${bale.code} · ${bale.supplierName}',
      subtitle: '${bale.itemName} · ${bale.metresReceived} ${bale.uom} · ${bale.billEntryDate}'
          '${bale.thaanCount > 0 ? ' · ${bale.thaanCount} Thaan${bale.thaanCount == 1 ? '' : 's'} so far' : ''}',
      trailing: StatusBadge(bale.status.replaceAll('_', ' '), tone: tone),
      chevron: onTap != null,
      onTap: onTap,
    );
  }
}

/// Recording Thaans cut from one bale — reusable across more than one
/// recording in the same visit, since cutting can be partial (see the
/// decision doc's "Re-revised" note): record some, keep the sheet open,
/// record more, and only close it out with "Mark cutting complete" once
/// nothing more will be cut from this bale.
///
/// Rendered inside [showAppSheet], which supplies the grabber, the bale's
/// title line and the keyboard inset — this is only the sheet's content.
class _RecordThaansSheet extends ConsumerStatefulWidget {
  const _RecordThaansSheet({required this.bale});
  final CoreBale bale;

  @override
  ConsumerState<_RecordThaansSheet> createState() => _RecordThaansSheetState();
}

class _RecordThaansSheetState extends ConsumerState<_RecordThaansSheet> {
  late CoreBale _bale;
  final _count = TextEditingController();

  /// Minted once per attempt and reused across a retry of that same attempt
  /// — the same idempotency-key discipline `new_record_screen.dart` follows.
  /// Cleared only after a confirmed success, at which point the next
  /// recording is a genuinely new one and needs its own key.
  String? _recordKey;

  bool _recording = false;
  bool _completing = false;
  bool _generatingQr = false;

  @override
  void initState() {
    super.initState();
    _bale = widget.bale;
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final count = _count.text.trim();
    if (!(int.tryParse(count) != null && int.parse(count) > 0)) {
      showError(context, 'Enter how many Thaans were just cut.');
      return;
    }

    _recordKey ??= idempotencyKey();

    setState(() => _recording = true);
    try {
      final message = await ref.read(baleRepositoryProvider).recordThaans(
            baleId: _bale.id,
            thaanCount: count,
            key: _recordKey!,
          );
      if (!mounted) return;
      showOk(context, message);
      setState(() {
        _bale = CoreBale(
          id: _bale.id,
          code: _bale.code,
          supplierName: _bale.supplierName,
          type: _bale.type,
          metresReceived: _bale.metresReceived,
          uom: _bale.uom,
          itemName: _bale.itemName,
          baleCount: _bale.baleCount,
          status: 'cutting_in_progress',
          billEntryDate: _bale.billEntryDate,
          thaanCount: _bale.thaanCount + int.parse(count),
          qrGeneratedCount: _bale.qrGeneratedCount,
        );
        _count.clear();
      });
      _recordKey = null; // that attempt succeeded; the next one is a new intent
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _complete() async {
    setState(() => _completing = true);
    try {
      final message = await ref.read(baleRepositoryProvider).markCuttingComplete(_bale.id);
      if (!mounted) return;
      showOk(context, message);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _generateQr() async {
    final remaining = _bale.thaanCount - _bale.qrGeneratedCount;
    final already = _bale.qrGeneratedCount;
    final ok = await showConfirmDialog(
      context,
      title: 'Generate QR codes for ${_bale.code}?',
      message: "Assigns a permanent code to the $remaining Thaan${remaining == 1 ? '' : 's'} still waiting on one"
          '${already > 0 ? ' — the $already already coded ${already == 1 ? 'stays' : 'stay'} untouched' : ''}. '
          "This can't be undone — a code, once generated, is fixed.",
      confirmLabel: 'Generate',
    );
    if (!ok || !mounted) return;

    setState(() => _generatingQr = true);
    try {
      final message = await ref.read(baleRepositoryProvider).generateQrCodes(_bale.id);
      if (!mounted) return;
      showOk(context, message);
      setState(() {
        _bale = CoreBale(
          id: _bale.id,
          code: _bale.code,
          supplierName: _bale.supplierName,
          type: _bale.type,
          metresReceived: _bale.metresReceived,
          uom: _bale.uom,
          itemName: _bale.itemName,
          baleCount: _bale.baleCount,
          status: _bale.status,
          billEntryDate: _bale.billEntryDate,
          thaanCount: _bale.thaanCount,
          qrGeneratedCount: _bale.thaanCount,
        );
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _generatingQr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final busy = _recording || _completing || _generatingQr;
    final qrRemaining = _bale.thaanCount - _bale.qrGeneratedCount;
    final hintStyle = TextStyle(fontSize: 12, color: p.textMuted);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineNotice(
          _bale.thaanCount > 0
              ? '${_bale.thaanCount} Thaan${_bale.thaanCount == 1 ? '' : 's'} recorded so far.'
              : 'No Thaans recorded yet.',
          icon: Icons.content_cut,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Thaans just cut',
          controller: _count,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          helper: 'The whole bale, or only part of it — recording again later adds more.',
        ),
        const SizedBox(height: 14),
        AppButton.primary(
          label: 'Record',
          icon: Icons.add,
          busy: _recording,
          onPressed: busy ? null : _record,
        ),
        const SizedBox(height: 10),
        AppButton.secondary(
          label: 'Mark cutting complete',
          icon: Icons.check_circle_outline,
          busy: _completing,
          onPressed: busy || _bale.thaanCount == 0 ? null : _complete,
        ),
        if (_bale.thaanCount == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Record at least one Thaan before this bale can be marked cut.', style: hintStyle),
          ),
        const SectionHeader('QR codes', top: 20),
        InlineNotice(
          _bale.thaanCount == 0
              ? "This bale hasn't been cut yet."
              : qrRemaining <= 0
                  ? 'Every Thaan from this bale already has a code.'
                  : '$qrRemaining Thaan${qrRemaining == 1 ? '' : 's'} still waiting on a code.',
          icon: Icons.qr_code_2,
        ),
        const SizedBox(height: 10),
        AppButton.secondary(
          label: 'Generate QR codes',
          icon: Icons.qr_code_2,
          busy: _generatingQr,
          onPressed: busy || qrRemaining <= 0 ? null : _generateQr,
        ),
        const SizedBox(height: 10),
        AppButton.secondary(
          label: 'Print QR codes',
          icon: Icons.print_outlined,
          onPressed: busy || _bale.qrGeneratedCount == 0
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ThaanLabelsScreen(baleId: _bale.id)),
                  ),
        ),
        if (_bale.qrGeneratedCount == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('No Thaans here have a QR code yet.', style: hintStyle),
          ),
      ],
    );
  }
}
