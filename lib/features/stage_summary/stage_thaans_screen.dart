import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
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
    final p = context.p;
    final q = _query.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(widget.baleType != null ? '${widget.bucket} · ${widget.baleType}' : widget.bucket)),
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
                    Text(
                      '$total Thaan${total == 1 ? "" : "s"} across ${rows.length} bale/vendor group${rows.length == 1 ? "" : "s"}.',
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search bale or vendor…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('No match for "${_query.text}".', style: TextStyle(color: p.textSecondary)))
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: stale ? p.danger.withValues(alpha: 0.5) : p.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bale ${group.baleCode}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (group.vendorName != null) ...[
                  const SizedBox(height: 2),
                  Text(group.vendorName!, style: TextStyle(color: p.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                ],
                if (group.daysWaiting != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${group.daysWaiting} day${group.daysWaiting == 1 ? "" : "s"} (since ${group.since})',
                    style: TextStyle(
                      color: stale ? p.danger : p.textSecondary,
                      fontWeight: stale ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text('${group.count}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.text)),
        ],
      ),
    );
  }
}
