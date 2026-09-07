import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slk_mobile/core/product_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ProductDraftStore', () {
    test('nothing saved yet reads as no draft', () async {
      expect(await ProductDraftStore.instance.read(), isNull);
    });

    test('round-trips a saved draft', () async {
      final draft = {
        'attrs': {'industry': 'ind-1', 'productType': 'saree'},
        'descriptors': ['Hand-painted'],
        'imageSlots': ['body', 'pallu'],
        'colourId': 'red',
        'secondaryColourId': null,
        'prices': {'retail': '999', 'cost': ''},
        'notes': 'Left half-filled',
        'name': '',
        'nameIsCustom': false,
        'location': 'wh-pedana',
        'qty': '2',
      };

      await ProductDraftStore.instance.save(draft);
      final restored = await ProductDraftStore.instance.read();

      expect(restored, draft);
    });

    test('a later save replaces the earlier one, not merges with it', () async {
      await ProductDraftStore.instance.save({'notes': 'first'});
      await ProductDraftStore.instance.save({'notes': 'second'});

      expect((await ProductDraftStore.instance.read())?['notes'], 'second');
    });

    test('clear removes the draft entirely', () async {
      await ProductDraftStore.instance.save({'notes': 'anything'});
      await ProductDraftStore.instance.clear();

      expect(await ProductDraftStore.instance.read(), isNull);
    });

    test('a malformed stored value reads as no draft rather than throwing',
        () async {
      SharedPreferences.setMockInitialValues({'product_draft': 'not json'});

      expect(await ProductDraftStore.instance.read(), isNull);
    });
  });
}
