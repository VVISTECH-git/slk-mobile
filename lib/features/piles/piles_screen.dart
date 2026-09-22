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
  /// Null is "All" — the query is left off.
  String? _status = 'draft';

  static const _filters = <(String?, String)>[
    ('draft', 'Draft'),
    ('ready', 'Ready'),
    ('live', 'Live'),
    (null, 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    final piles = ref.watch(pilesProvider(_status));

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
              onRetry: () => ref.invalidate(pilesProvider(_status)),
              isEmpty: (rows) => rows.isEmpty,
              emptyMessage: _status == null ? 'No piles yet.' : 'No ${_status!} piles.',
              data: (rows) => RefreshIndicator(
                onRefresh: () => ref.refresh(pilesProvider(_status).future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _PileRow(pile: rows[i]),
                ),
              ),
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
    final detail = [
      '${p.thaanCount} Thaan${p.thaanCount == 1 ? '' : 's'}',
      if (p.createdStage != null) 'from ${p.createdStage}',
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
              trailing: pileStatusBadge(p.status),
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

/// "19 Sep 2026" from whatever the server sent — an ISO timestamp becomes
/// the app's own date shape; anything else is shown as it came.
String pileDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : AppDateField.format(parsed.toLocal());
}
