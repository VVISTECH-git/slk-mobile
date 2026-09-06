import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

// ---- Reads (map-based, like settings/dashboard) ----

final prodStagesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return (await ref.watch(apiClientProvider).get('/production/stages')) as List;
});

final prodVendorsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return (await ref.watch(apiClientProvider).get('/production/vendors')) as List;
});

final batchesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return (await ref.watch(apiClientProvider).get('/production/batches')) as List;
});

final batchDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/production/batches/$id');
  return (data as Map).cast<String, dynamic>();
});

/// The reconciliation board — open/partial challans with pending counts + aging.
final jobBoardProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return (await ref.watch(apiClientProvider).get('/production/reconciliation')) as List;
});

final jobOrderProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/production/orders/$id');
  return (data as Map).cast<String, dynamic>();
});

/// All product variants — the picker for turning finished pieces into stock.
final finishVariantsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return (await ref.watch(apiClientProvider).get('/production/variants')) as List;
});

// ---- Writes ----

final productionRepositoryProvider = Provider((ref) => ProductionRepository(ref));

class ProductionRepository {
  ProductionRepository(this.ref);
  final Ref ref;

  Future<Map<String, dynamic>> createBatch({
    required String material,
    double? lengthMeters,
    String? supplier,
    double? cost,
    String? note,
  }) async {
    final data = await ref.read(apiClientProvider).post('/production/batches', body: {
      'material': material,
      'lengthMeters': ?lengthMeters,
      if (supplier != null && supplier.isNotEmpty) 'supplier': supplier,
      'cost': ?cost,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return (data as Map).cast<String, dynamic>();
  }

  /// Cut a batch into serialized pieces. Returns the created tag codes.
  Future<List<String>> cutAndTag(String batchId, List<({String size, int quantity})> cuts) async {
    final data = await ref.read(apiClientProvider).post('/production/batches/$batchId/cut', body: {
      'cuts': [for (final c in cuts) {'size': c.size, 'quantity': c.quantity}],
    });
    final created = ((data as Map)['created'] as List? ?? []);
    return [for (final c in created) (c as Map)['tagCode'] as String];
  }

  /// Dispatch scanned pieces to a vendor for a stage. Returns the challan info
  /// including any skipped tags (unknown / already out).
  Future<Map<String, dynamic>> dispatch({
    required String vendorId,
    required String stageId,
    required List<String> tagCodes,
    String? note,
  }) async {
    final data = await ref.read(apiClientProvider).post('/production/dispatch', body: {
      'vendorId': vendorId,
      'stageId': stageId,
      'tagCodes': tagCodes,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return (data as Map).cast<String, dynamic>();
  }

  /// Receive scanned pieces against a challan (partial supported).
  Future<Map<String, dynamic>> receive(String jobOrderId, List<String> tagCodes, {String? note}) async {
    final data = await ref.read(apiClientProvider).post('/production/orders/$jobOrderId/receive', body: {
      'tagCodes': tagCodes,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return (data as Map).cast<String, dynamic>();
  }

  /// Finish scanned pieces into sellable warehouse stock for a variant.
  Future<Map<String, dynamic>> finishPieces({
    required List<String> tagCodes,
    required String variantId,
    double? unitCost,
  }) async {
    final data = await ref.read(apiClientProvider).post('/production/finish', body: {
      'tagCodes': tagCodes,
      'variantId': variantId,
      'unitCost': ?unitCost,
    });
    return (data as Map).cast<String, dynamic>();
  }

  /// Re-tag a piece (bind a fresh tag code to an outstanding piece).
  Future<void> retagPiece(String pieceId, String newTag) async {
    await ref.read(apiClientProvider).post('/production/pieces/$pieceId/retag', body: {'newTag': newTag});
  }

  Future<Map<String, dynamic>> lookupPiece(String tag) async {
    final data = await ref.read(apiClientProvider).get('/production/pieces/$tag');
    return (data as Map).cast<String, dynamic>();
  }

  // ---- Vendors & stages (owner config) ----

  Future<void> saveVendor({String? id, required String name, String? phone, String? address}) async {
    final api = ref.read(apiClientProvider);
    final body = {'name': name, 'phone': ?phone, 'address': ?address};
    if (id == null) {
      await api.post('/production/vendors', body: body);
    } else {
      await api.patch('/production/vendors/$id', body: body);
    }
  }

  Future<void> deleteVendor(String id) => ref.read(apiClientProvider).delete('/production/vendors/$id');

  Future<void> saveStage({String? id, required String name, int sequence = 0}) async {
    final api = ref.read(apiClientProvider);
    final body = {'name': name, 'sequence': sequence};
    if (id == null) {
      await api.post('/production/stages', body: body);
    } else {
      await api.patch('/production/stages/$id', body: body);
    }
  }

  Future<void> deleteStage(String id) => ref.read(apiClientProvider).delete('/production/stages/$id');
}
