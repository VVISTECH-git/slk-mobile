import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'pile_providers.dart';
import 'piles_screen.dart' show pileDate, pileNeedsBadge, pileOnShelfBadge, pileReadyForShelfBadge, pileStatusBadge;

/// One pile: its photo, what it is, the Thaans in it and what has happened
/// to it. Reached by tapping a row on [PilesScreen]. Its actions: fill in
/// (or change) its details — motif, craft, colours — on [CompletePileScreen],
/// and, once Thaans are back from Ironing, put them on the shelf on
/// [ShelfPileScreen] — the primary the moment there is something to shelve.
class PileDetailScreen extends ConsumerWidget {
  const PileDetailScreen({super.key, required this.pileId});
  final String pileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pile = ref.watch(pileDetailProvider(pileId));

    return AppPage(
      title: pile.value?.name ?? 'Pile',
      subtitle: pile.value?.code,
      actions: const [ThemeButton()],
      padded: false,
      bottomBar: pile.value == null ? null : _bottomBar(context, pile.value!),
      body: AsyncView<CorePile>(
        value: pile,
        onRetry: () => ref.invalidate(pileDetailProvider(pileId)),
        data: (p) => RefreshIndicator(
          onRefresh: () => ref.refresh(pileDetailProvider(pileId).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: RowThumb(
                  size: 200,
                  image: p.photoUrl == null ? null : NetworkImage(p.photoUrl!),
                  icon: p.photoUrl == null ? Icons.layers_outlined : null,
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardTitle(
                      p.name,
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          pileStatusBadge(p.status),
                          if (p.needs.isNotEmpty) ...[const SizedBox(height: 4), pileNeedsBadge(p.needs)],
                          if (p.finishedCount > 0) ...[const SizedBox(height: 4), pileReadyForShelfBadge(p.finishedCount)],
                          if (p.shelvedCount > 0) ...[const SizedBox(height: 4), pileOnShelfBadge(p.shelvedCount)],
                        ],
                      ),
                    ),
                    const Divider(height: 20),
                    KeyValueRow('Code', p.code, mono: true),
                    KeyValueRow('Record', p.recordLabel ?? 'Not yet'),
                    KeyValueRow('Main colour', p.mainColour ?? '—'),
                    if (p.stage.isNotEmpty) KeyValueRow('Now at', p.stage),
                    KeyValueRow('Made at', p.createdStage ?? '—'),
                    KeyValueRow('Status', p.status),
                    KeyValueRow('Thaans', '${p.thaanCount}', strong: true),
                    KeyValueRow('Back from Ironing', '${p.finishedCount}'),
                    KeyValueRow('On shelf', '${p.shelvedCount}'),
                    if (p.baleCodes.isNotEmpty) KeyValueRow('Bales', p.baleCodes.join(', '), mono: true),
                    KeyValueRow('Made on', pileDate(p.createdAt)),
                    if (p.createdByName != null) KeyValueRow('Made by', p.createdByName!),
                  ],
                ),
              ),
              SectionHeader('Thaans', trailing: Text('${p.thaans.length}')),
              if (p.thaans.isEmpty)
                const EmptyState(compact: true, title: 'No Thaans in this pile.', icon: Icons.qr_code_2)
              else
                AppListGroup(
                  children: [
                    for (final t in p.thaans)
                      AppListRow(
                        title: t.code,
                        titleMono: true,
                        subtitle: [
                          if (t.baleCode != null) t.baleCode!,
                          t.openStage != null
                              ? 'Out for ${t.openStage}'
                              : '${t.completedStages} stage${t.completedStages == 1 ? '' : 's'} done',
                        ].join(' · '),
                        trailing: _thaanBadge(t),
                      ),
                  ],
                ),
              SectionHeader('History', trailing: Text('${p.events.length}')),
              if (p.events.isEmpty)
                const EmptyState(compact: true, title: 'Nothing recorded yet.', icon: Icons.history)
              else
                AppListGroup(
                  children: [
                    for (final e in p.events)
                      AppListRow(
                        title: _eventTitle(e),
                        subtitle: [
                          if (e.thaanCode != null) e.thaanCode!,
                          if (e.kind == 'moved' && e.from != null) 'from ${e.from}',
                          if (e.actorName != null) e.actorName!,
                          if (e.at != null) pileDate(e.at),
                        ].join(' · '),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Complete/edit details stays the one button until something is back
  /// from Ironing; then shelving is the primary and details step aside.
  Widget _bottomBar(BuildContext context, CorePile p) {
    final detailsLabel = p.needs.isEmpty ? 'Edit details' : 'Complete details';
    void openDetails() => context.push('/core/piles/$pileId/complete');

    if (p.finishedCount == 0) {
      return BottomActionBar(
        primary: AppButton.primary(label: detailsLabel, icon: Icons.edit_outlined, onPressed: openDetails),
      );
    }
    final n = p.finishedCount;
    return BottomActionBar(
      secondary: AppButton.secondary(label: detailsLabel, icon: Icons.edit_outlined, onPressed: openDetails),
      primary: AppButton.primary(
        label: p.shelvedCount > 0 ? 'Add $n more to shelf' : 'Put on shelf ($n)',
        icon: Icons.inventory_2_outlined,
        onPressed: () => context.push('/core/piles/$pileId/shelf'),
      ),
    );
  }

  /// Voided beats shelved: a voided Thaan is never stock.
  static Widget? _thaanBadge(CorePileThaan t) {
    if (t.voidedAt != null) return const StatusBadge('Voided', tone: BadgeTone.danger);
    if (t.pieceCode != null) return const StatusBadge('On shelf', tone: BadgeTone.success);
    return null;
  }

  static String _eventTitle(CorePileEvent e) {
    final kind = e.kind.isEmpty ? 'Event' : '${e.kind[0].toUpperCase()}${e.kind.substring(1)}';
    return e.stage == null ? kind : '$kind · ${e.stage}';
  }
}
