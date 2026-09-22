import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';
import '../core/core_photos.dart' show contentTypeOf;

/// Piles — Phase 1.
///
/// A pile is the Thaans that came back from Print printed the same way: one
/// design, one colour combination. It's made at the door, as a delivery is
/// received (a photo of one Thaan, a name, the main colour), and a Thaan
/// keeps its pile through later stages unless somebody moves it. Talks to
/// slk-core's `/piles/*`; the business rules (Print or later only, what
/// "ready" and "live" mean) live there once, not here as well.

/// The main colours a pile can be labelled with — the picker's options.
/// Not autoDispose: a short fixed vocabulary, wanted by every pile sheet.
final pileColoursProvider = FutureProvider<List<CoreColour>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/piles/colours');
  return [
    for (final row in (data as List)) CoreColour.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// Piles by status — `draft`, `ready`, `live`, or null for every one of
/// them (the query is simply left off).
final pilesProvider = FutureProvider.autoDispose.family<List<CorePile>, String?>((ref, status) async {
  final data = await ref.watch(coreApiProvider).get(
        '/piles',
        query: status == null ? null : {'status': status},
      );
  return [
    for (final row in (data as List)) CorePile.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// One pile with its Thaans and history.
final pileDetailProvider = FutureProvider.autoDispose.family<CorePile, String>((ref, id) async {
  final data = await ref.watch(coreApiProvider).get('/piles/$id');
  return CorePile.fromJson((data as Map).cast<String, dynamic>());
});

/// Phase 2 — what the complete screen shows for one pile: the details the
/// bale's cloth item already settled, the ones decided at this stage, and
/// what has been picked so far. `GET /piles/:id/draft`.
final pileDraftProvider = FutureProvider.autoDispose.family<CorePileDraft, String>((ref, id) async {
  final data = await ref.watch(coreApiProvider).get('/piles/$id/draft');
  return CorePileDraft.fromJson((data as Map).cast<String, dynamic>());
});

/// What `POST /piles/:id/thaans` did with each Thaan it was given.
class PileAddOutcome {
  const PileAddOutcome({
    required this.message,
    required this.added,
    required this.moved,
    required this.refused,
  });

  final String message;
  final int added;

  /// Taken out of another pile and put in this one.
  final int moved;

  /// Left where they were, each with the server's reason.
  final List<({String code, String why})> refused;

  factory PileAddOutcome.fromJson(Map<String, dynamic> json) {
    final outcome = (json['outcome'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PileAddOutcome(
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

final pileRepositoryProvider = Provider((ref) => PileRepository(ref));

class PileRepository {
  PileRepository(this.ref);
  final Ref ref;

  /// Makes a pile on its own — from Scan a Thaan, where there is no
  /// receive to make it inside. Returns the new pile's id and code.
  Future<({String message, String id, String code})> createPile({
    required String name,
    required String mainColourId,
    String? photoKey,
    String? stage,
  }) async {
    final body = <String, dynamic>{'name': name, 'mainColourId': mainColourId};
    if (photoKey != null) body['photoKey'] = photoKey;
    if (stage != null) body['stage'] = stage;
    final data = await ref.read(coreApiProvider).post('/piles', body: body);
    final map = (data as Map).cast<String, dynamic>();
    final pile = (map['pile'] as Map).cast<String, dynamic>();
    return (
      message: '${map['message'] ?? ''}',
      id: '${pile['id']}',
      code: '${pile['code'] ?? ''}',
    );
  }

  /// Fills in a pile's details — motif, craft, border, colours. Every field
  /// key goes up with its current value (null for "not yet"); the first
  /// save makes the Product Management record, later saves patch it. The
  /// server answers with what is still missing, if anything.
  Future<({String message, String? colourwayId, List<String> needs})> complete(
    String pileId, {
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
    final data = await ref.read(coreApiProvider).post('/piles/$pileId/complete', body: body);
    final map = (data as Map).cast<String, dynamic>();
    return (
      message: '${map['message'] ?? 'Saved'}',
      colourwayId: map['colourwayId'] == null ? null : '${map['colourwayId']}',
      needs: [
        for (final n in (map['needs'] as List? ?? const []))
          if (n != null && '$n'.isNotEmpty) '$n',
      ],
    );
  }

  /// Puts Thaans in a pile — moving any that were in another one. The
  /// server refuses what it can't pile (not back from Print yet, voided)
  /// and says why, per code, in the outcome.
  Future<PileAddOutcome> addThaans(String pileId, List<String> thaanIds, {String? stage}) async {
    final body = <String, dynamic>{'thaanIds': thaanIds};
    if (stage != null) body['stage'] = stage;
    final data = await ref.read(coreApiProvider).post('/piles/$pileId/thaans', body: body);
    return PileAddOutcome.fromJson((data as Map).cast<String, dynamic>());
  }

  /// The pile's photo — presign, PUT the bytes straight to R2, and hand
  /// back the key. Same three-step shape as core_photos.dart, for the same
  /// reasons (the bytes never touch the API; a bare Dio so the session
  /// token never reaches R2).
  ///
  /// With a [pileId], the photo goes on that pile and is confirmed here.
  /// Without one, it's for a pile that doesn't exist yet: the key is what
  /// the receive's `newPile.photoKey` carries, and the server confirms it
  /// when it makes the pile.
  Future<String> uploadPhoto(File file, {String? pileId}) async {
    final api = ref.read(coreApiProvider);
    final bytes = await file.length();
    final contentType = contentTypeOf(file.path);
    final base = pileId == null ? '/piles/new' : '/piles/$pileId';

    final ticket = await api.post(
      '$base/photo/presign',
      body: {'contentType': contentType, 'bytes': bytes},
    );
    final map = (ticket as Map).cast<String, dynamic>();
    final url = map['url'] as String;
    final key = map['key'] as String;

    await Dio().put<void>(
      url,
      data: file.openRead(),
      options: Options(
        headers: {
          'content-type': contentType,
          Headers.contentLengthHeader: bytes,
        },
        validateStatus: (status) => status != null && status >= 200 && status < 300,
        connectTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    if (pileId != null) {
      await api.post('$base/photo/confirm', body: {'key': key});
    }
    return key;
  }
}
