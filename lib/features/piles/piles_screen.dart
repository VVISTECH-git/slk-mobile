import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'pile_providers.dart';

/// Every pile, by status — what came back from Print sorted into designs.
/// Read-only here: piles are made at the door (Handovers → Receive, in
/// piles) and a single Thaan is moved from Scan a Thaan.
class PilesScreen extends ConsumerStatefulWidget {
  const PilesScreen({super.key});

  @override
  ConsumerState<PilesScreen> createState() => _PilesScreenState();
}

class _PilesScreenState extends ConsumerState<PilesScreen> {
  /// "To complete" — not a server status: every draft or ready pile that
  /// still has something to fill in. Fetched as All, filtered here.
  static const _toComplete = 'to-complete';

  /// "Ready for shelf" — also not a server status: every pile with Thaans
  /// back from Ironing that are not stock yet. Fetched as All, filtered here.
  static const _readyForShelf = 'ready-for-shelf';

  /// Null is "All" — the query is left off.
  String? _status = _toComplete;

  static const _filters = <(String?, String)>[
    (_toComplete, 'To complete'),
    (_readyForShelf, 'Ready for shelf'),
    ('draft', 'Draft'),
    ('ready', 'Ready'),
    ('live', 'Live'),
    (null, 'All'),
  ];

  bool get _local => _status == _toComplete || _status == _readyForShelf;

  String? get _query => _local ? null : _status;

  static bool _needsCompleting(CorePile p) =>
      (p.status == 'draft' || p.status == 'ready') && p.needs.isNotEmpty;

  List<CorePile> _visible(List<CorePile> rows) => switch (_status) {
        _toComplete => [for (final p in rows) if (_needsCompleting(p)) p],
        _readyForShelf => [for (final p in rows) if (p.finishedCount > 0) p],
        _ => rows,
      };

  String get _emptyMessage => switch (_status) {
        _toComplete => 'Nothing to complete — every pile has its details.',
        _readyForShelf => 'Nothing back from Ironing yet.',
        null => 'No piles yet.',
        final s => 'No $s piles.',
      };

  @override
  Widget build(BuildContext context) {
    final piles = ref.watch(pilesProvider(_query));

    return AppPage(
      title: 'Piles',
      actions: const [ThemeButton()],
      padded: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, label) in _filters)
                  ChoiceChip(
                    label: Text(label),
                    selected: _status == key,
                    onSelected: (_) => setState(() => _status = key),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<CorePile>>(
              value: piles,
              onRetry: () => ref.invalidate(pilesProvider(_query)),
              isEmpty: (rows) => _visible(rows).isEmpty,
              emptyMessage: _emptyMessage,
              data: (rows) {
                final shown = _visible(rows);
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(pilesProvider(_query).future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PileRow(pile: shown[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PileRow extends StatelessWidget {
  const _PileRow({required this.pile});
  final CorePile pile;

  @override
  Widget build(BuildContext context) {
    final p = pile;
    final stage = p.stageLabel;
    final detail = [
      '${p.thaanCount} Thaan${p.thaanCount == 1 ? '' : 's'}',
      if (stage != null && stage.isNotEmpty) 'at $stage',
      if (p.createdAt != null) pileDate(p.createdAt),
    ].join(' · ');

    return AppCard(
      onTap: () => context.push('/core/piles/${p.id}'),
      child: Row(
        children: [
          RowThumb(
            size: 52,
            image: p.photoUrl == null ? null : NetworkImage(p.photoUrl!),
            icon: p.photoUrl == null ? Icons.layers_outlined : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CardTitle(
              p.mainColour == null || p.mainColour!.isEmpty ? p.name : '${p.name} · ${p.mainColour}',
              subtitle: detail,
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  pileStatusBadge(p.status),
                  if (p.needs.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    pileNeedsBadge(p.needs),
                  ],
                  if (p.finishedCount > 0) ...[
                    const SizedBox(height: 4),
                    pileReadyForShelfBadge(p.finishedCount),
                  ],
                  if (p.shelvedCount > 0) ...[
                    const SizedBox(height: 4),
                    pileOnShelfBadge(p.shelvedCount),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: context.p.textMuted),
        ],
      ),
    );
  }
}

/// Draft, Ready, Live — the badge for a pile's status, toned the way the
/// rest of the app tones "not yet / nearly / done".
StatusBadge pileStatusBadge(String status) {
  final tone = switch (status) {
    'live' => BadgeTone.success,
    'ready' => BadgeTone.brand,
    _ => BadgeTone.neutral,
  };
  final label = status.isEmpty ? '—' : '${status[0].toUpperCase()}${status.substring(1)}';
  return StatusBadge(label, tone: tone);
}

/// "Needs motif, craft" — what a pile is still waiting on, in the warning
/// tone: not wrong, just not done.
StatusBadge pileNeedsBadge(List<String> needs) =>
    StatusBadge('Needs ${needs.join(', ')}', tone: BadgeTone.warning);

/// "3 ready for shelf" — Thaans back from Ironing that "Put on shelf"
/// would take. Success-toned: the pipeline did its job.
StatusBadge pileReadyForShelfBadge(int n) => StatusBadge('$n ready for shelf', tone: BadgeTone.success);

/// "5 on shelf" — already stock, in the quiet tone: done, nothing to do.
StatusBadge pileOnShelfBadge(int n) => StatusBadge('$n on shelf');

/// "19 Sep 2026" from whatever the server sent — an ISO timestamp becomes
/// the app's own date shape; anything else is shown as it came.
String pileDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : AppDateField.format(parsed.toLocal());
}
