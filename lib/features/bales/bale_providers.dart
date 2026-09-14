import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../core/core_auth.dart';

/// Kora to Shelf, step one: receiving a bale.
///
/// Talks to slk-core the same way the record screens do — `coreApiProvider`,
/// not tantu's default client — because suppliers, cloth items and bales all
/// live on slk-core's own tables, independent of the catalogue. See
/// `packages/db/src/schema/production.ts` there for why.

/// The five types `bale.type` allows — matches slk-core's own
/// `BALE_TYPES` (apps/web/src/app/bales/constants.ts), which a "use server"
/// module cannot export as a plain array for a client to import directly.
const kBaleTypes = <String>['Sarees', 'Fabric', 'Chunnies', 'Bedsheets', 'Pillows'];

/// The two units `bale.uom` allows — slk-core's own `UOMS`.
const kBaleUoms = <String>['Mtrs', 'Nos'];

final coreSuppliersProvider = FutureProvider.autoDispose<List<CoreSupplier>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/suppliers');
  return [
    for (final row in (data as List))
      CoreSupplier.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

final coreClothItemsProvider = FutureProvider.autoDispose<List<CoreClothItem>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/cloth-items');
  return [
    for (final row in (data as List))
      CoreClothItem.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// Every bale on file, unfiltered and newest first — the same table the web
/// page shows. Searched client-side by code so a floor phone can find one
/// bale to record Thaans against without a dedicated search endpoint.
final coreBalesProvider = FutureProvider.autoDispose<List<CoreBale>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/bales');
  return [
    for (final row in (data as List)) CoreBale.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

final baleRepositoryProvider = Provider((ref) => BaleRepository(ref));

class BaleRepository {
  BaleRepository(this.ref);
  final Ref ref;

  /// Logs a bale as received. Returns the confirmation message slk-core
  /// sends back — "Saved as 1234." — which already names the bale's own
  /// code, so there is nothing to compose here.
  Future<String> create({
    required String supplierId,
    required String billEntryDate,
    required String type,
    required String metresReceived,
    required String uom,
    required String itemId,
    String transporter = '',
    String invoiceNumber = '',
    String invoiceDate = '',
    String invoiceAmount = '',
    String baleCount = '1',
    String notes = '',
  }) async {
    final data = await ref.read(coreApiProvider).post('/bales', body: {
      'supplierId': supplierId,
      'billEntryDate': billEntryDate,
      'transporter': transporter,
      'invoiceNumber': invoiceNumber,
      'invoiceDate': invoiceDate,
      'invoiceAmount': invoiceAmount,
      'type': type,
      'metresReceived': metresReceived,
      'uom': uom,
      'itemId': itemId,
      'baleCount': baleCount,
      'notes': notes,
    });
    return (data as Map)['message'] as String;
  }

  /// Records Thaans cut from a bale — as many times as it takes. [key]
  /// must be minted once per attempt and reused across a retry of that same
  /// attempt (see [idempotencyKey]): recording twice on a network hiccup
  /// would mint real, physical Thaans that were never actually cut.
  Future<String> recordThaans({
    required String baleId,
    required String thaanCount,
    required String key,
  }) async {
    final data = await ref.read(coreApiProvider).post(
          '/bales/$baleId/thaans',
          body: {'thaanCount': thaanCount},
          headers: {'Idempotency-Key': key},
        );
    return (data as Map)['message'] as String;
  }

  /// Closes a bale's cutting out — nothing more will be cut from it.
  Future<String> markCuttingComplete(String baleId) async {
    final data = await ref.read(coreApiProvider).post('/bales/$baleId/complete');
    return (data as Map)['message'] as String;
  }
}
