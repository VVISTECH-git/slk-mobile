import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';

/// Production Manager and Operations Manager's own whole-pipeline view —
/// how many Thaans currently sit at each stage, and which ones, either
/// across the whole business or narrowed to one bale type. Talks to
/// `/api/v1/thaans/{stage,type}-summary*`, which wraps slk-core's own
/// `loadStageSummary`/`loadThaansInBucket`/`loadTypeSummary`
/// (apps/web/src/lib/thaans.ts).
///
/// All three are `.autoDispose` — a fresh fetch every time Stage Summary is
/// actually opened, not the stale-until-someone-remembers-to-pull-to-refresh
/// bug an earlier, non-autoDispose version of this file had (a bale's type
/// changed on the web; the app kept showing the old breakdown indefinitely).
/// The By Stage / By Type toggle stays instant anyway: stage_summary_screen
/// keeps both sides mounted in an `IndexedStack` rather than building only
/// the active one, so neither provider is ever unwatched — and therefore
/// never torn down — just by flipping the toggle. Only actually leaving the
/// screen disposes them, which is exactly when a stale value stops mattering
/// and a fresh one is wanted next time.

/// How many Thaans currently sit at each point in the pipeline — the whole
/// business when [baleType] is null, one bale type's own pipeline when set.
final stageSummaryProvider = FutureProvider.autoDispose.family<List<CoreStageSummaryRow>, String?>((ref, baleType) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/stage-summary', query: {if (baleType != null) 'type': baleType});
  return [
    for (final row in (data as List)) CoreStageSummaryRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// One bucket's Thaans, grouped by vendor and bale — fetched on drill-down, not baked into the summary.
final stageGroupsProvider =
    FutureProvider.autoDispose.family<List<CoreStageGroup>, ({String bucket, String? baleType})>((ref, key) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/stage-summary/thaans', query: {
    'bucket': key.bucket,
    if (key.baleType != null) 'type': key.baleType,
  });
  return [
    for (final row in (data as List)) CoreStageGroup.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// Every bale type's own completion — the reorder signal.
final typeSummaryProvider = FutureProvider.autoDispose<List<CoreTypeSummaryRow>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/type-summary');
  return [
    for (final row in (data as List)) CoreTypeSummaryRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});
