import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../core/core_auth.dart';

final thaanRepositoryProvider = Provider((ref) => ThaanRepository(ref));

class ThaanRepository {
  ThaanRepository(this.ref);
  final Ref ref;

  /// The Thaan a scanned QR code names — same row slk-core's own Thaans
  /// table shows, narrowed to one code.
  Future<CoreThaan> lookupByCode(String code) async {
    final data = await ref.read(coreApiProvider).get('/thaans/lookup', query: {'code': code});
    return CoreThaan.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Flags a Thaan damaged — [vendorId] overrides the auto-derived one
  /// (`CoreThaan.lastVendorId`) when the scanner corrects it; pass it back
  /// unchanged to keep the derived vendor. Returns the confirmation message.
  Future<String> flagDamaged({required String code, String? vendorId, String notes = ''}) async {
    final data = await ref.read(coreApiProvider).post('/thaans/flag-damaged', body: {
      'code': code,
      'vendorId': vendorId,
      'notes': notes,
    });
    return (data as Map)['message'] as String;
  }
}
