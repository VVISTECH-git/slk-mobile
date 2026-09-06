import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/pos.dart';

/// Sellable variants (priced + in stock) at the signed-in cashier's store.
final sellableProvider = FutureProvider.autoDispose<List<SellableVariant>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/pos/products');
  return (data as List)
      .map((e) => SellableVariant.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

/// Every variant (price/stock/store-agnostic) — for goods-in / receiving, where
/// you tag stock even before a price exists.
final goodsInVariantsProvider = FutureProvider.autoDispose<List<SellableVariant>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.get('/variants');
  return (data as List)
      .map((e) => SellableVariant.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

/// The working cart. Keyed by variant id; quantity is clamped to available stock.
class CartController extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => [];

  int qtyOf(String variantId) =>
      state.where((l) => l.variant.id == variantId).firstOrNull?.quantity ?? 0;

  void add(SellableVariant v, {int by = 1}) {
    final existing = state.where((l) => l.variant.id == v.id).firstOrNull;
    final next = (existing?.quantity ?? 0) + by;
    setQty(v, next);
  }

  void setQty(SellableVariant v, int qty) {
    final clamped = qty.clamp(0, v.stock);
    if (clamped <= 0) {
      state = state.where((l) => l.variant.id != v.id).toList();
      return;
    }
    final found = state.any((l) => l.variant.id == v.id);
    if (found) {
      state = [
        for (final l in state)
          if (l.variant.id == v.id) l.copyWith(quantity: clamped) else l
      ];
    } else {
      state = [...state, CartLine(variant: v, quantity: clamped)];
    }
  }

  void remove(String variantId) =>
      state = state.where((l) => l.variant.id != variantId).toList();

  void clear() => state = [];

  int get totalUnits => state.fold(0, (s, l) => s + l.quantity);
  double get subtotal => state.fold(0.0, (s, l) => s + l.gross);
}

final cartProvider = NotifierProvider<CartController, List<CartLine>>(CartController.new);

/// Sales channel for the current sale: false = retail, true = wholesale (B2B).
final wholesaleProvider = StateProvider<bool>((ref) => false);

/// Result of completing a sale.
class SaleResult {
  const SaleResult({required this.invoiceId, required this.invoiceNumber});
  final String invoiceId;
  final String invoiceNumber;
}

/// POS write operations.
final posRepositoryProvider = Provider((ref) => PosRepository(ref));

class PosRepository {
  PosRepository(this.ref);
  final Ref ref;

  Future<SaleResult> createInvoice({
    required List<CartLine> cart,
    required String paymentMode,
    double discount = 0,
    Map<String, String?>? customer,
    String? note,
    String channel = 'retail',
  }) async {
    final api = ref.read(apiClientProvider);
    final data = await api.post('/pos/invoices', body: {
      'items': [
        for (final l in cart) {'variantId': l.variant.id, 'quantity': l.quantity}
      ],
      'paymentMode': paymentMode,
      'discount': discount,
      'channel': channel,
      'customer': ?customer,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    final map = (data as Map).cast<String, dynamic>();
    return SaleResult(
      invoiceId: map['invoiceId'] as String,
      invoiceNumber: map['invoiceNumber'] as String,
    );
  }
}
