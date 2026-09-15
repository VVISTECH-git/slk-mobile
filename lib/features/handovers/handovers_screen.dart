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

/// Distinct from [_inHouse] — that sentinel already means "Auto" on the
/// Stage picker, and reusing it for the Vendor picker's "In-house" would
/// make an unselected [_SendPanelState._vendorId] (`null`) indistinguishable
/// from "in-house, chosen on purpose". Sending in-house has to be picked,
/// the same as sending to a vendor — never fallen into by not touching the
/// picker at all.
const _vendorInHouse = 'in-house';

/// One scan failure, kept structured (code + error) rather than formatted
/// into a string right away — so failures that share a reason across many
/// codes ("all 20 already out for Salava") can collapse into one line
/// instead of twenty near-identical ones, in [summarizeProblems] below.
class ScanProblem {
  ScanProblem(this.code, Object error) : message = '$error';
  final String code;
  final String message;

  bool get _mentionsCode => message.contains(code);

  /// This problem alone. Every message from `checkThaanForSend` /
  /// `checkThaanForReceive` already names the Thaan it's about —
  /// "T00002041 is already out for Label Stitching." — so prefixing the
  /// code again would just say it twice. Only genuinely code-blind
  /// failures (a dropped connection, mid-scan) need the code added back
  /// in, or there'd be no way to tell which scan they belonged to.
  String get solo => _mentionsCode ? message : '$code — $message';

  /// The message with this problem's own code removed — what several
  /// problems that share a reason, but not a code, have in common.
  String get _reason => _mentionsCode ? message.replaceAll(code, '').trim() : message;
}

/// "is out for Salava" → "are out for Salava" — the one grammatical fix
/// needed to talk about several Thaans instead of one, for the handful of
/// verb shapes the actual messages use.
String _pluralizeReason(String reason) {
  if (reason == 'No Thaan with code "".') return "aren't on file.";
  if (reason.startsWith('is ')) return 'are ${reason.substring(3)}';
  if (reason.startsWith("isn't ")) return "aren't ${reason.substring(6)}";
  if (reason.startsWith('has ')) return 'have ${reason.substring(4)}';
  return reason;
}

/// Groups by identical reason first — reading twenty repeats of the same
/// sentence to learn one fact ("this whole batch is already out") is worse
/// than reading it once.
List<String> summarizeProblems(List<ScanProblem> problems) {
  final groups = <String, List<ScanProblem>>{};
  for (final p in problems) {
    groups.putIfAbsent(p._reason, () => []).add(p);
  }
  return [
    for (final group in groups.values)
      if (group.length == 1)
        group.first.solo
      else
        '${group.length} Thaans ${_pluralizeReason(group.first._reason)}'.trim(),
  ];
}

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
  final List<ScanProblem> problems;
}

// ── Send ─────────────────────────────────────────────────────────────────

class _SendPanel extends ConsumerStatefulWidget {
  const _SendPanel();

  @override
  ConsumerState<_SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends ConsumerState<_SendPanel> {
  String? _stage;
  // Null means not chosen yet — see _vendorInHouse for why this can't
  // default to "in-house".
  String? _vendorId;
  final _items = <CoreThaanForSend>[];
  bool _busy = false;

  /// A vendor picked before the stage was known (or before it changed) might
  /// not do the stage that just got locked in — every Thaan goes through
  /// every stage in order, so a vendor who doesn't do this one was never a
  /// real option for this batch. Falls back to unselected, not in-house: a
  /// vendor becoming invalid is a reason to make the reader choose again.
  void _dropIneligibleVendor() {
    if (_vendorId == null || _vendorId == _vendorInHouse || _stage == null) return;
    final vendors = ref.read(coreVendorsProvider).value;
    if (vendors == null) return;
    final stillEligible = vendors.any((v) => v.id == _vendorId && v.stages.contains(_stage));
    if (!stillEligible) _vendorId = null;
  }

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
      _dropIneligibleVendor();
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
    final problems = <ScanProblem>[];

    for (final code in codes) {
      if (_items.any((t) => t.code == code) || resolved.any((t) => t.code == code)) continue;
      try {
        final result = await repo.lookupForSend(code: code, stage: stage);
        stage ??= result.stage;
        resolved.add(result.thaan);
      } catch (e) {
        problems.add(ScanProblem(code, e));
      }
    }

    if (stage != null) _stage = stage;
    return _ScanOutcome(resolved: resolved, problems: problems);
  }

  void _showProblems(List<ScanProblem> problems) {
    final lines = summarizeProblems(problems);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Not sent',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.p.danger),
              ),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSend() async {
    if (_items.isEmpty || _stage == null || _vendorId == null) return;
    final stage = _stage!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Send ${_items.length} Thaan${_items.length == 1 ? '' : 's'} for $stage?'),
        content: Text(
          _vendorId == _vendorInHouse
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
            vendorId: _vendorId == _vendorInHouse ? null : _vendorId,
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
                  hint: 'Auto',
                  allowClear: true,
                  options: [
                    PickerOption(_inHouse, 'Auto'),
                    ...plainOptions(kSendableStages),
                  ],
                  onChanged: (v) => setState(() {
                    _stage = (v == null || v == _inHouse) ? null : v;
                    _dropIneligibleVendor();
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
                    hint: 'Choose…',
                    // Once a stage is known, only vendors who actually do it are
                    // worth offering — see _dropIneligibleVendor.
                    options: [
                      const PickerOption(_vendorInHouse, 'In-house'),
                      for (final v in rows)
                        if (_stage == null || v.stages.contains(_stage)) PickerOption(v.id, v.name),
                    ],
                    onChanged: (v) => setState(() {
                      _vendorId = v;
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(_items.clear),
                child: const Text('Clear'),
              ),
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
                    onPressed: _busy || _items.isEmpty || _stage == null || _vendorId == null ? null : _confirmSend,
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
    final problems = <ScanProblem>[];

    for (final code in codes) {
      if (_items.any((t) => t.code == code)) continue;
      try {
        resolved.add(await repo.lookupForReceive(code));
      } catch (e) {
        problems.add(ScanProblem(code, e));
      }
    }

    if (!mounted) return;
    setState(() {
      _items.addAll(resolved);
      _busy = false;
    });
    if (problems.isNotEmpty) {
      final lines = summarizeProblems(problems);
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => SafeArea(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  'Not received',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.p.danger),
                ),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmReceive() async {
    if (_items.isEmpty) return;

    // Named when the whole batch is coming back from one stage — the usual
    // case, and the fact that actually matters to whoever is confirming
    // this. A mixed batch (allowed — see the panel's own copy above) falls
    // back to just the count, since no single stage name would be true of
    // all of them.
    final stages = _items.map((t) => t.stage).toSet();
    final title = stages.length == 1
        ? 'Receiving ${_items.length} Thaan${_items.length == 1 ? '' : 's'} after ${stages.first}?'
        : 'Receive ${_items.length} Thaan${_items.length == 1 ? '' : 's'}?';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text('Confirm all of these are physically back in hand.'),
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
