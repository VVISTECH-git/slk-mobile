import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';

/// Kora to Shelf, step three: a Thaan's trip through the stage pipeline.
///
/// Talks to the REST surface `/api/v1/handovers/*` and `/api/v1/vendors`
/// wraps around slk-core's own Send/Receive Server Actions
/// (apps/web/src/app/handovers/actions.ts) — see that file for the business
/// logic (auto-detecting the next stage from a scan, per-Thaan
/// re-validation, automatic billing on receive), which lives there once
/// rather than twice.

/// The stage pipeline, in order — matches slk-core's own `STAGES`
/// (apps/web/src/lib/stages.ts). Label Stitching is sent automatically when
/// QR codes are generated, so it never belongs in a manual Send picker —
/// see [kSendableStages].
const kStages = <String>[
  'Label Stitching',
  'Salava',
  'Karakkaya',
  'Print',
  'Second Print',
  'Nellateeta',
  'Udukulu',
  'Ironing',
];

/// [kStages] minus Label Stitching — what the Send screen's stage picker
/// actually offers.
const kSendableStages = <String>[
  'Salava',
  'Karakkaya',
  'Print',
  'Second Print',
  'Nellateeta',
  'Udukulu',
  'Ironing',
];

/// "Salava" -> "Salava + Karakkaya": the name of a combined trip, one vendor
/// doing several stages in a single visit. [through] null or empty (or not
/// after [stage]) is the ordinary one-stage trip.
String tripLabel(String stage, String? through) {
  if (through == null || through.isEmpty) return stage;
  final from = kStages.indexOf(stage);
  final to = kStages.indexOf(through);
  if (from < 0 || to <= from) return stage;
  return kStages.sublist(from, to + 1).join(' + ');
}

/// The stages after [stage] that [vendorStages] also covers, in unbroken
/// order: what one visit could cover. Stops at the first one the vendor
/// doesn't do, since the cloth can't skip a stage on its way through.
List<String> alsoStages(List<String>? vendorStages, String? stage) {
  if (vendorStages == null || stage == null) return const [];
  final out = <String>[];
  for (var i = kStages.indexOf(stage) + 1; i > 0 && i < kStages.length; i++) {
    if (!vendorStages.contains(kStages[i])) break;
    out.add(kStages[i]);
  }
  return out;
}

/// Every vendor who could be sent a batch — the Send screen's picker.
final coreVendorsProvider = FutureProvider.autoDispose<List<CoreVendor>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/vendors');
  return [
    for (final row in (data as List)) CoreVendor.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// One pile inside a receive — either a pile that already exists
/// ([pileId]) or one to make right now ([newPile]), and which of the
/// batch's Thaans go in it. Thaans in the receive that no spec names are
/// received just as Thaans.
class ReceivePileSpec {
  const ReceivePileSpec({
    this.pileId,
    this.newPile,
    required this.thaanIds,
  }) : assert(pileId != null || newPile != null, 'a pile is either existing or new');

  final String? pileId;
  final ({String name, String mainColourId, String photoKey})? newPile;
  final List<String> thaanIds;

  Map<String, dynamic> toJson() => {
        'pileId': pileId,
        'newPile': newPile == null
            ? null
            : {
                'name': newPile!.name,
                'mainColourId': newPile!.mainColourId,
                'photoKey': newPile!.photoKey,
              },
        'thaanIds': thaanIds,
      };
}

final handoverRepositoryProvider = Provider((ref) => HandoverRepository(ref));

class HandoverRepository {
  HandoverRepository(this.ref);
  final Ref ref;

  /// Whether [code] can be sent for [stage] right now, and the Thaan it
  /// names if so. [stage] null means "not chosen yet" — the resolved stage
  /// comes back regardless, so the first scan of a batch can read its own
  /// next stage rather than being refused.
  Future<({CoreThaanForSend thaan, String stage})> lookupForSend({
    required String code,
    String? stage,
  }) async {
    final data = await ref.read(coreApiProvider).post(
          '/handovers/lookup-send',
          body: {'code': code, if (stage != null) 'stage': stage},
        );
    final map = (data as Map).cast<String, dynamic>();
    return (
      thaan: CoreThaanForSend.fromJson((map['thaan'] as Map).cast<String, dynamic>()),
      stage: map['stage'] as String,
    );
  }

  /// Sends a scanned batch off for one stage, to one vendor (or in-house,
  /// when [vendorId] is null). Returns the confirmation message.
  Future<String> sendBatch({
    required String stage,
    String? vendorId,
    required List<String> thaanIds,
    String? throughStage,
  }) async {
    final data = await ref.read(coreApiProvider).post('/handovers/send', body: {
      'stage': stage,
      'vendorId': vendorId,
      'thaanIds': thaanIds,
      if (throughStage != null) 'throughStage': throughStage,
    });
    return (data as Map)['message'] as String;
  }

  /// Whether [code] is out for some stage right now, and what it's
  /// returning from.
  Future<CoreThaanForReceive> lookupForReceive(String code) async {
    final data = await ref.read(coreApiProvider).post('/handovers/lookup-receive', body: {'code': code});
    final map = (data as Map).cast<String, dynamic>();
    return CoreThaanForReceive.fromJson((map['thaan'] as Map).cast<String, dynamic>());
  }

  /// Marks a scanned batch received, and bills whatever came back from a
  /// vendor at their rate for that stage. Returns the confirmation message.
  ///
  /// [piles], when given, sorts some of [thaanIds] into piles as they come
  /// in — one delivery, one bill, whatever the piles. Left off, the request
  /// is exactly what it always was.
  Future<String> receiveBatch(List<String> thaanIds, {List<ReceivePileSpec>? piles}) async {
    final body = <String, dynamic>{'thaanIds': thaanIds};
    if (piles != null && piles.isNotEmpty) body['piles'] = [for (final p in piles) p.toJson()];
    final data = await ref.read(coreApiProvider).post('/handovers/receive', body: body);
    return (data as Map)['message'] as String;
  }
}
