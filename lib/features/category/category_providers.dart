import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// When set, the Category module is scoped to this top-level category and its
/// sub-categories only (e.g. 'Sarees'). Set to `null` to show every category.
/// Single switch so the scope is trivially reversible.
// ignore: unnecessary_nullable_for_final_variable_declarations
// No forced focus — the catalogue shows all top-level groups (Sarees, Fabric…)
// and new groups/sub-groups/designs can be created at any level.
const String? kCategoryFocus = null;

/// One row of the Category list (`GET /categories/full`) — a (sub-)category plus
/// its template attributes (resolved to names) and how many products use it.
class CategoryRow {
  const CategoryRow({
    required this.id,
    required this.name,
    required this.productCount,
    this.pieceCount = 0,
    this.colourCount = 0,
    this.coloursWithPhotos = 0,
    required this.status,
    this.code,
    this.ownCode,
    this.parentId,
    this.parentName,
    this.fabricId,
    this.techniqueId,
    this.dyeTypeId,
    this.borderStyleId,
    this.fabric,
    this.technique,
    this.dyeType,
    this.borderStyle,
    this.unitType,
    this.hsnCode,
    this.gstRate,
    this.costPrice,
    this.b2cPrice,
    this.b2bPrice,
  });

  final String id;
  final String name;
  final int productCount;
  final int pieceCount;
  final int colourCount;
  final int coloursWithPhotos;
  final String status;

  /// A tagged design where at least one colour variant has no captured photos.
  bool get missingPhotos => colourCount > 0 && coloursWithPhotos < colourCount;
  final String? code;
  final String? ownCode;
  final String? parentId;
  final String? parentName;
  final String? fabricId;
  final String? techniqueId;
  final String? dyeTypeId;
  final String? borderStyleId;
  final String? fabric;
  final String? technique;
  final String? dyeType;
  final String? borderStyle;
  final String? unitType;
  final String? hsnCode;
  final String? gstRate;
  final String? costPrice;
  final String? b2cPrice;
  final String? b2bPrice;

  factory CategoryRow.fromJson(Map<String, dynamic> j) => CategoryRow(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        productCount: (j['productCount'] as num?)?.toInt() ?? 0,
        pieceCount: (j['pieceCount'] as num?)?.toInt() ?? 0,
        colourCount: (j['colourCount'] as num?)?.toInt() ?? 0,
        coloursWithPhotos: (j['coloursWithPhotos'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? 'active') as String,
        code: j['code'] as String?,
        ownCode: j['ownCode'] as String?,
        parentId: j['parentId'] as String?,
        parentName: j['parentName'] as String?,
        fabricId: j['fabricId'] as String?,
        techniqueId: j['techniqueId'] as String?,
        dyeTypeId: j['dyeTypeId'] as String?,
        borderStyleId: j['borderStyleId'] as String?,
        fabric: j['fabric'] as String?,
        technique: j['technique'] as String?,
        dyeType: j['dyeType'] as String?,
        borderStyle: j['borderStyle'] as String?,
        unitType: j['unitType'] as String?,
        hsnCode: j['hsnCode'] as String?,
        gstRate: j['gstRate']?.toString(),
        costPrice: j['costPrice']?.toString(),
        b2cPrice: j['b2cPrice']?.toString(),
        b2bPrice: j['b2bPrice']?.toString(),
      );
}

/// A named lookup value (fabric / technique / dye / border / category).
class NamedRef {
  const NamedRef(this.id, this.name, {this.parentId});
  final String id;
  final String name;
  final String? parentId;

  factory NamedRef.fromJson(Map<String, dynamic> j) =>
      NamedRef(j['id'] as String, (j['name'] ?? '') as String, parentId: j['parentId'] as String?);
}

/// Dropdown data for the Category form (`GET /products/lookups`).
class CategoryLookups {
  const CategoryLookups({
    required this.categories,
    required this.fabrics,
    required this.techniques,
    required this.dyeTypes,
    required this.borderStyles,
  });

  final List<NamedRef> categories;
  final List<NamedRef> fabrics;
  final List<NamedRef> techniques;
  final List<NamedRef> dyeTypes;
  final List<NamedRef> borderStyles;

  /// Only top-level categories (no parent) — candidate parents for a new one.
  List<NamedRef> get topCategories => categories.where((c) => c.parentId == null).toList();

  static List<NamedRef> _list(dynamic v) =>
      ((v as List?) ?? []).map((e) => NamedRef.fromJson((e as Map).cast<String, dynamic>())).toList();

  factory CategoryLookups.fromJson(Map<String, dynamic> j) => CategoryLookups(
        categories: _list(j['categories']),
        fabrics: _list(j['fabrics']),
        techniques: _list(j['techniques']),
        dyeTypes: _list(j['dyeTypes']),
        borderStyles: _list(j['borderStyles']),
      );
}

/// The category list with template attributes + product counts.
final categoriesProvider = FutureProvider.autoDispose<List<CategoryRow>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/categories/full');
  return ((data as List?) ?? [])
      .map((e) => CategoryRow.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

/// Dropdown data shared by the form.
final categoryLookupsProvider = FutureProvider.autoDispose<CategoryLookups>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/products/lookups');
  return CategoryLookups.fromJson((data as Map).cast<String, dynamic>());
});

/// Category write operations (owner-only on the server).
final categoryRepositoryProvider = Provider((ref) => CategoryRepository(ref));

class CategoryRepository {
  CategoryRepository(this.ref);
  final Ref ref;

  Future<String> create(Map<String, dynamic> input) async {
    final data = await ref.read(apiClientProvider).post('/settings/categories', body: input);
    return ((data as Map?)?['id'] ?? '') as String;
  }

  Future<void> update(String id, Map<String, dynamic> input) async {
    await ref.read(apiClientProvider).patch('/settings/categories/$id', body: input);
  }

  Future<void> delete(String id) async {
    await ref.read(apiClientProvider).delete('/settings/categories/$id');
  }

  /// Colours defined on a design (with per-colour prices + piece counts).
  Future<List<Map<String, dynamic>>> getColours(String id) async {
    final data = await ref.read(apiClientProvider).get('/categories/$id/colours');
    return ((data as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Replace the design's colour set (create/update/remove).
  Future<void> saveColours(String id, List<Map<String, dynamic>> colours) async {
    await ref.read(apiClientProvider).put('/categories/$id/colours', body: {'colours': colours});
  }
}
