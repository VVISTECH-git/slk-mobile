import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/record_fields.dart';
import 'package:slk_mobile/features/core/record_form_fields.dart';
import 'package:slk_mobile/models/core.dart';

CoreOption _opt(String id, String label, {String? parent}) =>
    CoreOption(id: id, label: label, parentId: parent);

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
      // The edit screen's own stock correction — a different server key
      // from create's opening count, on the same tab.
      expect(fieldErrorTabIndex['quantity'], 5);
    });
  });

  group('firstErrorKey', () {
    test('nothing to jump to when there are no errors', () {
      expect(firstErrorKey(const {}), isNull);
    });

    test('picks the error whose tab reads earliest, not the server\'s order',
        () {
      // Prices (tab 3) listed before Basic (tab 0) in the map — the jump
      // should still land on Basic first, because that is what somebody
      // filling the form in order would hit first.
      final key = firstErrorKey({
        'retail': 'A selling price is needed',
        'industry': 'Industry is needed',
      });

      expect(key, 'industry');
    });

    test('a key with no known tab never wins over one that has a home', () {
      final key = firstErrorKey({
        'somethingNew': 'unmapped',
        'colour': 'A primary colour is needed',
      });

      expect(key, 'colour');
    });
  });

  group('composeDesignNamePreview', () {
    final options = <String, List<CoreOption>>{
      'descriptor': [_opt('soft', 'soft'), _opt('pure', 'pure')],
      'craft_technique': [_opt('kalamkari', 'Kalamkari')],
      'fibre_type': [
        _opt('silk', 'Silk'),
        _opt('sico', 'Sico (Silk-Cotton Blend)'),
      ],
      'product_type': [_opt('saree', 'Saree')],
      'garment_type': [_opt('kurthi', 'Kurthi')],
      'home_product_type': [_opt('bedsheet', 'Bedsheet')],
    };

    test('reads as a name: descriptors, craft, fibre, then the noun', () {
      final name = composeDesignNamePreview(
        options: options,
        descriptorIds: ['soft', 'pure'],
        attrs: {'craftTechnique': 'kalamkari', 'fibreType': 'silk', 'productType': 'saree'},
        home: false,
      );

      expect(name, 'Soft Pure Kalamkari Silk Saree');
    });

    test('a fibre\'s parenthesised half never reaches the name', () {
      final name = composeDesignNamePreview(
        options: options,
        descriptorIds: const [],
        attrs: {'fibreType': 'sico', 'productType': 'saree'},
        home: false,
      );

      expect(name, 'Sico Saree');
    });

    test('the sub type stands in only where there is no product type', () {
      final name = composeDesignNamePreview(
        options: options,
        descriptorIds: const [],
        attrs: {'garmentType': 'kurthi'},
        home: false,
      );

      expect(name, 'Kurthi');
    });

    test('a product type present is the noun, never the sub type', () {
      final name = composeDesignNamePreview(
        options: options,
        descriptorIds: const [],
        attrs: {'productType': 'saree', 'garmentType': 'kurthi'},
        home: false,
      );

      expect(name, 'Saree');
    });

    test('home industry reads its own product type list', () {
      final name = composeDesignNamePreview(
        options: options,
        descriptorIds: const [],
        attrs: {'homeProductType': 'bedsheet', 'productType': 'saree'},
        home: true,
      );

      expect(name, 'Bedsheet');
    });

    test('nothing chosen yet composes to nothing, not a broken sentence', () {
      expect(
        composeDesignNamePreview(
          options: options,
          descriptorIds: const [],
          attrs: const {},
          home: false,
        ),
        isEmpty,
      );
    });
  });

  group('requiredErrorsForTab', () {
    test('Basic: names every missing field, worded like the server', () {
      final errors = requiredErrorsForTab(
        tabIndex: 0,
        attrs: const {},
        home: false,
      );

      expect(errors, {
        'industry': 'Industry is needed',
        'productType': 'Product type is needed',
        'fibreType': 'Fiber type is needed',
      });
    });

    test('Basic: the home industry checks its own product type key', () {
      final errors = requiredErrorsForTab(
        tabIndex: 0,
        attrs: const {'industry': 'home'},
        home: true,
      );

      expect(errors.containsKey('homeProductType'), isTrue);
      expect(errors.containsKey('productType'), isFalse);
    });

    test('Basic: answered fields drop out, one at a time', () {
      final errors = requiredErrorsForTab(
        tabIndex: 0,
        attrs: const {'industry': 'clothing', 'productType': 'saree'},
        home: false,
      );

      expect(errors, {'fibreType': 'Fiber type is needed'});
    });

    test('Basic: a garment needs its sub type, a saree does not', () {
      // The field is starred for a garment; Next should say so rather than
      // let a blank cut through to the server.
      expect(
        requiredErrorsForTab(
          tabIndex: 0,
          attrs: const {'industry': 'clothing', 'productType': 'kurthi', 'fibreType': 'cotton'},
          home: false,
          requiresSubType: true,
        ),
        {'garmentType': 'Product sub type is needed'},
      );

      expect(
        requiredErrorsForTab(
          tabIndex: 0,
          attrs: const {'industry': 'clothing', 'productType': 'saree', 'fibreType': 'cotton'},
          home: false,
        ),
        isEmpty,
      );
    });

    test('Craft: colour and craft technique are both required', () {
      final errors = requiredErrorsForTab(
        tabIndex: 1,
        attrs: const {},
        home: false,
      );

      expect(errors, {
        'colour': 'Colour is needed',
        'craftTechnique': 'Craft technique is needed',
      });
    });

    test('Prices: only retail is required, and only when blank', () {
      expect(
        requiredErrorsForTab(
          tabIndex: 3,
          attrs: const {},
          home: false,
          retailPrice: '',
        ),
        {'retail': 'A selling price is needed'},
      );

      expect(
        requiredErrorsForTab(
          tabIndex: 3,
          attrs: const {},
          home: false,
          retailPrice: '2500',
        ),
        isEmpty,
      );
    });

    test('Details and Images ask for nothing — Next always passes through',
        () {
      for (final tab in [2, 4]) {
        expect(
          requiredErrorsForTab(tabIndex: tab, attrs: const {}, home: false),
          isEmpty,
        );
      }
    });

    test('Stock: opening quantity only checked when asked to', () {
      // Not asked — the edit screen's own Stock tab, which never wires this.
      expect(
        requiredErrorsForTab(tabIndex: 5, attrs: const {}, home: false),
        isEmpty,
      );

      // Asked, and nothing entered.
      expect(
        requiredErrorsForTab(
          tabIndex: 5,
          attrs: const {},
          home: false,
          checkOpeningStock: true,
        ),
        {
          'openingStock':
              'At least one location needs a quantity greater than zero.',
        },
      );

      // Asked, and a location with a zero or blank quantity is still nothing.
      expect(
        requiredErrorsForTab(
          tabIndex: 5,
          attrs: const {},
          home: false,
          checkOpeningStock: true,
          openingLocationId: 'wh-1',
          openingQty: '0',
        ),
        isNotEmpty,
      );

      // Asked, and answered.
      expect(
        requiredErrorsForTab(
          tabIndex: 5,
          attrs: const {},
          home: false,
          checkOpeningStock: true,
          openingLocationId: 'wh-1',
          openingQty: '5',
        ),
        isEmpty,
      );
    });
  });
}
