import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/stock.dart';

/// Variants with per-location stock + the location columns.
final stockProvider = FutureProvider.autoDispose<StockData>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/stock');
  return StockData.fromJson((data as Map).cast<String, dynamic>());
});

/// The stock-movement audit ledger (newest first).
final movementsProvider = FutureProvider.autoDispose<List<MovementRow>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/stock/movements');
  return (data as List)
      .map((e) => MovementRow.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

final stockRepositoryProvider = Provider((ref) => StockRepository(ref));

class StockRepository {
  StockRepository(this.ref);
  final Ref ref;

  Future<void> receive({
    required String variantId,
    required String locationId,
    required int quantity,
    String? reference,
    String? note,
  }) async {
    await ref.read(apiClientProvider).post('/stock/receive', body: {
      'variantId': variantId,
      'locationId': locationId,
      'quantity': quantity,
      'reference': ?reference,
      'note': ?note,
    });
  }

  Future<void> adjust({
    required String variantId,
    required String locationId,
    required int delta,
    String? note,
  }) async {
    await ref.read(apiClientProvider).post('/stock/adjust', body: {
      'variantId': variantId,
      'locationId': locationId,
      'delta': delta,
      'note': ?note,
    });
  }

  Future<void> transfer({
    required String variantId,
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
    String? note,
  }) async {
    await ref.read(apiClientProvider).post('/stock/transfer', body: {
      'variantId': variantId,
      'fromLocationId': fromLocationId,
      'toLocationId': toLocationId,
      'quantity': quantity,
      'note': ?note,
    });
  }
}
