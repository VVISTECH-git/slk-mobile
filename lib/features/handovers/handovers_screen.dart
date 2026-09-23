import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../core/core_auth.dart' show coreOptionsProvider;
import '../core/pipeline_providers.dart';
import '../core/record_fields.dart' show narrow;
import '../core/records_list_screen.dart' show coreRecordsProvider;
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

/// The scans that didn't make it into the batch, one notice per reason —
/// see [summarizeProblems]. Shared by Send ("Not sent") and Receive ("Not
/// received").
void _showProblemsSheet(BuildContext context, {required String title, required List<ScanProblem> problems}) {
  final lines = summarizeProblems(problems);
  showAppSheet<void>(
    context,
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InlineNotice(line, warning: true, icon: Icons.error_outline),
          ),
      ],
    ),
  );
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
    // Each panel frames itself in an [AppPage] so its own Send / Receive
    // confirm can sit in the page's [BottomActionBar]; the Send / Receive
    // toggle is handed down to sit at the top of either body. Switching
    // swaps the whole panel (and so its scanned batch), as it always did.
    final toggle = _ModeToggle(sending: _sending, onChanged: (v) => setState(() => _sending = v));
    return _sending ? _SendPanel(toggle: toggle) : _ReceivePanel(toggle: toggle);
  }
}

