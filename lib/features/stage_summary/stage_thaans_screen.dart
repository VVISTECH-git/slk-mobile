import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'stage_summary_providers.dart';

/// One bucket's Thaans, grouped by vendor and bale rather than one row per
/// Thaan — a stage with hundreds in it is unreadable as a flat list, and a
/// flat list is all a bare count ever tells you. Sorted oldest-first by
/// default, with a search box, so "who's holding what, and what's been
/// stuck longest" is answerable at real volume, not just in a demo.
/// Pushed, not routed: a drill-down from one number, the same way
/// BarcodeScanScreen is pushed rather than given its own go_router path.
class StageThaansScreen extends ConsumerStatefulWidget {
  const StageThaansScreen({super.key, required this.bucket, this.baleType});
  final String bucket;
  final String? baleType;

  @override
  ConsumerState<StageThaansScreen> createState() => _StageThaansScreenState();
}

class _StageThaansScreenState extends ConsumerState<StageThaansScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = (bucket: widget.bucket, baleType: widget.baleType);
    final groups = ref.watch(stageGroupsProvider(key));
    final q = _query.text.trim().toLowerCase();

    return AppPage(
      title: widget.baleType != null ? '${widget.bucket} · ${widget.baleType}' : widget.bucket,
      padded: false,
      body: AsyncView(
        value: groups,
        onRetry: () => ref.invalidate(stageGroupsProvider(key)),
        isEmpty: (rows) => rows.isEmpty,
        emptyMessage: 'Nothing here right now.',
        data: (rows) {
          final filtered = q.isEmpty
              ? rows
              : rows
                  .where((g) => g.baleCode.toLowerCase().contains(q) || (g.vendorName ?? '').toLowerCase().contains(q))
                  .toList();
          final total = rows.fold<int>(0, (s, g) => s + g.count);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatTile(
                      value: '$total',
                      label: 'Thaan${total == 1 ? "" : "s"} across ${rows.length} bale/vendor group${rows.length == 1 ? "" : "s"}.',
                      tone: BadgeTone.brand,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Search',
                      controller: _query,
                      hint: 'Search bale or vendor…',
                      suffix: const Icon(Icons.search, size: 20),
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(title: 'No match for "${_query.text}".', icon: Icons.search_off, compact: true)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) => _GroupRow(group: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});
  final CoreStageGroup group;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final stale = (group.daysWaiting ?? 0) >= 14;

    return AppCard(
      tone: stale ? p.danger.withValues(alpha: 0.06) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitle(
            'Bale ${group.baleCode}',
            subtitle: group.vendorName,
            trailing: Text(
              '${group.count}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: p.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (group.daysWaiting != null) ...[
            const SizedBox(height: 6),
            StatusBadge(
              '${group.daysWaiting} day${group.daysWaiting == 1 ? "" : "s"} (since ${group.since})',
              tone: stale ? BadgeTone.danger : BadgeTone.neutral,
              icon: Icons.schedule,
            ),
          ],
        ],
      ),
    );
  }
}
