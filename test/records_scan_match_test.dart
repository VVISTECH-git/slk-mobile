import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/records_list_screen.dart';
import 'package:slk_mobile/models/core.dart';

CoreRecordRow row({
  required String id,
  String code = 'SAR-GEN-COT-0001',
  String? productCode,
}) =>
    CoreRecordRow(
      id: id,
      code: code,
      name: 'Kalamkari Cotton Saree',
      productCode: productCode,
      quantity: 2,
      pieces: 2,
      isSerialised: true,
    );

CorePiece piece({
  String itemCode = '500047',
  String designCode = 'SAR-GEN-COT-0001',
  String? productCode = '300018',
}) =>
    CorePiece(
      id: itemCode,
      itemCode: itemCode,
      designCode: designCode,
      name: 'Kalamkari Cotton Saree',
      isHeld: true,
      productCode: productCode,
    );

void main() {
  group('matchingRowForPiece', () {
    test('finds the row whose newest consignment is the scanned one', () {
      final rows = [
        row(id: 'a', productCode: '300017'),
        row(id: 'b', productCode: '300018'),
      ];

      expect(matchingRowForPiece(rows, piece(productCode: '300018'))?.id, 'b');
    });

    test(
      'REGRESSION: an older consignment of a row does not falsely match another row',
      () {
        // The row only remembers its newest product code — a piece from an
        // earlier delivery of the same colourway has a product code no row
        // currently carries. This must return null, not the wrong row.
        final rows = [
          row(id: 'a', productCode: '300017'),
          row(id: 'b', productCode: '300020'),
        ];

        expect(matchingRowForPiece(rows, piece(productCode: '300018')), isNull);
      },
    );

    test('null product code on a row is never treated as a match', () {
      final rows = [row(id: 'a', productCode: null)];

      expect(matchingRowForPiece(rows, piece(productCode: null)), isNull);
    });
  });

  group('fallbackSearchFor', () {
    test('prefers the product code — what is on the paperwork', () {
      expect(
        fallbackSearchFor(piece(productCode: '300018', designCode: 'SAR-GEN-COT-0001')),
        '300018',
      );
    });

    test('falls back to the design code when there is no consignment yet', () {
      expect(
        fallbackSearchFor(piece(productCode: null, designCode: 'SAR-GEN-COT-0001')),
        'SAR-GEN-COT-0001',
      );
    });
  });
}
