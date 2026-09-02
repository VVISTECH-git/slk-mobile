import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/record_fields.dart';
import 'package:slk_mobile/models/core.dart';

CoreOption opt(String id, String label, {String? parent, String? soldBy, bool isDefault = false}) =>
    CoreOption(
      id: id,
      label: label,
      parentId: parent,
      soldById: soldBy,
      isDefault: isDefault,
    );

void main() {
  group('narrow', () {
    // The shape that caused the bug: Saree/Dupatta/Fabric name Clothing as
    // their parent, and Bedsheets names nobody.
    final productTypes = [
      opt('saree', 'Saree', parent: 'clothing'),
      opt('dupatta', 'Dupatta', parent: 'clothing'),
      opt('fabric', 'Fabric', parent: 'clothing'),
      opt('bedsheets', 'Bedsheets'),
    ];

    test('REGRESSION: an unparented value is not offered under a parent', () {
      // The first cut let anything with a null parent through, so choosing
      // Clothing offered Bedsheets. An unparented value applies to *every*
      // parent, not to any parent that happens to be asking.
      final under = narrow(productTypes, 'clothing').map((o) => o.label);

      expect(under, ['Saree', 'Dupatta', 'Fabric']);
      expect(under, isNot(contains('Bedsheets')));
    });

    test('nothing chosen above offers nothing at all', () {
      // Not "the values that belong to nobody" — with no industry picked
      // there is nothing the field could honestly offer.
      expect(narrow(productTypes, null), isEmpty);
    });

    test('an industry with no product types offers none', () {
      expect(narrow(productTypes, 'garments'), isEmpty);
    });

    test('fallbackToUnparented only fires when the parented set is empty', () {
      // Textile Material: Silk names its own weaves, and a fibre that names
      // none falls through to the ones naming no fibre at all.
      final materials = [
        opt('katan', 'Katan', parent: 'silk'),
        opt('mulmul', 'Mul Mul', parent: 'cotton'),
        opt('georgette', 'Georgette'),
      ];

      expect(
        narrow(materials, 'silk', fallbackToUnparented: true).map((o) => o.label),
        ['Katan'],
        reason: 'silk has its own, so no fall-through',
      );

      expect(
        narrow(materials, 'linen', fallbackToUnparented: true).map((o) => o.label),
        ['Georgette'],
        reason: 'linen names none, so the unparented ones apply',
      );

      expect(
        narrow(materials, 'linen').map((o) => o.label),
        isEmpty,
        reason: 'without the flag there is no fall-through',
      );
    });
  });

  group('isHomeIndustry', () {
    test('matches both spellings the live data has used', () {
      // Renamed from "Home & Lifestyle" to "Home" on the live screen; the web
      // form compared against one string and its whole home branch went dead.
      expect(isHomeIndustry('Home'), isTrue);
      expect(isHomeIndustry('Home & Lifestyle'), isTrue);
      expect(isHomeIndustry('Clothing'), isFalse);
      expect(isHomeIndustry(null), isFalse);
    });
  });

  group('defaultAttributes', () {
    test('applies a default whose parent is also a default, and not one whose is not', () {
      final options = <String, List<CoreOption>>{
        'industry': [opt('clothing', 'Clothing', isDefault: true)],
        'product_type': [
          opt('saree', 'Saree', parent: 'clothing', soldBy: 'piece', isDefault: true),
        ],
        'fibre_type': [opt('silk', 'Silk')],
        // Mul Mul belongs to Cotton, which is not the default fibre — so it
        // must not be applied until a fibre is actually chosen.
        'textile_material': [
          opt('mulmul', 'Mul Mul', parent: 'cotton', isDefault: true),
        ],
        'uom': [opt('piece', 'Piece')],
      };

      final defaults = defaultAttributes(options);

      expect(defaults['industry'], 'clothing');
      expect(defaults['productType'], 'saree');
      expect(defaults['textileMaterial'], isNull);
    });

    test('unit of measure follows the product type rather than being asked', () {
      final options = <String, List<CoreOption>>{
        'industry': [opt('clothing', 'Clothing', isDefault: true)],
        'product_type': [
          opt('saree', 'Saree', parent: 'clothing', soldBy: 'piece', isDefault: true),
        ],
        'uom': [opt('piece', 'Piece'), opt('metre', 'Metre')],
      };

      expect(defaultAttributes(options)['uom'], 'piece');
    });

    test('colour is never defaulted', () {
      final options = <String, List<CoreOption>>{
        'colour': [opt('red', 'Red', isDefault: true)],
      };

      // Colour is per-colourway and not in the attribute map at all — a record
      // silently created in somebody else's idea of a default colour is worse
      // than one that makes you choose.
      expect(defaultAttributes(options).containsKey('colour'), isFalse);
    });
  });

  group('attributeLists', () {
    test('every key the form sends is one the API knows', () {
      // These must match ATTRIBUTES in apps/web/src/lib/attributes.ts —
      // toRecordDraft answers 400 for an attribute it does not recognise, so a
      // typo here is a broken save, not a quietly ignored field.
      const knownToApi = {
        'industry', 'productType', 'homeProductType', 'garmentType', 'uom',
        'homeWeavingCategory', 'productionMethod', 'audienceType', 'descriptor',
        'fibreType', 'weaveStructure', 'textileMaterial', 'silkSubFamily',
        'cottonSubFamily', 'fabricType', 'craftTechnique', 'craftSubType',
        'regionalStyle', 'motifCategory', 'motif', 'borderStyle', 'borderHeight',
        'sareeStyle', 'blouseStyle', 'palluMotif', 'borderMotif',
        'sareeBodyMotif', 'blouseMotif', 'blouseBorder', 'sareeLayout',
        'palluDesign', 'blouseAvailable', 'blouseStatus', 'blouseMaterial',
      };

      for (final key in attributeLists.keys) {
        expect(knownToApi, contains(key), reason: '"$key" is not an API attribute');
      }
    });
  });
}
