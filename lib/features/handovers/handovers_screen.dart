import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../piles/pile_providers.dart';
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

/// A pile being filled in this receive — one that already exists on the
/// server (made at Print, now getting its Nellateeta delivery) or one made
/// at the door just now, which the server only learns of when the batch is
/// confirmed. Holds the Thaans scanned into it so far.
class _SessionPile {
  _SessionPile.existing(CorePile pile)
      : pileId = pile.id,
        code = pile.code,
        name = pile.name,
        colourId = pile.mainColourId,
        colourLabel = pile.mainColour,
        photoKey = null,
        photoFile = null,
        photoUrl = pile.photoUrl;

  _SessionPile.fresh({
    required this.name,
    required this.colourId,
    required this.colourLabel,
    required this.photoKey,
    required this.photoFile,
  })  : pileId = null,
        code = null,
        photoUrl = null;

  /// Null until the server makes it — i.e. for a pile made in this session.
  final String? pileId;
  final String? code;
  final String name;
  final String? colourId;
  final String? colourLabel;

  /// The uploaded photo's key, for a new pile; an existing pile already has
  /// its photo on the server.
  final String? photoKey;
  final File? photoFile;
  final String? photoUrl;

  final thaans = <CoreThaanForReceive>[];

  bool get isNew => pileId == null;

  /// The Thaans that will actually go in this pile — the rest are received
  /// without one, because they're not back from Print yet.
  List<CoreThaanForReceive> get pileable => [for (final t in thaans) if (t.canPile) t];

  String get label => colourLabel == null || colourLabel!.isEmpty ? name : '$name · $colourLabel';

  ImageProvider? get image {
    if (photoFile != null) return FileImage(photoFile!);
    if (photoUrl != null) return NetworkImage(photoUrl!);
    return null;
  }
}

class _ReceivePanelState extends ConsumerState<_ReceivePanel> {
  final _items = <CoreThaanForReceive>[];
  bool _busy = false;

  /// Receive as: just Thaans (the batch in [_items]) or in piles (the
  /// batches in [_piles]). Switching clears whichever was in progress — a
  /// batch scanned without piles can't be sorted into them after the fact,
  /// since which pile each Thaan belongs in is only known at the door with
  /// the cloth in hand.
  bool _inPiles = false;
  final _piles = <_SessionPile>[];
  int _active = -1;

  List<CoreThaanForReceive> get _pileItems => [for (final p in _piles) ...p.thaans];

  /// Resolves each newly scanned code against `/handovers/lookup-receive`,
  /// skipping any already in [already]. Shared by both modes so a Thaan
  /// answers the same way whichever way it's being received.
  Future<_ScanOutcome<CoreThaanForReceive>> _resolve(List<String> codes, Iterable<CoreThaanForReceive> already) async {
    final repo = ref.read(handoverRepositoryProvider);
    final resolved = <CoreThaanForReceive>[];
    final problems = <ScanProblem>[];

    for (final code in codes) {
      if (already.any((t) => t.code == code) || resolved.any((t) => t.code == code)) continue;
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
        builder: (_) => const ContinuousScanScreen(title: "Scan what's coming back"),
      ),
    );
    if (codes == null || codes.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final outcome = await _resolve(codes, _items);

    if (!mounted) return;
    setState(() {
      _items.addAll(outcome.resolved);
      _busy = false;
    });
    if (outcome.problems.isNotEmpty) {
      _showProblemsSheet(context, title: 'Not received', problems: outcome.problems);
    }
  }

