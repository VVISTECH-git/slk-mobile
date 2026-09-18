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
class StageSummaryScreen extends ConsumerWidget {
  const StageSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(stageSummaryProvider);
    final p = context.p;

    return Scaffold(
      appBar: AppBar(title: const Text('Stage Summary'), actions: const [ThemeButton()]),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(stageSummaryProvider),
        child: AsyncView(
          value: summary,
          onRetry: () => ref.invalidate(stageSummaryProvider),
          isEmpty: (rows) => rows.isEmpty,
          emptyMessage: 'No Thaans on file yet.',
          data: (rows) {
            final total = rows.fold<int>(0, (s, r) => s + r.count);
            final maxCount = rows.fold<int>(1, (m, r) => r.count > m ? r.count : m);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  '$total Thaan${total == 1 ? "" : "s"} across the pipeline right now.',
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                for (final row in rows)
                  _StageRow(
                    row: row,
                    maxCount: maxCount,
                    onTap: row.count == 0
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => StageThaansScreen(bucket: row.bucket)),
                            ),
                  ),
              ],
            );
          },
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
