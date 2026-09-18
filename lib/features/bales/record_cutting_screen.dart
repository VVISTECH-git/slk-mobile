import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import 'bale_providers.dart';

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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.p.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RecordThaansSheet(bale: bale),
    ).then((_) => ref.invalidate(coreBalesProvider));
  }

  @override
  Widget build(BuildContext context) {
    final bales = ref.watch(coreBalesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Cutting'),
        actions: [
          const ThemeButton(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(coreBalesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Search any bale by code',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(emptyMessage, textAlign: TextAlign.center, style: TextStyle(color: context.p.textSecondary)),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    if (_query.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(
                          'Waiting on cutting',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.p.textSecondary),
                        ),
                      ),
                    for (final b in shown) _BaleRow(bale: b, onTap: () => _openRecordSheet(b)),
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
    final p = context.p;
    final statusColor = switch (bale.status) {
      'cut' => p.success,
      'returned' => p.danger,
      'cutting_in_progress' => p.accent,
      _ => p.textSecondary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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
                      '${bale.itemName} · ${bale.metresReceived} ${bale.uom} · ${bale.billEntryDate}'
                      '${bale.thaanCount > 0 ? ' · ${bale.thaanCount} Thaan${bale.thaanCount == 1 ? '' : 's'} so far' : ''}',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(bale.status.replaceAll('_', ' '), style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                  if (onTap != null) Icon(Icons.chevron_right, size: 18, color: p.textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recording Thaans cut from one bale — reusable across more than one
/// recording in the same visit, since cutting can be partial (see the
/// decision doc's "Re-revised" note): record some, keep the sheet open,
/// record more, and only close it out with "Mark cutting complete" once
/// nothing more will be cut from this bale.
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Generate QR codes for ${_bale.code}?'),
        content: Text(
          "Assigns a permanent code to the $remaining Thaan${remaining == 1 ? '' : 's'} still waiting on one"
          '${already > 0 ? ' — the $already already coded ${already == 1 ? 'stays' : 'stay'} untouched' : ''}. '
          "This can't be undone — a code, once generated, is fixed.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

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

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_bale.code} · ${_bale.supplierName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 2),
          Text('${_bale.itemName} · ${_bale.metresReceived} ${_bale.uom}', style: TextStyle(fontSize: 13, color: p.textSecondary)),
          const SizedBox(height: 12),
          Text(
            _bale.thaanCount > 0
                ? '${_bale.thaanCount} Thaan${_bale.thaanCount == 1 ? '' : 's'} recorded so far.'
                : 'No Thaans recorded yet.',
            style: TextStyle(fontSize: 13, color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _count,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Thaans just cut',
              helperText: 'The whole bale, or only part of it — recording again later adds more.',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : _record,
            icon: _recording
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add),
            label: Text(_recording ? 'Recording…' : 'Record'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy || _bale.thaanCount == 0 ? null : _complete,
            icon: _completing
                ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                : const Icon(Icons.check_circle_outline),
            label: Text(_completing ? 'Completing…' : 'Mark cutting complete'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (_bale.thaanCount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Record at least one Thaan before this bale can be marked cut.',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
            ),
          const Divider(height: 28),
          OutlinedButton.icon(
            onPressed: busy || qrRemaining <= 0 ? null : _generateQr,
            icon: _generatingQr
                ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                : const Icon(Icons.qr_code_2),
            label: Text(_generatingQr ? 'Generating…' : 'Generate QR codes'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _bale.thaanCount == 0
                  ? "This bale hasn't been cut yet."
                  : qrRemaining <= 0
                      ? 'Every Thaan from this bale already has a code.'
                      : '$qrRemaining Thaan${qrRemaining == 1 ? '' : 's'} still waiting on a code.',
              style: TextStyle(fontSize: 12, color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
