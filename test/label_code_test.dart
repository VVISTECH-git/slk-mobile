import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/records_list_screen.dart';

void main() {
  group('looksLikeLabelCode', () {
    test('an item code or a product code off a label', () {
      expect(looksLikeLabelCode('500066'), isTrue);
      expect(looksLikeLabelCode('300032'), isTrue);
      expect(looksLikeLabelCode('  562764 '), isTrue);
    });

    test('a word, a design code or a partial number is a plain search', () {
      // These the phone-side filter can answer itself; only a full label
      // number needs the scan-style lookup.
      expect(looksLikeLabelCode('beige'), isFalse);
      expect(looksLikeLabelCode('SAR-GEN-COT-0001'), isFalse);
      expect(looksLikeLabelCode('3000'), isFalse);
      expect(looksLikeLabelCode('3000321'), isFalse);
      expect(looksLikeLabelCode(''), isFalse);
    });
  });
}
