import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Full settings payload (owner-only): business profile, staff, categories,
/// locations, attributes.
final settingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/settings');
  return (data as Map).cast<String, dynamic>();
});

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref));

/// Photo-guide slots for one category (owner editor + product form both read this).
final categoryPhotoSlotsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, categoryId) async {
  return ref.watch(settingsRepositoryProvider).photoSlots(categoryId);
});

class SettingsRepository {
  SettingsRepository(this.ref);
  final Ref ref;

  Future<void> saveBusiness(Map<String, String> profile) async {
    await ref.read(apiClientProvider).put('/settings/business', body: profile);
  }

  // ---- staff ----
  Future<void> addStaff({required String name, required String pin, String? storeId, required String role}) async {
    await ref.read(apiClientProvider).post('/settings/staff', body: {
      'name': name,
      'pin': pin,
      'storeId': ?storeId,
      'role': role,
    });
  }

  Future<void> updateStaff(String id, {required String name, String? storeId, required String role, String? pin}) async {
    await ref.read(apiClientProvider).patch('/settings/staff/$id', body: {
      'name': name,
      'storeId': ?storeId,
      'role': role,
      if (pin != null && pin.isNotEmpty) 'pin': pin,
    });
  }

  Future<void> deleteStaff(String id) async {
    await ref.read(apiClientProvider).delete('/settings/staff/$id');
  }

  // ---- locations ----
  Future<void> addLocation(String name, String type) async {
    await ref.read(apiClientProvider).post('/settings/locations', body: {'name': name, 'type': type});
  }

  Future<void> deleteLocation(String id) async {
    await ref.read(apiClientProvider).delete('/settings/locations/$id');
  }

  // ---- categories ----
  Future<void> addCategory(String name, String? parentId) async {
    await ref.read(apiClientProvider).post('/settings/categories', body: {
      'name': name,
      'parentId': ?parentId,
    });
  }

  Future<void> updateCategory(String id, {String? name, String? code}) async {
    await ref.read(apiClientProvider).patch('/settings/categories/$id', body: {
      'name': ?name,
      'code': ?code,
    });
  }

  Future<void> deleteCategory(String id) async {
    await ref.read(apiClientProvider).delete('/settings/categories/$id');
  }

  // ---- category photo guides (shot templates) ----
  Future<List<Map<String, dynamic>>> photoSlots(String categoryId) async {
    final data = await ref.read(apiClientProvider).get('/categories/$categoryId/photo-slots');
    return ((data as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> savePhotoSlot({
    String? id,
    required String categoryId,
    required String label,
    String? guide, // base64; pass '' to clear, null to leave unchanged
    required bool required,
    required int position,
  }) async {
    final body = {
      'label': label,
      'required': required,
      'position': position,
      'guide': ?guide,
    };
    if (id == null) {
      await ref.read(apiClientProvider).post('/categories/$categoryId/photo-slots', body: body);
    } else {
      await ref.read(apiClientProvider).patch('/photo-slots/$id', body: body);
    }
  }

  Future<void> deletePhotoSlot(String id) async {
    await ref.read(apiClientProvider).delete('/photo-slots/$id');
  }

  // ---- attributes (fabric | technique | dye | border) ----
  Future<void> addAttribute(String kind, String name) async {
    await ref.read(apiClientProvider).post('/settings/attributes/$kind', body: {'name': name});
  }

  Future<void> deleteAttribute(String kind, String id) async {
    await ref.read(apiClientProvider).delete('/settings/attributes/$kind/$id');
  }
}