/// Send | Receive. A segmented control, since the library has no
/// two-way switch of its own; sized so each half is a full 48 px target.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.sending, required this.onChanged});
  final bool sending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, 48)),
          segments: const [
            ButtonSegment(value: true, label: Text('Send'), icon: Icon(Icons.north_east)),
            ButtonSegment(value: false, label: Text('Receive'), icon: Icon(Icons.south_west)),
          ],
          selected: {sending},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
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
  const _SendPanel({required this.toggle});
  final Widget toggle;

  @override
  ConsumerState<_SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends ConsumerState<_SendPanel> {
  String? _stage;
  // Null means not chosen yet — see _vendorInHouse for why this can't
  // default to "in-house".
  String? _vendorId;
  // Null is the ordinary one-stage trip; otherwise the last stage of a
  // combined one (this vendor doing several stages in a single visit).
  String? _through;
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

  /// The stages this vendor could also cover after [_stage], or none: for
  /// in-house, an unchosen vendor, or a vendor who only does this one.
  List<String> _alsoOptions() {
    if (_vendorId == null || _vendorId == _vendorInHouse) return const [];
    final vendors = ref.read(coreVendorsProvider).value;
    final match = vendors?.where((v) => v.id == _vendorId);
    return alsoStages(match == null || match.isEmpty ? null : match.first.stages, _stage);
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
    if (outcome.problems.isNotEmpty) {
      _showProblemsSheet(context, title: 'Not sent', problems: outcome.problems);
    }
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

  Future<void> _confirmSend() async {
    if (_items.isEmpty || _stage == null || _vendorId == null) return;
    final stage = _stage!;

    final ok = await showConfirmDialog(
      context,
      title: 'Send ${_items.length} Thaan${_items.length == 1 ? '' : 's'} for ${tripLabel(stage, _through)}?',
      message: _vendorId == _vendorInHouse
          ? 'Going to in-house.'
          : 'Going to ${ref.read(coreVendorsProvider).value?.firstWhere((v) => v.id == _vendorId).name ?? 'that vendor'}.',
      confirmLabel: 'Send',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(handoverRepositoryProvider).sendBatch(
            stage: stage,
            vendorId: _vendorId == _vendorInHouse ? null : _vendorId,
            thaanIds: [for (final t in _items) t.id],
            throughStage: _through,
          );
      if (!mounted) return;
      showOk(context, message);
      setState(() {
        _items.clear();
        _through = null;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = ref.watch(coreVendorsProvider);
    final also = _alsoOptions();
    // A choice made for another vendor or stage doesn't carry over.
    if (_through != null && !also.contains(_through)) _through = null;

    return AppPage(
      title: 'Handovers',
      actions: const [ThemeButton()],
      padded: false,
      body: Column(
        children: [
          widget.toggle,
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
                    loading: () => const Skeleton(height: 52, radius: 12),
                    error: (e, _) => InlineNotice('$e', warning: true),
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
          if (also.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PickerField(
                label: 'Stages this trip',
                value: _through ?? _inHouse,
                options: [
                  PickerOption(_inHouse, '${_stage!} only'),
                  for (final s in also) PickerOption(s, tripLabel(_stage!, s)),
                ],
                onChanged: (v) => setState(() => _through = (v == null || v == _inHouse) ? null : v),
              ),
            ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionHeader(
                'Scanned',
                top: 0,
                trailing: AppButton.ghost(label: 'Clear', compact: true, onPressed: () => setState(_items.clear)),
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(title: 'Nothing scanned yet.', icon: Icons.qr_code_scanner)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      AppListGroup(
                        children: [
                          for (final (i, t) in _items.indexed)
                            AppListRow(
                              title: t.code,
                              titleMono: true,
                              subtitle: '${t.baleCode} · ${t.itemName}',
                              trailing: AppIconButton(
                                icon: Icons.close,
                                tooltip: 'Remove',
                                onPressed: () => setState(() => _items.removeAt(i)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomBar: BottomActionBar(
        secondary: AppButton.secondary(
          label: 'Scan',
          icon: Icons.qr_code_scanner,
          onPressed: _busy ? null : _scan,
        ),
        primary: AppButton.primary(
          label: 'Send${_items.isNotEmpty ? ' ${_items.length}' : ''}',
          icon: Icons.north_east,
          busy: _busy,
          onPressed: _items.isEmpty || _stage == null || _vendorId == null ? null : _confirmSend,
        ),
      ),
    );
  }
}

// ── Receive ──────────────────────────────────────────────────────────────

class _ReceivePanel extends ConsumerStatefulWidget {
  const _ReceivePanel({required this.toggle});
  final Widget toggle;

  @override
  ConsumerState<_ReceivePanel> createState() => _ReceivePanelState();
}

/// One group in a receive: the Thaans that share a colour and a motif. Either
/// a record that already exists on the server (a later delivery of a
/// colourway made at Print) or one to make right now, which the server
/// only learns of when the batch is confirmed.
class _RecordGroup {
  _RecordGroup.existing(CorePipelineRecord record)
      : colourwayId = record.id,
        code = record.code,
        colourId = null,
        colourLabel = record.colour,
        secondaryColourId = null,
        secondaryColourLabel = null,
        motifCategoryId = null,
        motifCategoryLabel = record.motifCategory,
        motifId = null,
        motifLabel = record.motif,
        existingCount = record.thaanCount;

  _RecordGroup.fresh({
    required String this.colourId,
    required this.colourLabel,
    required this.secondaryColourId,
    required this.secondaryColourLabel,
    required String this.motifCategoryId,
    required this.motifCategoryLabel,
    required String this.motifId,
    required this.motifLabel,
  })  : colourwayId = null,
        code = null,
        existingCount = 0;

  /// Null until the server makes it — i.e. for a record made in this session.
  final String? colourwayId;
  final String? code;
  final String? colourId;
  final String? colourLabel;
  final String? secondaryColourId;
  final String? secondaryColourLabel;
  final String? motifCategoryId;
  final String? motifCategoryLabel;
  final String? motifId;
  final String? motifLabel;

  /// Thaans already in an existing record, before this delivery.
  final int existingCount;

  bool get isNew => colourwayId == null;

  /// "Red · Peacock", or "Red / Gold · Peacock" with a secondary colour —
  /// how the group is named everywhere on the panel.
  String get label {
    final colour = [
      if (colourLabel != null && colourLabel!.isNotEmpty) colourLabel!,
      if (secondaryColourLabel != null && secondaryColourLabel!.isNotEmpty) secondaryColourLabel!,
    ].join(' / ');
    final motif = motifLabel ?? motifCategoryLabel;
    final parts = [
      if (colour.isNotEmpty) colour,
      if (motif != null && motif.isNotEmpty) motif,
    ];
    if (parts.isEmpty) return code ?? 'Record';
    return parts.join(' · ');
  }

  /// A short version for the row's trailing button, where there is no room
  /// for a sentence.
  String get shortLabel => code ?? label;
}

class _ReceivePanelState extends ConsumerState<_ReceivePanel> {
  final _items = <CoreThaanForReceive>[];
  bool _busy = false;

  /// The groups made or picked in this receive, and which group each
  /// eligible Thaan is sorted into (by Thaan id; absent means none).
  final _groups = <_RecordGroup>[];
  final _assignment = <String, int>{};

  /// The Thaans this receive is allowed to sort — back from Print or later.
  List<CoreThaanForReceive> get _eligible => [for (final t in _items) if (t.canRecord) t];

  /// Resolves each newly scanned code against `/handovers/lookup-receive`,
  /// skipping any already in the batch.
  Future<_ScanOutcome<CoreThaanForReceive>> _resolve(List<String> codes) async {
    final repo = ref.read(handoverRepositoryProvider);
    final resolved = <CoreThaanForReceive>[];
    final problems = <ScanProblem>[];

    for (final code in codes) {
      if (_items.any((t) => t.code == code) || resolved.any((t) => t.code == code)) continue;
      try {
        resolved.add(await repo.lookupForReceive(code));
      } catch (e) {
        problems.add(ScanProblem(code, e));
      }
    }
    return _ScanOutcome(resolved: resolved, problems: problems);
  }

  Future<void> _scan() async {
    final codes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ContinuousScanScreen(
          title: "Scan what's coming back",
          already: {for (final t in _items) t.code},
        ),
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
    if (outcome.problems.isNotEmpty) {
      _showProblemsSheet(context, title: 'Not received', problems: outcome.problems);
    }
  }

  void _clear() => setState(() {
        _items.clear();
        _groups.clear();
        _assignment.clear();
      });

  void _removeItem(int i) => setState(() {
        _assignment.remove(_items[i].id);
        _items.removeAt(i);
      });

  /// Drops a group; whatever was sorted into it becomes unsorted again, and
  /// the groups after it shift down one.
  void _removeGroup(int index) => setState(() {
        _groups.removeAt(index);
        for (final id in _assignment.keys.toList()) {
          final g = _assignment[id]!;
          if (g == index) {
            _assignment.remove(id);
          } else if (g > index) {
            _assignment[id] = g - 1;
          }
        }
      });

  /// "New group": the sheet hands back a group (made here, or one of the
  /// records already in the pipeline). With a [forThaan], that Thaan is
  /// sorted into it straight away.
  Future<int?> _newGroup({CoreThaanForReceive? forThaan}) async {
    final group = await showAppSheet<_RecordGroup>(
      context,
      title: 'New group',
      subtitle: 'The Thaans that share one colour and one motif become one record.',
      child: _GroupSheet(
        excludeIds: {for (final g in _groups) if (g.colourwayId != null) g.colourwayId!},
      ),
    );
    if (group == null || !mounted) return null;
    setState(() {
      _groups.add(group);
      if (forThaan != null) _assignment[forThaan.id] = _groups.length - 1;
    });
    return _groups.length - 1;
  }

  /// Which group [t] goes in — one of those made so far, none, or a new
  /// one made right here.
  Future<void> _pickGroupFor(CoreThaanForReceive t) async {
    final current = _assignment[t.id];
    final picked = await showAppSheet<int>(
      context,
      title: 'Sort ${t.code}',
      subtitle: t.recordLabel == null ? 'Not in a record yet.' : 'Now in ${t.recordLabel}.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_groups.isEmpty)
            const InlineNotice('No groups yet — make one for this Thaan.')
          else
            AppListGroup(
              children: [
                for (final (i, g) in _groups.indexed)
                  AppListRow(
                    title: g.label,
                    subtitle: _groupSubtitle(g),
                    selected: i == current,
                    trailing: i == current ? Icon(Icons.check, color: context.p.primary) : null,
                    onTap: () => Navigator.pop(context, i),
                  ),
                AppListRow(
                  title: 'None',
                  subtitle: 'Receive it without sorting',
                  selected: current == null,
                  trailing: current == null ? Icon(Icons.check, color: context.p.primary) : null,
                  onTap: () => Navigator.pop(context, -1),
                ),
              ],
            ),
          const SizedBox(height: 12),
          AppButton.secondary(
            label: 'New group',
            icon: Icons.add,
            onPressed: () => Navigator.pop(context, -2),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == -2) {
      await _newGroup(forThaan: t);
      return;
    }
    setState(() {
      if (picked < 0) {
        _assignment.remove(t.id);
      } else {
        _assignment[t.id] = picked;
      }
    });
  }

  int _countIn(int index) => _assignment.values.where((g) => g == index).length;

  String _groupSubtitle(_RecordGroup g) {
    final n = _countIn(_groups.indexOf(g));
    return [
      '$n Thaan${n == 1 ? '' : 's'} here',
      g.isNew ? 'new record' : '${g.code} · ${g.existingCount} already',
    ].join(' · ');
  }

  Future<void> _confirmReceive() async {
    if (_items.isEmpty) return;

    final specs = <ReceiveRecordSpec>[];
    final lines = <String>[];
    for (final (i, g) in _groups.indexed) {
      final ids = [
        for (final t in _eligible)
          if (_assignment[t.id] == i) t.id,
      ];
      if (ids.isEmpty) continue;
      specs.add(ReceiveRecordSpec(
        colourwayId: g.colourwayId,
        newRecord: g.isNew
            ? (
                colourId: g.colourId!,
                secondaryColourId: g.secondaryColourId,
                motifCategoryId: g.motifCategoryId!,
                motifId: g.motifId!,
              )
            : null,
        thaanIds: ids,
      ));
      lines.add('${g.label} — ${ids.length} Thaan${ids.length == 1 ? '' : 's'}${g.isNew ? ' (new record)' : ''}');
    }
    final plain = _items.where((t) => _assignment[t.id] == null && t.colourwayId == null).length;
    if (plain > 0 && specs.isNotEmpty) lines.add('$plain received without a record');

    // Named when the whole batch is coming back from one stage — the usual
    // case, and the fact that actually matters to whoever is confirming
    // this. A mixed batch falls back to just the count, since no single
    // stage name would be true of all of them.
    final stages = _items.map((t) => tripLabel(t.stage, t.throughStage)).toSet();
    final title = stages.length == 1
        ? 'Receiving ${_items.length} Thaan${_items.length == 1 ? '' : 's'} after ${stages.first}?'
        : 'Receive ${_items.length} Thaan${_items.length == 1 ? '' : 's'}?';

    final ok = await showConfirmDialog(
      context,
      title: title,
      message: specs.isEmpty
          ? 'Confirm all of these are physically back in hand.'
          : '${lines.map((l) => '• $l').join('\n')}\n\nAll of it goes in as one delivery, one bill.',
      confirmLabel: 'Receive',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(handoverRepositoryProvider).receiveBatch(
            [for (final t in _items) t.id],
            records: specs,
          );
      if (!mounted) return;
      showOk(context, message);
      _clear();
      if (specs.isNotEmpty) {
        ref.invalidate(pipelineRecordsProvider);
        ref.invalidate(coreRecordsProvider);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSort = _eligible.isNotEmpty;

    return AppPage(
      title: 'Handovers',
      actions: const [ThemeButton()],
      padded: false,
      body: Column(
        children: [
          widget.toggle,
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: InlineNotice(
              "Scan whatever's coming back — it doesn't matter which stage or which vendor each piece is from.",
            ),
          ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionHeader(
                'Scanned',
                top: 0,
                trailing: AppButton.ghost(label: 'Clear', compact: true, onPressed: _busy ? null : _clear),
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(title: 'Nothing scanned yet.', icon: Icons.qr_code_scanner)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      AppListGroup(
                        children: [
                          for (final (i, t) in _items.indexed) _thaanRow(i, t),
                        ],
                      ),
                      if (canSort) ...[
                        const SizedBox(height: 12),
                        _SortCard(
                          groups: _groups,
                          countIn: _countIn,
                          // One already in a record stays there unless moved — that's sorted.
                          unsorted: _eligible.where((t) => _assignment[t.id] == null && t.colourwayId == null).length,
                          onNewGroup: _busy ? null : () => _newGroup(),
                          onRemoveGroup: _busy ? null : _removeGroup,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      bottomBar: BottomActionBar(
        secondary: AppButton.secondary(
          label: 'Scan',
          icon: Icons.qr_code_scanner,
          onPressed: _busy ? null : _scan,
        ),
        primary: AppButton.primary(
          label: 'Receive${_items.isNotEmpty ? ' ${_items.length}' : ''}',
          icon: Icons.south_west,
          busy: _busy,
          onPressed: _items.isEmpty ? null : _confirmReceive,
        ),
      ),
    );
  }

  /// One scanned Thaan. Back from Print or later, it carries a group
  /// picker; earlier than that it is received as it is, and says so only
  /// when there is sorting going on around it.
  Widget _thaanRow(int i, CoreThaanForReceive t) {
    final group = _assignment[t.id];
    final g = group == null ? null : _groups[group];
    final subtitle = [
      '${t.baleCode} · ${t.vendorName} — ${tripLabel(t.stage, t.throughStage)}',
      // Where it's moving from, when it already sits in a different record.
      if (t.canRecord && t.colourwayId != null && g != null && g.colourwayId != t.colourwayId)
        'moving from ${t.recordLabel}',
    ].join(' · ');

    return AppListRow(
      title: t.code,
      titleMono: true,
      subtitle: subtitle,
      onTap: t.canRecord && !_busy ? () => _pickGroupFor(t) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t.canRecord)
            AppButton.ghost(
              label: g?.shortLabel ?? (t.colourwayId == null ? 'Sort…' : (t.recordCode ?? 'In a record')),
              icon: Icons.expand_more,
              compact: true,
              onPressed: _busy ? null : () => _pickGroupFor(t),
            ),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Remove',
            onPressed: _busy ? null : () => _removeItem(i),
          ),
        ],
      ),
    );
  }
}

/// "Sort into records" — the groups made in this receive, how many Thaans
/// each has so far, and the way to make another.
class _SortCard extends StatelessWidget {
  const _SortCard({
    required this.groups,
    required this.countIn,
    required this.unsorted,
    required this.onNewGroup,
    required this.onRemoveGroup,
  });

  final List<_RecordGroup> groups;
  final int Function(int index) countIn;
  final int unsorted;
  final VoidCallback? onNewGroup;
  final ValueChanged<int>? onRemoveGroup;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      emphasis: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(
            'Sort into records',
            subtitle: unsorted == 0
                ? 'Every Thaan back from Print has a group.'
                : '$unsorted back from Print still unsorted — tap a Thaan to sort it.',
          ),
          const SizedBox(height: 10),
          if (groups.isEmpty)
            const InlineNotice(
              'Pick a colour and a motif for the first design in this delivery, then tap each Thaan of it.',
              icon: Icons.palette_outlined,
            )
          else
            AppListGroup(
              children: [
                for (final (i, g) in groups.indexed)
                  AppListRow(
                    dense: true,
                    title: g.label,
                    subtitle: [
                      '${countIn(i)} Thaan${countIn(i) == 1 ? '' : 's'}',
                      g.isNew ? 'new record' : '${g.code} · ${g.existingCount} already',
                    ].join(' · '),
                    trailing: AppIconButton(
                      icon: Icons.close,
                      tooltip: 'Remove group',
                      onPressed: onRemoveGroup == null ? null : () => onRemoveGroup!(i),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          AppButton.secondary(label: 'New group', icon: Icons.add, onPressed: onNewGroup),
        ],
      ),
    );
  }
}

/// New group: a colour, an optional secondary colour, a motif category and
/// a motif from the Master Lists — or one of the records already in the
/// pipeline, for a delivery that's going into colourways made at Print.
/// Pops with the [_RecordGroup]. Rendered inside [showAppSheet].
class _GroupSheet extends ConsumerStatefulWidget {
  const _GroupSheet({required this.excludeIds});

  /// Records already grouped in this session — offered once, not twice.
  final Set<String> excludeIds;

  @override
  ConsumerState<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends ConsumerState<_GroupSheet> {
  String? _colourId;
  String? _secondaryColourId;
  String? _motifCategoryId;
  String? _motifId;

  bool get _canAdd => _colourId != null && _motifCategoryId != null && _motifId != null;

  static String? _labelOf(List<CoreOption>? values, String? id) {
    if (id == null) return null;
    for (final v in values ?? const <CoreOption>[]) {
      if (v.id == id) return v.label;
    }
    return null;
  }

  static List<PickerOption> _pickOptions(List<CoreOption> values) => [
        for (final v in values) PickerOption(v.id, v.label, color: v.swatch),
      ];

  void _add(CoreOptions o) {
    Navigator.pop(
      context,
      _RecordGroup.fresh(
        colourId: _colourId!,
        colourLabel: _labelOf(o['colour'], _colourId),
        secondaryColourId: _secondaryColourId,
        secondaryColourLabel: _labelOf(o['colour'], _secondaryColourId),
        motifCategoryId: _motifCategoryId!,
        motifCategoryLabel: _labelOf(o['motif_category'], _motifCategoryId),
        motifId: _motifId!,
        motifLabel: _labelOf(o['motif'], _motifId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(coreOptionsProvider);
    final records = ref.watch(pipelineRecordsProvider('in_pipeline'));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        options.when(
          loading: () => const LoadingState(rows: 4),
          error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
          data: (o) {
            final colours = _pickOptions(o['colour'] ?? const []);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PickerField(
                  label: 'Colour',
                  required: true,
                  value: _colourId,
                  hint: 'Choose…',
                  options: colours,
                  onChanged: (v) => setState(() => _colourId = v),
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Secondary colour',
                  value: _secondaryColourId,
                  hint: 'None',
                  allowClear: true,
                  options: colours,
                  onChanged: (v) => setState(() => _secondaryColourId = v),
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Motif category',
                  required: true,
                  value: _motifCategoryId,
                  hint: 'Choose…',
                  options: _pickOptions(o['motif_category'] ?? const []),
                  onChanged: (v) => setState(() {
                    // A re-confirm is not a change; a change clears the motif.
                    if (_motifCategoryId == v) return;
                    _motifCategoryId = v;
                    _motifId = null;
                  }),
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Motif',
                  required: true,
                  value: _motifId,
                  hint: _motifCategoryId == null ? 'Pick a category first' : 'Choose…',
                  options: _pickOptions(narrow(o['motif'], _motifCategoryId)),
                  onChanged: (v) => setState(() => _motifId = v),
                ),
                const SizedBox(height: 16),
                AppButton.primary(
                  label: 'Add group',
                  icon: Icons.add,
                  onPressed: _canAdd ? () => _add(o) : null,
                ),
              ],
            );
          },
        ),
        const SectionHeader('Or an existing record', top: 20),
        records.when(
          loading: () => const LoadingState(rows: 3),
          error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
          data: (rows) {
            final offered = [for (final r in rows) if (!widget.excludeIds.contains(r.id)) r];
            if (offered.isEmpty) {
              return const InlineNotice('Nothing in the pipeline right now — every delivery starts with a new group.');
            }
            return AppListGroup(
              children: [
                for (final r in offered)
                  AppListRow(
                    leading: RowThumb(color: r.swatch, icon: r.swatch == null ? Icons.palette_outlined : null),
                    title: r.name,
                    subtitle: r.summary,
                    chevron: true,
                    onTap: () => Navigator.pop(context, _RecordGroup.existing(r)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
