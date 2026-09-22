import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import 'core_auth.dart';

/// The production pipeline behind a Product Management record.
///
/// When Thaans come back from Print the receiver sorts them by colour and
/// motif, and each group becomes a draft record (a colourway) in the same
/// receive. From then on the record is the thing: its Thaans are listed on
/// it, its details are filled in on it, and once they are back from Ironing
/// they are put on the shelf from it as pieces. Talks to slk-core's
/// `/records/pipeline`, `/records/:id/thaans`, `/records/:id/fill` and
/// `/records/:id/shelf`; the business rules (Print or later only, what
/// "ready" means, what a shelve needs) live there once, not here as well.

/// Records with Thaans behind them, by status — `in_pipeline`, `ready`
/// (something back from Ironing) or `shelved`. The picker every "which
/// record?" sheet reads.
final pipelineRecordsProvider =
    FutureProvider.autoDispose.family<List<CorePipelineRecord>, String>((ref, status) async {
  final data = await ref.watch(coreApiProvider).get('/records/pipeline', query: {'status': status});
  return [
    for (final row in (data as List)) CorePipelineRecord.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// The Thaans linked to one record — `GET /records/:id/thaans`.
final recordThaansProvider = FutureProvider.autoDispose.family<List<CorePipelineThaan>, String>((ref, id) async {
  final data = await ref.watch(coreApiProvider).get('/records/$id/thaans');
  return [
    for (final row in (data as List)) CorePipelineThaan.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// What the fill screen shows for one record: the details the bale's cloth
/// item already settled, the ones decided at this stage, and what has been
/// picked so far. `GET /records/:id/fill`.
final recordFillProvider = FutureProvider.autoDispose.family<CoreRecordFill, String>((ref, id) async {
  final data = await ref.watch(coreApiProvider).get('/records/$id/fill');
  return CoreRecordFill.fromJson((data as Map).cast<String, dynamic>());
});

/// What the shelf screen shows for one record: the Thaans back from Ironing
/// that would go, the ones on the shelf already, the prices so far, where
/// they can go, and anything in the way. `GET /records/:id/shelf`.
final recordShelfProvider = FutureProvider.autoDispose.family<CoreRecordShelf, String>((ref, id) async {
  final data = await ref.watch(coreApiProvider).get('/records/$id/shelf');
  return CoreRecordShelf.fromJson((data as Map).cast<String, dynamic>());
});

/// What `POST /records/:id/thaans` did with each Thaan it was given.
class AddThaansOutcome {
  const AddThaansOutcome({
    required this.message,
    required this.added,
    required this.moved,
    required this.refused,
  });

  final String message;
  final int added;

  /// Taken out of another record and put in this one.
  final int moved;

  /// Left where they were, each with the server's reason.
  final List<({String code, String why})> refused;

  factory AddThaansOutcome.fromJson(Map<String, dynamic> json) {
    final outcome = (json['outcome'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AddThaansOutcome(
      message: '${json['message'] ?? ''}',
      added: (outcome['added'] as num?)?.toInt() ?? 0,
      moved: (outcome['moved'] as num?)?.toInt() ?? 0,
      refused: [
        for (final r in (outcome['refused'] as List? ?? const []))
          (code: '${(r as Map)['code']}', why: '${r['why'] ?? ''}'),
      ],
    );
  }
}

final pipelineRepositoryProvider = Provider((ref) => PipelineRepository(ref));

class PipelineRepository {
  PipelineRepository(this.ref);
  final Ref ref;

  /// Links Thaans to a record — moving any that were in another one. The
  /// server refuses what it can't link (not back from Print yet, voided)
  /// and says why, per code, in the outcome.
  Future<AddThaansOutcome> addThaans(String recordId, List<String> thaanIds) async {
    final data = await ref.read(coreApiProvider).post('/records/$recordId/thaans', body: {'thaanIds': thaanIds});
    return AddThaansOutcome.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Fills in a record's details — motif, craft, border, colours. Every
  /// field key goes up with its current value (null for "not yet"). The
  /// server answers with what is still missing, if anything.
  Future<({String message, List<String> needs})> fill(
    String recordId, {
    required Map<String, String?> attributes,
    String? colourId,
    String? secondaryColourId,
  }) async {
    final body = <String, dynamic>{
      'attributes': attributes,
      'colourId': ?colourId,
      // Sent even when null, so clearing the secondary colour sticks.
      'secondaryColourId': secondaryColourId,
    };
    final data = await ref.read(coreApiProvider).post('/records/$recordId/fill', body: body);
    final map = (data as Map).cast<String, dynamic>();
    return (
      message: '${map['message'] ?? 'Saved'}',
      needs: [
        for (final n in (map['needs'] as List? ?? const []))
          if (n != null && '$n'.isNotEmpty) '$n',
      ],
    );
  }

  /// Puts every Thaan back from Ironing on the shelf: each becomes a piece
  /// with its own code (the QR label already on it), stock at [locationId],
  /// under the record's product. Retail is the one price the server
  /// insists on; the others may be "". Repeatable as more Thaans finish.
  /// Returns the product code and the new piece codes.
  Future<({String message, String productCode, List<String> pieceCodes})> shelve(
    String recordId, {
    required CoreShelfPrices prices,
    required String locationId,
  }) async {
    final data = await ref.read(coreApiProvider).post(
      '/records/$recordId/shelf',
      body: {'prices': prices.toJson(), 'locationId': locationId},
    );
    final map = (data as Map).cast<String, dynamic>();
    return (
      message: '${map['message'] ?? 'On the shelf'}',
      productCode: '${map['productCode'] ?? ''}',
      pieceCodes: [
        for (final c in (map['pieceCodes'] as List? ?? const []))
          if (c != null && '$c'.isNotEmpty) '$c',
      ],
    );
  }
}
