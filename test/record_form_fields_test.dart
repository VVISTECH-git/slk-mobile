import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/record_form_fields.dart';

void main() {
  group('tabErrorCounts', () {
    test('groups fieldErrors keys onto their owning tab', () {
      final counts = tabErrorCounts({
        'colour': 'A primary colour is needed',
        'retail': 'A selling price is needed',
        'mrp': 'An MRP is needed',
        'openingStock': 'At least one location needs a quantity greater than zero.',
      });

      expect(counts, {1: 1, 3: 2, 5: 1});
    });

    test('no errors means no tab carries a badge', () {
      expect(tabErrorCounts(const {}), isEmpty);
    });

    test('a key with no known tab is dropped rather than crashing', () {
      // Guards against a future fieldErrors key that fieldErrorTabIndex
      // hasn't been taught about yet — silently ignored, not a thrown error.
      final counts = tabErrorCounts({'somethingNew': 'unmapped'});

      expect(counts, isEmpty);
    });

    test('every price key and quantity share the tabs the form actually has',
        () {
      // Pins the mapping itself, not just the grouping logic above — a typo
      // here would misroute every tap-to-jump silently.
      expect(fieldErrorTabIndex['industry'], 0);
      expect(fieldErrorTabIndex['productType'], 0);
      expect(fieldErrorTabIndex['homeProductType'], 0);
      expect(fieldErrorTabIndex['garmentType'], 0);
      expect(fieldErrorTabIndex['fibreType'], 0);
      expect(fieldErrorTabIndex['colour'], 1);
      expect(fieldErrorTabIndex['craftTechnique'], 1);
      for (final key in ['cost', 'making', 'wholesale', 'retail', 'mrp']) {
        expect(fieldErrorTabIndex[key], 3, reason: '$key belongs on Prices');
      }
      // Named for the server's own validation key (records/actions.ts),
      // not the field's local name — a mismatch here is exactly the bug
      // that shipped once already (silently no-op badge, clear and jump).
      expect(fieldErrorTabIndex['openingStock'], 5);
    });
  });
}
