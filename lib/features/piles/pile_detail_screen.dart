import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'pile_providers.dart';
import 'piles_screen.dart' show pileDate, pileNeedsBadge, pileStatusBadge;

/// One pile: its photo, what it is, the Thaans in it and what has happened
/// to it. Reached by tapping a row on [PilesScreen]. The one action is to
/// fill in (or change) its details — motif, craft, colours — on
/// [CompletePileScreen].
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
      bottomBar: pile.value == null
          ? null
          : BottomActionBar(
              primary: AppButton.primary(
                label: pile.value!.needs.isEmpty ? 'Edit details' : 'Complete details',
                icon: Icons.edit_outlined,
                onPressed: () => context.push('/core/piles/$pileId/complete'),
              ),
            ),
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
                        trailing: t.voidedAt == null ? null : const StatusBadge('Voided', tone: BadgeTone.danger),
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

  static String _eventTitle(CorePileEvent e) {
    final kind = e.kind.isEmpty ? 'Event' : '${e.kind[0].toUpperCase()}${e.kind.substring(1)}';
    return e.stage == null ? kind : '$kind · ${e.stage}';
  }
}
