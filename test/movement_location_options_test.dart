import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/record_detail_screen.dart';
import 'package:slk_mobile/models/core.dart';

CoreLocation loc(String id, String name) =>
    CoreLocation(id: id, code: id.toUpperCase(), name: name, isInternal: true);

CoreStockAtLocation held(String location, int qty) =>
    CoreStockAtLocation(location: location, qty: qty);

void main() {
  group('movementDirOf', () {
    test('received and returned are "in"', () {
      expect(movementDirOf('received'), 'in');
      expect(movementDirOf('returned'), 'in');
    });

    test('sold, damaged and transferred are "out"', () {
      expect(movementDirOf('sold'), 'out');
      expect(movementDirOf('damaged'), 'out');
      expect(movementDirOf('transferred'), 'out');
    });
  });

  group('movementLocationOptions', () {
    final warehouse = loc('a', 'Warehouse');
    final shop = loc('b', 'Retail Unit 1');
    final internal = [warehouse, shop];

    test('an "in" movement offers every internal location, unfiltered', () {
      expect(
        movementLocationOptions(kind: 'received', internal: internal, byLocation: const []),
        internal,
      );
    });

    test('an "out" movement narrows to locations the ledger says hold something', () {
      final byLocation = [held('Warehouse', 5), held('Retail Unit 1', 0)];

      expect(
        movementLocationOptions(kind: 'sold', internal: internal, byLocation: byLocation),
        [warehouse],
      );
    });

    test(
      'REGRESSION: a stale or empty stock summary never leaves the field with nothing to choose',
      () {
        // Neither location shows as holding anything — narrowing would empty
        // the list entirely, which is worse than the unfiltered one.
        expect(
          movementLocationOptions(kind: 'transferred', internal: internal, byLocation: const []),
          internal,
        );
      },
    );
  });
}
