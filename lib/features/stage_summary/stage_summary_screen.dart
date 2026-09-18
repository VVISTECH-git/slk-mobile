import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import 'stage_summary_providers.dart';
import 'stage_thaans_screen.dart';

/// How many Thaans currently sit at each point in the pipeline — Production
/// Manager and Operations Manager's own landing screen. Tap a stage to see
/// the actual Thaans behind its count (see stage_thaans_screen.dart).
///
/// The whole-business view (`baleType == null`) also offers a "By Type"
/// lens — which bale type is close to fully Finished and needs raw cloth
/// reordered — that this same screen re-opens itself with, one bale type
/// at a time (`baleType` set, toggle hidden): there's nothing to further
/// split a single type's own pipeline by.
class StageSummaryScreen extends ConsumerStatefulWidget {
  const StageSummaryScreen({super.key, this.baleType});
  final String? baleType;

  @override
  ConsumerState<StageSummaryScreen> createState() => _StageSummaryScreenState();
}

enum _View { byStage, byType }

class _StageSummaryScreenState extends ConsumerState<StageSummaryScreen> {
  _View _view = _View.byStage;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.baleType == null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.baleType ?? 'Stage Summary'), actions: const [ThemeButton()]),
      body: Column(
        children: [
          if (showToggle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ViewToggle(view: _view, onChanged: (v) => setState(() => _view = v)),
            ),
          Expanded(
            child: showToggle
                // Both sides stay mounted (and so keep watching their own
                // provider, which is what stops `.autoDispose` from tearing
                // either one down) the whole time this screen is open —
                // only the currently-selected one is actually visible.
                // Toggling is then just a paint switch, not a re-fetch.
                ? IndexedStack(
                    index: _view == _View.byStage ? 0 : 1,
                    sizing: StackFit.expand,
                    children: const [_StageList(baleType: null), _TypeList()],
                  )
                : _StageList(baleType: widget.baleType),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});
  final _View view;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_View>(
      segments: const [
        ButtonSegment(value: _View.byStage, label: Text('By Stage')),
        ButtonSegment(value: _View.byType, label: Text('By Type')),
      ],
      selected: {view},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _StageList extends ConsumerWidget {
  const _StageList({required this.baleType});
  final String? baleType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(stageSummaryProvider(baleType));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(stageSummaryProvider(baleType)),
      child: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(stageSummaryProvider(baleType)),
        isEmpty: (rows) => rows.isEmpty,
        emptyMessage: 'No Thaans on file yet.',
        data: (rows) {
          final total = rows.fold<int>(0, (s, r) => s + r.count);
          final maxCount = rows.fold<int>(1, (m, r) => r.count > m ? r.count : m);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                '$total Thaan${total == 1 ? "" : "s"} ${baleType != null ? "of $baleType " : ""}across the pipeline right now.',
                style: TextStyle(color: context.p.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              for (final row in rows)
                _StageRow(
                  row: row,
                  maxCount: maxCount,
                  onTap: row.count == 0
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => StageThaansScreen(bucket: row.bucket, baleType: baleType)),
                          ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TypeList extends ConsumerWidget {
  const _TypeList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(typeSummaryProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(typeSummaryProvider),
      child: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(typeSummaryProvider),
        isEmpty: (rows) => rows.isEmpty,
        emptyMessage: 'No Thaans on file yet.',
        data: (rows) {
          final sorted = [...rows]..sort((a, b) => b.finishedFraction.compareTo(a.finishedFraction));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                "How close each bale type is to fully Finished — a type near the top with little left behind it is one to reorder raw cloth for.",
                style: TextStyle(color: context.p.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              for (final row in sorted)
                _TypeRow(
                  row: row,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => StageSummaryScreen(baleType: row.type)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.row, required this.onTap});
  final CoreTypeSummaryRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final remaining = row.total - row.finished;
    final needsReorder = row.finishedFraction >= 0.9;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: needsReorder ? p.primary.withValues(alpha: 0.6) : p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(row.type, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.text)),
                          if (needsReorder) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Consider reordering',
                                style: TextStyle(color: p.primary, fontWeight: FontWeight.w700, fontSize: 10.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '${(row.finishedFraction * 100).round()}%',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.text),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.finished} of ${row.total} Finished · $remaining still in the pipeline',
                  style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: row.finishedFraction.clamp(0.02, 1.0),
                    minHeight: 5,
                    backgroundColor: p.surface3,
                    valueColor: AlwaysStoppedAnimation(needsReorder ? p.primary : p.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.row, required this.maxCount, required this.onTap});
  final CoreStageSummaryRow row;
  final int maxCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final fraction = row.count / maxCount;
    final isTerminal = row.bucket == 'Not started' || row.bucket == 'Finished';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        row.bucket,
                        style: TextStyle(
                          fontWeight: isTerminal ? FontWeight.w500 : FontWeight.w700,
                          fontStyle: isTerminal ? FontStyle.italic : FontStyle.normal,
                          color: isTerminal ? p.textSecondary : p.text,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '${row.count}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: p.text),
                    ),
                  ],
                ),
                if (row.oldestDaysWaiting != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Oldest waiting ${row.oldestDaysWaiting} day${row.oldestDaysWaiting == 1 ? "" : "s"} (since ${row.oldestSince})',
                    style: TextStyle(
                      color: row.oldestDaysWaiting! >= 14 ? p.danger : p.textSecondary,
                      fontWeight: row.oldestDaysWaiting! >= 14 ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.02, 1.0),
                    minHeight: 5,
                    backgroundColor: p.surface3,
                    valueColor: AlwaysStoppedAnimation(isTerminal ? p.textMuted : p.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
