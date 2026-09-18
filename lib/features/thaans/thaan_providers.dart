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
}
