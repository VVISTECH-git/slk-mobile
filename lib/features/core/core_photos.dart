import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'core_auth.dart';

/// Getting a photograph from the phone into R2 and onto a record.
///
/// Three steps, and the split matters:
///
///   1. **presign** — ask slk-core for a signed URL for this record and slot
///   2. **PUT** — send the bytes straight to R2, not through slk-core
///   3. **confirm** — tell slk-core the file landed
///
/// The bytes never touch the API. A saree photograph is 3-6MB and routing it
/// through a serverless function would pay for every megabyte twice, inbound
/// and outbound, for no benefit — the server has nothing to say about pixels.
///
/// Confirming is separate from presigning because step 2 happens on a network
/// that drops. A row written at presign time would mark a slot photographed
/// for a file that never arrived, and every screen would believe it.

/// Whether uploading can work at all, and what is missing if not.
class StorageState {
  const StorageState({required this.ready, required this.missing});

  final bool ready;
  final List<String> missing;

  factory StorageState.fromJson(Map<String, dynamic> json) => StorageState(
        ready: json['ready'] == true,
        missing: [
          for (final m in (json['missing'] as List? ?? const [])) '$m',
        ],
      );
}

/// Asked before the camera opens rather than after.
///
/// Letting somebody photograph six slots of a saree and only then discovering
/// the bucket was never configured is how a person stops trusting a screen —
/// and on a floor they will not go back and do it again.
final coreStorageProvider = FutureProvider<StorageState>((ref) async {
  final data = await ref.read(coreApiProvider).get('/storage');
  return StorageState.fromJson((data as Map).cast<String, dynamic>());
});

/// What a phone camera produces, and what the API will sign for.
String contentTypeOf(String path) {
  final lower = path.toLowerCase();

  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.avif')) return 'image/avif';

  return 'image/jpeg';
}

class CorePhotos {
  CorePhotos(this._api);

  final ApiClient _api;

  /// Put one photograph in one slot.
  ///
  /// Throws [ApiException] with a message meant to be shown as-is; the API
  /// writes its refusals for whoever is holding the phone.
  Future<void> upload({
    required String recordId,
    required String slotId,
    required File file,
  }) async {
    final bytes = await file.length();
    final contentType = contentTypeOf(file.path);

    final ticket = await _api.post(
      '/records/$recordId/images/presign',
      body: {'slotId': slotId, 'contentType': contentType, 'bytes': bytes},
    );

    final map = (ticket as Map).cast<String, dynamic>();
    final url = map['url'] as String;
    final key = map['key'] as String;

    /*
      A bare Dio, deliberately.

      The app's client attaches an slk-core bearer token to everything it
      sends. R2 must not receive it: the signature in the URL is the whole
      authorisation, and posting a session token to a third party is how
      credentials leak into somebody else's logs.
    */
    await Dio().put<void>(
      url,
      data: file.openRead(),
      options: Options(
        headers: {
          'content-type': contentType,
          Headers.contentLengthHeader: bytes,
        },
        // The signed URL is not the API, so the envelope rules do not apply.
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );

    /*
      Width and height are not sent.

      Reading them means decoding the whole JPEG — a 6MB photograph becomes
      about 36MB in memory — and the columns are nullable because they
      describe the file rather than being part of it. A picture with no
      dimensions recorded is still a picture. Worth revisiting if a storefront
      needs them, with a header-only decoder rather than a full one.
    */
    await _api.post(
      '/records/$recordId/images/confirm',
      body: {'slotId': slotId, 'key': key},
    );
  }

  /// Take the photograph off, leaving the slot wanted.
  Future<void> remove({
    required String recordId,
    required String slotId,
  }) =>
      _api.delete('/records/$recordId/images/$slotId');
}

final corePhotosProvider = Provider<CorePhotos>(
  (ref) => CorePhotos(ref.read(coreApiProvider)),
);
