import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import '../../widgets/theme_button.dart';
import '../production/continuous_scanner.dart';
import 'handover_providers.dart';

const _inHouse = '';

/// Kora to Shelf, step three: a Thaan's trip through the stage pipeline.
///
/// Everything here happens by scanning a Thaan's own QR code — the same
/// accountability the web screen (apps/web/src/app/handovers/handovers.tsx)
/// enforces: a material handler hands a Thaan to a vendor by scanning it,
/// not by ticking a box in a list they might not have the physical piece in
/// front of. Field-for-field the same Send/Receive split, on a phone rather
/// than a desktop's own camera — see the "why mobile" note in this
/// session's own history for why that split matters here specifically.
class HandoversScreen extends StatefulWidget {
  const HandoversScreen({super.key});

  @override
  State<HandoversScreen> createState() => _HandoversScreenState();
}

class _HandoversScreenState extends State<HandoversScreen> {
  bool _sending = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Handovers'),
        actions: const [ThemeButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Send'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: false, label: Text('Receive'), icon: Icon(Icons.south_west)),
              ],
              selected: {_sending},
              onSelectionChanged: (s) => setState(() => _sending = s.first),
            ),
          ),
          Expanded(child: _sending ? const _SendPanel() : const _ReceivePanel()),
        ],
      ),
    );
  }
}

/// A resolved scan the reader hasn't sent/received yet, plus whatever went
/// wrong resolving codes that didn't make it into the batch.
class _ScanOutcome<T> {
  _ScanOutcome({required this.resolved, required this.problems});
  final List<T> resolved;
  final List<String> problems;
}

// ── Send ─────────────────────────────────────────────────────────────────

class _SendPanel extends ConsumerStatefulWidget {
  const _SendPanel();

  @override
  ConsumerState<_SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends ConsumerState<_SendPanel> {
  String? _stage;
  String _vendorId = _inHouse;
  final _items = <CoreThaanForSend>[];
  bool _busy = false;

  Future<void> _scan() async {
    final codes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const ContinuousScanScreen(title: 'Scan to send'),
      ),
    );
    if (codes == null || codes.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final outcome = await _resolve(codes);
    if (!mounted) return;
    setState(() {
      _items.addAll(outcome.resolved);
      _busy = false;
    });
    if (outcome.problems.isNotEmpty) _showProblems(outcome.problems);
  }

  /// Resolves each newly scanned code against `/handovers/lookup-send`, in
  /// order. The first success locks [_stage] — read synchronously off the
  /// local variable, not the not-yet-rebuilt widget state — so the rest of
  /// this same batch validates against that stage rather than each one
  /// auto-detecting independently, which is what would let two different
  /// physical batches get scanned into one send by mistake.
  Future<_ScanOutcome<CoreThaanForSend>> _resolve(List<String> codes) async {
    final repo = ref.read(handoverRepositoryProvider);
    String? stage = _stage;
    final resolved = <CoreThaanForSend>[];
    final problems = <String>[];

    for (final code in codes) {
      if (_items.any((t) => t.code == code) || resolved.any((t) => t.code == code)) continue;
      try {
        final result = await repo.lookupForSend(code: code, stage: stage);
        stage ??= result.stage;
        resolved.add(result.thaan);
      } catch (e) {
        problems.add('$code — $e');
      }
    }

    if (stage != null) _stage = stage;
    return _ScanOutcome(resolved: resolved, problems: problems);
  }

  void _showProblems(List<String> problems) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Not sent',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.p.danger),
              ),
              const SizedBox(height: 8),
              for (final p in problems) Text(p, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSend() async {
    if (_items.isEmpty || _stage == null) return;
    final stage = _stage!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Send ${_items.length} Thaan${_items.length == 1 ? '' : 's'} for $stage?'),
        content: Text(
          _vendorId == _inHouse
              ? 'Going to in-house.'
              : 'Going to ${ref.read(coreVendorsProvider).value?.firstWhere((v) => v.id == _vendorId).name ?? 'that vendor'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(handoverRepositoryProvider).sendBatch(
            stage: stage,
            vendorId: _vendorId == _inHouse ? null : _vendorId,
            thaanIds: [for (final t in _items) t.id],
          );
      if (!mounted) return;
      showOk(context, message);
      setState(() => _items.clear());
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
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: PickerField(
                  label: 'Stage',
                  value: _stage ?? _inHouse,
                  hint: 'Auto — first scan decides',
                  allowClear: true,
                  options: [
                    PickerOption(_inHouse, 'Auto — first scan decides'),
                    ...plainOptions(kSendableStages),
                  ],
                  onChanged: (v) => setState(() {
                    _stage = (v == null || v == _inHouse) ? null : v;
                    _items.clear();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: vendors.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e', style: TextStyle(color: context.p.danger)),
                  data: (rows) => PickerField(
                    label: 'Vendor',
                    value: _vendorId,
                    options: [
                      const PickerOption(_inHouse, 'In-house (no vendor)'),
                      for (final v in rows) PickerOption(v.id, v.name),
                    ],
                    onChanged: (v) => setState(() {
                      _vendorId = v ?? _inHouse;
                      _items.clear();
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text('Nothing scanned yet.', style: TextStyle(color: context.p.textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = _items[i];
                    return ListTile(
                      dense: true,
                      title: Text(t.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                      subtitle: Text('${t.baleCode} · ${t.itemName}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _items.removeAt(i)),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _items.isEmpty || _stage == null ? null : _confirmSend,
                    icon: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.north_east),
                    label: Text('Send${_items.isNotEmpty ? ' ${_items.length}' : ''}'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Receive ──────────────────────────────────────────────────────────────

class _ReceivePanel extends ConsumerStatefulWidget {
  const _ReceivePanel();

  @override
  ConsumerState<_ReceivePanel> createState() => _ReceivePanelState();
}

class _ReceivePanelState extends ConsumerState<_ReceivePanel> {
  final _items = <CoreThaanForReceive>[];
  bool _busy = false;

  Future<void> _scan() async {
    final codes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const ContinuousScanScreen(title: "Scan what's coming back"),
      ),
    );
    if (codes == null || codes.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(handoverRepositoryProvider);
    final resolved = <CoreThaanForReceive>[];
    final problems = <String>[];

    for (final code in codes) {
      if (_items.any((t) => t.code == code)) continue;
      try {
        resolved.add(await repo.lookupForReceive(code));
      } catch (e) {
        problems.add('$code — $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _items.addAll(resolved);
      _busy = false;
    });
    if (problems.isNotEmpty) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not received',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.p.danger),
                ),
                const SizedBox(height: 8),
                for (final p in problems) Text(p, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmReceive() async {
    if (_items.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Receive ${_items.length} Thaan${_items.length == 1 ? '' : 's'}?'),
        content: const Text('Any piece back from a vendor is billed at their rate for that stage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Receive')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(handoverRepositoryProvider).receiveBatch([for (final t in _items) t.id]);
      if (!mounted) return;
      showOk(context, message);
      setState(() => _items.clear());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            "Scan whatever's coming back — it doesn't matter which stage or which vendor each piece is from.",
            style: TextStyle(fontSize: 13, color: context.p.textSecondary),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text('Nothing scanned yet.', style: TextStyle(color: context.p.textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = _items[i];
                    return ListTile(
                      dense: true,
                      title: Text(t.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                      subtitle: Text('${t.baleCode} · ${t.vendorName} — ${t.stage}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _items.removeAt(i)),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _items.isEmpty ? null : _confirmReceive,
                    icon: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.south_west),
                    label: Text('Receive${_items.isNotEmpty ? ' ${_items.length}' : ''}'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