  Future<void> _confirmReceive() async {
    if (_items.isEmpty) return;

    // Named when the whole batch is coming back from one stage — the usual
    // case, and the fact that actually matters to whoever is confirming
    // this. A mixed batch (allowed — see the panel's own copy above) falls
    // back to just the count, since no single stage name would be true of
    // all of them.
    final stages = _items.map((t) => tripLabel(t.stage, t.throughStage)).toSet();
    final title = stages.length == 1
        ? 'Receiving ${_items.length} Thaan${_items.length == 1 ? '' : 's'} after ${stages.first}?'
        : 'Receive ${_items.length} Thaan${_items.length == 1 ? '' : 's'}?';

    final ok = await showConfirmDialog(
      context,
      title: title,
      message: 'Confirm all of these are physically back in hand.',
      confirmLabel: 'Receive',
    );
    if (!ok || !mounted) return;

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

  // ── In piles ──

  void _switchMode(bool inPiles) {
    if (inPiles == _inPiles) return;
    setState(() {
      _inPiles = inPiles;
      _items.clear();
      _piles.clear();
      _active = -1;
    });
  }

  /// "New pile" / "Next pile": the sheet hands back a pile (made here or
  /// picked from the drafts), which becomes the active one and opens the
  /// scanner straight away — the reader has the cloth in hand.
  Future<void> _newPile() async {
    final pile = await showAppSheet<_SessionPile>(
      context,
      title: _piles.isEmpty ? 'New pile' : 'Next pile',
      subtitle: 'One design, one colour combination — photograph one Thaan of it.',
      child: _PileSheet(
        excludePileIds: {for (final p in _piles) if (p.pileId != null) p.pileId!},
      ),
    );
    if (pile == null || !mounted) return;
    setState(() {
      _piles.add(pile);
      _active = _piles.length - 1;
    });
    await _scanIntoActive();
  }

  Future<void> _scanIntoActive() async {
    if (_active < 0 || _active >= _piles.length) return;
    final pile = _piles[_active];
    final codes = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ContinuousScanScreen(
          title: 'Scan into ${pile.name}',
          already: {for (final t in _pileItems) t.code},
        ),
      ),
    );
    if (codes == null || codes.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final outcome = await _resolve(codes, _pileItems);

    if (!mounted) return;
    setState(() {
      pile.thaans.addAll(outcome.resolved);
      _busy = false;
    });
    if (outcome.problems.isNotEmpty) {
      _showProblemsSheet(context, title: 'Not received', problems: outcome.problems);
    }
  }

