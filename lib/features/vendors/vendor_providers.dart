import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';

/// Finance Manager's own vendor billing screens — pricing, approving and
/// paying vendor work, and settling damaged Thaans per vendor. Talks to the
/// REST surface `/api/v1/vendors/*`, which wraps slk-core's own Server
/// Actions (apps/web/src/app/vendors/actions.ts) — see that file for the
/// business logic, which lives there once rather than twice.

/// Every vendor with what's owed and what's been paid — the list screen.
final coreVendorsFinanceProvider = FutureProvider.autoDispose<List<CoreVendorFinance>>((ref) async {
  final data = await ref.watch(coreApiProvider).get('/vendors/finance');
  return [
    for (final row in (data as List)) CoreVendorFinance.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// One vendor's own billing history, newest first — the detail screen.
/// Re-fetched (via `ref.invalidate`) after any action that changes it.
final vendorLedgerProvider = FutureProvider.autoDispose.family<List<CoreVendorLedgerEntry>, String>(
  (ref, vendorId) => ref.watch(vendorRepositoryProvider).ledger(vendorId),
);

/// Every Thaan ever flagged damaged against this vendor — the detail screen.
final vendorDamagedProvider = FutureProvider.autoDispose.family<List<CoreDamagedThaan>, String>(
  (ref, vendorId) => ref.watch(vendorRepositoryProvider).damagedThaans(vendorId),
);

final vendorRepositoryProvider = Provider((ref) => VendorRepository(ref));

class VendorRepository {
  VendorRepository(this.ref);
  final Ref ref;

  /// One vendor's own billing history, newest first.
  Future<List<CoreVendorLedgerEntry>> ledger(String vendorId) async {
    final data = await ref.read(coreApiProvider).get('/vendors/$vendorId/ledger');
    return [
      for (final row in (data as List)) CoreVendorLedgerEntry.fromJson((row as Map).cast<String, dynamic>()),
    ];
  }

  /// Every Thaan ever flagged damaged against this vendor.
  Future<List<CoreDamagedThaan>> damagedThaans(String vendorId) async {
    final data = await ref.read(coreApiProvider).get('/vendors/$vendorId/damaged');
    return [
      for (final row in (data as List)) CoreDamagedThaan.fromJson((row as Map).cast<String, dynamic>()),
    ];
  }

  /// Prices a set of previously-unpriced transactions at one rate per
  /// piece — all must share one vendor and stage (checked again
  /// server-side). Returns the confirmation message.
  Future<String> priceTransactions({required List<String> transactionIds, required double unitPrice}) async {
    final data = await ref.read(coreApiProvider).post('/vendors/price', body: {
      'transactionIds': transactionIds,
      'unitPrice': unitPrice,
    });
    return (data as Map)['message'] as String;
  }

  /// Finance's sign-off on a set of transactions, before any of them can be paid.
  Future<String> approveTransactions(List<String> transactionIds) async {
    final data = await ref.read(coreApiProvider).post('/vendors/approve', body: {
      'transactionIds': transactionIds,
    });
    return (data as Map)['message'] as String;
  }

  /// Settles a set of approved, unpaid transactions for one vendor in a
  /// single payment.
  Future<String> payTransactions({
    required String vendorId,
    required List<String> transactionIds,
    required String paidOn,
    String method = '',
    String notes = '',
  }) async {
    final data = await ref.read(coreApiProvider).post('/vendors/pay', body: {
      'vendorId': vendorId,
      'transactionIds': transactionIds,
      'paidOn': paidOn,
      'method': method,
      'notes': notes,
    });
    return (data as Map)['message'] as String;
  }

  /// Money paid against this vendor's running balance, not tied to any
  /// particular transaction — for an advance or an adjustment.
  ///
  /// [key] is one [idempotencyKey] per save attempt, reused on retry, so a
  /// payment can't be recorded twice by a tap that lost its response.
  Future<String> recordPayment({
    required String vendorId,
    required String amount,
    required String paidOn,
    required String key,
    String method = '',
    String notes = '',
  }) async {
    final data = await ref.read(coreApiProvider).post(
      '/vendors/record-payment',
      body: {
        'vendorId': vendorId,
        'amount': amount,
        'paidOn': paidOn,
        'method': method,
        'notes': notes,
      },
      headers: {'Idempotency-Key': key},
    );
    return (data as Map)['message'] as String;
  }

  /// Finance's review of one damaged Thaan, during that vendor's settlement.
  Future<String> addressDamaged(String damageId) async {
    final data = await ref.read(coreApiProvider).post('/vendors/damaged/address', body: {'damageId': damageId});
    return (data as Map)['message'] as String;
  }

  /// Retires an already-addressed damaged Thaan for good.
  Future<String> writeOffDamaged(String damageId) async {
    final data = await ref.read(coreApiProvider).post('/vendors/damaged/write-off', body: {'damageId': damageId});
    return (data as Map)['message'] as String;
  }
}
