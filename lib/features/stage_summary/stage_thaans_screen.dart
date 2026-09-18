import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'stage_summary_providers.dart';

/// The actual Thaans sitting in one stage-summary bucket — pushed, not
/// routed: a drill-down from one number, the same way BarcodeScanScreen is
/// pushed rather than given its own go_router path.
class StageThaansScreen extends ConsumerWidget {
  const StageThaansScreen({super.key, required this.bucket});
  final String bucket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thaans = ref.watch(stageThaansProvider(bucket));
    final p = context.p;

    return Scaffold(
      appBar: AppBar(title: Text(bucket)),
      body: AsyncView(
        value: thaans,
        onRetry: () => ref.invalidate(stageThaansProvider(bucket)),
        isEmpty: (rows) => rows.isEmpty,
        emptyMessage: 'Nothing here right now.',
        data: (rows) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final t = rows[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.thaanCode ?? 'no code yet',
                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text('Bale ${t.baleCode}', style: TextStyle(color: p.textSecondary, fontSize: 12)),
                    ],
                  ),
                  if (t.vendorName != null)
                    Text(t.vendorName!, style: TextStyle(color: p.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