  Future<void> _confirmReceivePiles() async {
    final all = _pileItems;
    if (all.isEmpty) return;

    final specs = <ReceivePileSpec>[];
    final lines = <String>[];
    for (final p in _piles) {
      final ids = [for (final t in p.pileable) t.id];
      if (ids.isEmpty) continue;
      specs.add(ReceivePileSpec(
        pileId: p.pileId,
        newPile: p.isNew ? (name: p.name, mainColourId: p.colourId ?? '', photoKey: p.photoKey ?? '') : null,
        thaanIds: ids,
      ));
      lines.add('${p.label} — ${ids.length} Thaan${ids.length == 1 ? '' : 's'}${p.isNew ? ' (new)' : ''}');
    }
    final loose = all.length - specs.fold<int>(0, (n, s) => n + s.thaanIds.length);
    if (loose > 0) lines.add('$loose without a pile — not back from Print yet');

    final ok = await showConfirmDialog(
      context,
      title: 'Receive ${all.length} Thaan${all.length == 1 ? '' : 's'} in ${specs.length} pile${specs.length == 1 ? '' : 's'}?',
      message: '${lines.map((l) => '• $l').join('\n')}\n\nAll piles go in as one delivery, one bill.',
      confirmLabel: 'Receive',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await ref.read(handoverRepositoryProvider).receiveBatch(
            [for (final t in all) t.id],
            piles: specs,
          );
      if (!mounted) return;
      showOk(context, message);
      setState(() {
        _piles.clear();
        _active = -1;
      });
      // The piles are in; their details (motif, craft, colours) are not.
      // Offer to go and fill them in now, while the Thaans are in hand —
      // or not: "Later" leaves them on the Piles list under "To complete".
      if (specs.isNotEmpty) {
        ref.invalidate(pilesProvider);
        final now = await showConfirmDialog(
          context,
          title: 'Fill in the details now?',
          message: 'Motif, craft, colours — one pile at a time.',
          confirmLabel: 'Yes',
          cancelLabel: 'Later',
        );
        if (now && mounted) context.push('/core/piles');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiveAs = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _ReceiveAsToggle(inPiles: _inPiles, onChanged: _busy ? null : _switchMode),
    );
    return _inPiles ? _buildPiles(receiveAs) : _buildJustThaans(receiveAs);
  }

  Widget _buildJustThaans(Widget receiveAs) {
    return AppPage(
      title: 'Handovers',
      actions: const [ThemeButton()],
      padded: false,
      body: Column(
        children: [
          widget.toggle,
          receiveAs,
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
                              subtitle: '${t.baleCode} · ${t.vendorName} — ${tripLabel(t.stage, t.throughStage)}',
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
          label: 'Receive${_items.isNotEmpty ? ' ${_items.length}' : ''}',
          icon: Icons.south_west,
          busy: _busy,
          onPressed: _items.isEmpty ? null : _confirmReceive,
        ),
      ),
    );
  }

  Widget _buildPiles(Widget receiveAs) {
    final active = _active >= 0 && _active < _piles.length ? _piles[_active] : null;
    final total = _pileItems.length;

    return AppPage(
      title: 'Handovers',
      actions: const [ThemeButton()],
      padded: false,
      body: Column(
        children: [
          widget.toggle,
          receiveAs,
          Expanded(
            child: _piles.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const InlineNotice(
                        'Make a pile for the first design in this delivery, then scan its Thaans into it. '
                        'Anything not back from Print yet is received without a pile.',
                      ),
                      const EmptyState(
                        title: 'No pile yet.',
                        message: 'Photograph one Thaan, name the pile, pick its main colour.',
                        icon: Icons.layers_outlined,
                      ),
                      AppButton.primary(
                        label: 'New pile',
                        icon: Icons.add,
                        onPressed: _busy ? null : _newPile,
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      if (active != null) ...[
                        _ActivePileCard(pile: active),
                        SectionHeader(
                          'In this pile',
                          trailing: Text('${active.thaans.length}'),
                        ),
                        if (active.thaans.isEmpty)
                          const EmptyState(compact: true, title: 'Nothing scanned into it yet.', icon: Icons.qr_code_scanner)
                        else
                          AppListGroup(
                            children: [
                              for (final (i, t) in active.thaans.indexed)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    AppListRow(
                                      title: t.code,
                                      titleMono: true,
                                      subtitle: _pileRowSubtitle(t, active),
                                      trailing: AppIconButton(
                                        icon: Icons.close,
                                        tooltip: 'Remove',
                                        onPressed: () => setState(() => active.thaans.removeAt(i)),
                                      ),
                                    ),
                                    if (!t.canPile)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                        child: InlineNotice(
                                          '${t.code} is not back from Print — it will be received without a pile.',
                                          warning: true,
                                          icon: Icons.error_outline,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                      SectionHeader(
                        'Piles',
                        trailing: AppButton.ghost(
                          label: 'Clear',
                          compact: true,
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _piles.clear();
                                    _active = -1;
                                  }),
                        ),
                      ),
                      AppListGroup(
                        children: [
                          for (final (i, p) in _piles.indexed)
                            AppListRow(
                              leading: RowThumb(image: p.image, icon: p.image == null ? Icons.layers_outlined : null),
                              title: p.name,
                              subtitle: [
                                if (p.colourLabel != null && p.colourLabel!.isNotEmpty) p.colourLabel!,
                                p.isNew ? 'new' : (p.code ?? 'existing'),
                              ].join(' · '),
                              selected: i == _active,
                              trailing: Text(
                                '${p.thaans.length}',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.p.text),
                              ),
                              onTap: () => setState(() => _active = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppButton.secondary(
                        label: 'Next pile',
                        icon: Icons.add,
                        onPressed: _busy ? null : _newPile,
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomBar: BottomActionBar(
        secondary: AppButton.secondary(
          label: active == null ? 'Scan' : 'Scan into pile',
          icon: Icons.qr_code_scanner,
          onPressed: _busy || active == null ? null : _scanIntoActive,
        ),
        primary: AppButton.primary(
          label: 'Receive${total > 0 ? ' $total' : ''}',
          icon: Icons.south_west,
          busy: _busy,
          onPressed: total == 0 ? null : _confirmReceivePiles,
        ),
      ),
    );
  }

  /// The row's second line: bale, vendor and trip as in Just Thaans, plus
  /// where it's moving from when it already sits in a different pile.
  static String _pileRowSubtitle(CoreThaanForReceive t, _SessionPile pile) {
    final base = '${t.baleCode} · ${t.vendorName} — ${tripLabel(t.stage, t.throughStage)}';
    if (t.pileId != null && t.pileId != pile.pileId && t.canPile) {
      return '$base · moving from ${t.pileName ?? t.pileCode ?? 'another pile'}';
    }
    return base;
  }
}

/// Just Thaans | In piles — the Receive panel's own two-way switch, the
/// same shape as Send | Receive above it.
class _ReceiveAsToggle extends StatelessWidget {
  const _ReceiveAsToggle({required this.inPiles, required this.onChanged});
  final bool inPiles;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Receive as'),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(minimumSize: const Size(0, 48)),
            segments: const [
              ButtonSegment(value: false, label: Text('Just Thaans'), icon: Icon(Icons.view_list_outlined)),
              ButtonSegment(value: true, label: Text('In piles'), icon: Icon(Icons.layers_outlined)),
            ],
            selected: {inPiles},
            onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
          ),
        ),
      ],
    );
  }
}

/// The pile being scanned into, pinned at the top: its photo, name and
/// colour, and the count going up as the reader scans.
class _ActivePileCard extends StatelessWidget {
  const _ActivePileCard({required this.pile});
  final _SessionPile pile;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final n = pile.thaans.length;
    return AppCard(
      emphasis: true,
      child: Row(
        children: [
          RowThumb(size: 64, image: pile.image, icon: pile.image == null ? Icons.layers_outlined : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pile.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (pile.colourLabel != null && pile.colourLabel!.isNotEmpty) pile.colourLabel!,
                    pile.isNew ? 'New pile' : 'Pile ${pile.code ?? ''}'.trim(),
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatTile(value: '$n', label: n == 1 ? 'Thaan' : 'Thaans', tone: BadgeTone.brand),
        ],
      ),
    );
  }
}

/// New pile: a photo of one Thaan (uploaded the moment it's taken, so the
/// key is ready when the batch is confirmed), a name and the main colour —
/// or one of the draft piles already on the server, for a delivery that's
/// going into piles made at Print. Pops with the [_SessionPile] to scan
/// into. Rendered inside [showAppSheet].
class _PileSheet extends ConsumerStatefulWidget {
  const _PileSheet({required this.excludePileIds});

  /// Draft piles already in this session — offered once, not twice.
  final Set<String> excludePileIds;

  @override
  ConsumerState<_PileSheet> createState() => _PileSheetState();
}

class _PileSheetState extends ConsumerState<_PileSheet> {
  final _name = TextEditingController();
  String? _colourId;
  File? _photo;
  String? _photoKey;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (shot == null || !mounted) return;
    final file = File(shot.path);
    setState(() {
      _photo = file;
      _photoKey = null;
      _uploading = true;
    });
    try {
      final key = await ref.read(pileRepositoryProvider).uploadPhoto(file);
      if (!mounted) return;
      setState(() => _photoKey = key);
    } catch (e) {
      if (!mounted) return;
      setState(() => _photo = null);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // A photo is what makes a pile easy to recognise later, but a camera that
  // will not open must not stop a delivery being received: name and colour
  // are enough to start, and the photo can be added on the web.
  bool get _canStart => _name.text.trim().isNotEmpty && _colourId != null && !_uploading;

  void _start(List<CoreColour> colours) {
    final label = colours.where((c) => c.id == _colourId).map((c) => c.label).firstOrNull;
    Navigator.pop(
      context,
      _SessionPile.fresh(
        name: _name.text.trim(),
        colourId: _colourId,
        colourLabel: label,
        photoKey: _photoKey,
        photoFile: _photo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final colours = ref.watch(pileColoursProvider);
    final drafts = ref.watch(pilesProvider('draft'));

    final photoLine = _uploading
        ? 'Uploading…'
        : _photoKey != null
            ? 'Photo taken — tap to retake'
            : 'Tap to photograph one Thaan of this design';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Photo', required: true),
        const SizedBox(height: 6),
        AppCard(
          onTap: _uploading ? null : _takePhoto,
          child: Row(
            children: [
              RowThumb(
                size: 64,
                image: _photo == null ? null : FileImage(_photo!),
                icon: _photo == null ? Icons.photo_camera_outlined : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(photoLine, style: TextStyle(fontSize: 14, color: p.textSecondary))),
              if (_uploading)
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.primary))
              else if (_photoKey != null)
                Icon(Icons.check_circle, color: p.success),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: 'Name',
          required: true,
          hint: 'e.g. Peacock florals',
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        colours.when(
          loading: () => const Skeleton(height: 48, radius: 12),
          error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
          data: (rows) => PickerField(
            label: 'Main colour',
            required: true,
            value: _colourId,
            hint: 'Choose…',
            options: [for (final c in rows) PickerOption(c.id, c.label, color: colourSwatch(c.label))],
            onChanged: (v) => setState(() => _colourId = v),
          ),
        ),
        const SizedBox(height: 16),
        AppButton.primary(
          label: 'Start scanning this pile',
          icon: Icons.qr_code_scanner,
          busy: _uploading,
          onPressed: _canStart ? () => _start(colours.value ?? const []) : null,
        ),
        const SectionHeader('Use an existing pile', top: 20),
        drafts.when(
          loading: () => const LoadingState(rows: 3),
          error: (e, _) => InlineNotice('$e', icon: Icons.cloud_off_outlined, warning: true),
          data: (rows) {
            final offered = [for (final d in rows) if (!widget.excludePileIds.contains(d.id)) d];
            if (offered.isEmpty) {
              return const InlineNotice('No draft piles waiting — every delivery into piles starts with a new one.');
            }
            return AppListGroup(
              children: [
                for (final d in offered)
                  AppListRow(
                    leading: RowThumb(
                      image: d.photoUrl == null ? null : NetworkImage(d.photoUrl!),
                      icon: d.photoUrl == null ? Icons.layers_outlined : null,
                    ),
                    title: d.name,
                    subtitle: [
                      if (d.mainColour != null && d.mainColour!.isNotEmpty) d.mainColour!,
                      '${d.thaanCount} Thaan${d.thaanCount == 1 ? '' : 's'}',
                      if (d.createdStage != null) 'from ${d.createdStage}',
                    ].join(' · '),
                    chevron: true,
                    onTap: () => Navigator.pop(context, _SessionPile.existing(d)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
