import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';

/// Production Manager and Operations Manager's own whole-pipeline view —
/// how many Thaans currently sit at each stage, and which ones. Talks to
/// `/api/v1/thaans/stage-summary*`, which wraps slk-core's own
/// `loadStageSummary`/`loadThaansInBucket` (apps/web/src/lib/thaans.ts).

/// How many Thaans currently sit at each point in the pipeline.
final stageSummaryProvider = FutureProvider.autoDispose<List<CoreStageSummaryRow>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/stage-summary');
  return [
    for (final row in (data as List)) CoreStageSummaryRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// The actual Thaans behind one bucket's count — fetched on drill-down, not baked into the summary.
final stageThaansProvider = FutureProvider.autoDispose.family<List<CoreStageThaan>, String>((ref, bucket) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/stage-summary/thaans', query: {'bucket': bucket});
  return [
    for (final row in (data as List)) CoreStageThaan.fromJson((row as Map).cast<String, dynamic>()),
  ];
});
