import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';

/// Production Manager and Operations Manager's own whole-pipeline view —
/// how many Thaans currently sit at each stage, and which ones, either
/// across the whole business or narrowed to one bale type. Talks to
/// `/api/v1/thaans/{stage,type}-summary*`, which wraps slk-core's own
/// `loadStageSummary`/`loadThaansInBucket`/`loadTypeSummary`
/// (apps/web/src/lib/thaans.ts).

/// None of these three are `.autoDispose`, on purpose: the Stage Summary
/// screen's By Stage / By Type toggle only ever mounts one side at a time,
/// so an `.autoDispose` provider backing the hidden side gets torn down the
/// moment it stops being watched — every single tap of the toggle would
/// then refetch from scratch and show a fresh loading spinner, even though
/// nothing on the server had changed since the last look. Kept alive for
/// the app's lifetime instead; pull-to-refresh (`ref.invalidate`) still
/// forces a real refetch when the data actually might have moved.

/// How many Thaans currently sit at each point in the pipeline — the whole
/// business when [baleType] is null, one bale type's own pipeline when set.
final stageSummaryProvider = FutureProvider.family<List<CoreStageSummaryRow>, String?>((ref, baleType) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/stage-summary', query: {if (baleType != null) 'type': baleType});
  return [
    for (final row in (data as List)) CoreStageSummaryRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// One bucket's Thaans, grouped by vendor and bale — fetched on drill-down, not baked into the summary.
final stageGroupsProvider = FutureProvider.family<List<CoreStageGroup>, ({String bucket, String? baleType})>((ref, key) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/stage-summary/thaans', query: {
    'bucket': key.bucket,
    if (key.baleType != null) 'type': key.baleType,
  });
  return [
    for (final row in (data as List)) CoreStageGroup.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// Every bale type's own completion — the reorder signal.
final typeSummaryProvider = FutureProvider<List<CoreTypeSummaryRow>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/thaans/type-summary');
  return [
    for (final row in (data as List)) CoreTypeSummaryRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});
