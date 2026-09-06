import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/product.dart';
import '../../models/transfer.dart';

final transfersProvider = FutureProvider.autoDispose<List<TransferListRow>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/transfers');
  return (data as List)
      .map((e) => TransferListRow.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

final transferDetailProvider =
    FutureProvider.autoDispose.family<TransferDetail, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/transfers/$id');
  return TransferDetail.fromJson((data as Map).cast<String, dynamic>());
});

final transferLocationsProvider = FutureProvider.autoDispose<List<NamedLocation>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/transfers/locations');
  return (data as List)
      .map((e) => NamedLocation.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

final variantsAtLocationProvider =
    FutureProvider.autoDispose.family<List<TransferVariant>, String>((ref, locationId) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/transfers/at/$locationId');
  return (data as List)
      .map((e) => TransferVariant.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

final transferRepositoryProvider = Provider((ref) => TransferRepository(ref));

class TransferRepository {
  TransferRepository(this.ref);
  final Ref ref;

  Future<String> create({
    required String fromLocationId,
    required String toLocationId,
    required List<({String variantId, int quantity})> items,
    String? note,
  }) async {
    final data = await ref.read(apiClientProvider).post('/transfers', body: {
      'fromLocationId': fromLocationId,
      'toLocationId': toLocationId,
      'items': [for (final i in items) {'variantId': i.variantId, 'quantity': i.quantity}],
      'note': ?note,
    });
    return (data as Map)['id'] as String;
  }

  Future<void> receive(
    String id,
    List<({String itemId, int quantity, String? reason, String? note})> received,
  ) async {
    await ref.read(apiClientProvider).post('/transfers/$id/receive', body: {
      'received': [
        for (final r in received)
          {
            'itemId': r.itemId,
            'quantity': r.quantity,
            if (r.reason != null) 'reason': r.reason,
            if (r.note != null && r.note!.isNotEmpty) 'note': r.note,
          }
      ],
    });
  }

  Future<void> cancel(String id) async {
    await ref.read(apiClientProvider).post('/transfers/$id/cancel');
  }
}
