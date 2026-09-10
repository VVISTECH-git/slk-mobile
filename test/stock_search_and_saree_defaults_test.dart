import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/core/api_client.dart';
import 'package:slk_mobile/features/core/core_auth.dart';
import 'package:slk_mobile/features/core/record_form_fields.dart';
import 'package:slk_mobile/features/core/stock_records_screen.dart';
import 'package:slk_mobile/models/core.dart';
import 'package:slk_mobile/theme/app_theme.dart';

/// Records what it was asked for instead of hitting the network — the point
/// of these tests is "did the widget ask", not "what does the API answer".
class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: 'http://test.invalid');

  final List<String> requestedPaths = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    requestedPaths.add(path);
    return <dynamic>[];
  }
}

CoreOption opt(String id, String label, {String? parent}) =>
    CoreOption(id: id, label: label, parentId: parent);

void main() {
  group('Stock Records — manual code entry', () {
    testWidgets(
      'tapping the search button submits the typed code, no Enter key needed',
      (tester) async {
        final api = _RecordingApiClient();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [coreApiProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: SlkThemes.kalamkari.toThemeData(),
              home: const StockRecordsScreen(),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '500066');
        // The regression: iOS's numeric keypad has no return/search key, so
        // onSubmitted alone can never fire from typing. Tapping the button —
        // not pressing Enter — is what this test exercises.
        await tester.tap(find.byTooltip('Search'));
        await tester.pumpAndSettle();

        expect(api.requestedPaths, ['/pieces/500066']);
      },
    );

    testWidgets('onSubmitted (Enter) still works, for HID scanners', (tester) async {
      final api = _RecordingApiClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [coreApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: SlkThemes.kalamkari.toThemeData(),
            home: const StockRecordsScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '300032');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(api.requestedPaths, ['/pieces/300032']);
    });
  });

  group('Saree image slots default to all wanted', () {
    testWidgets('choosing Saree selects Body, Pallu, Border and Blouse',
        (tester) async {
      late _HarnessState fields;

      final options = <String, List<CoreOption>>{
        'product_type': [
          opt('saree', 'Saree', parent: 'clothing'),
          opt('bedsheets', 'Bedsheets'),
        ],
        'image_slot': [
          // Unparented, matching the live vocabulary exactly: nothing has
          // ever scoped these four to a product type, Saree included.
          opt('body', 'Body'),
          opt('pallu', 'Pallu'),
          opt('border', 'Border'),
          opt('blouse', 'Blouse'),
          // Belongs to a different product type — must not be swept in.
          opt('flat-lay', 'Flat lay', parent: 'bedsheets'),
        ],
      };

      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      expect(fields.imageSlots, isEmpty, reason: 'nothing ticked before a type is chosen');

      fields.setProductType(options, 'productType', 'saree');
      await tester.pump();

      expect(
        fields.imageSlots.toSet(),
        {'body', 'pallu', 'border', 'blouse'},
      );
    });

    testWidgets(
      'REGRESSION: re-confirming Saree does not wipe slots already set',
      (tester) async {
        // The edit screen shares this mixin, and its Product Type picker
        // fires onChanged on every Done tap — including confirming a value
        // that was already selected. Applying the default unconditionally
        // there wiped a photographed slot outside the usual four, and
        // silently restored one somebody had deliberately unticked.
        late _HarnessState fields;

        final options = <String, List<CoreOption>>{
          'product_type': [opt('saree', 'Saree', parent: 'clothing')],
          'image_slot': [
            opt('body', 'Body', parent: 'saree'),
            opt('pallu', 'Pallu', parent: 'saree'),
            opt('border', 'Border', parent: 'saree'),
            opt('blouse', 'Blouse', parent: 'saree'),
            // Photographed already, under a slot Saree's own four don't name.
            opt('full-length', 'Full length'),
          ],
        };

        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        // As if seeded from an existing record: Blouse deliberately left
        // out, and a universal slot present that the four defaults know
        // nothing about.
        fields.imageSlots = ['body', 'pallu', 'border', 'full-length'];

        fields.setProductType(options, 'productType', 'saree');
        await tester.pump();

        expect(
          fields.imageSlots.toSet(),
          {'body', 'pallu', 'border', 'full-length'},
          reason: 'confirming an unchanged Product Type must not touch '
              "slots that were already someone's own answer",
        );
      },
    );

    test(
      'REGRESSION: a record that opens already defaulted to Saree still gets all four',
      () {
        // defaultAttributes() writes attrs['productType'] directly — it
        // never calls setProductType — so when Saree is the vocabulary's
        // own default, a brand-new record used to open with none of the
        // four slots ticked, because the only place that applied them lived
        // inside setProductType and nothing had called it.
        final options = <String, List<CoreOption>>{
          'product_type': [
            opt('saree', 'Saree', parent: 'clothing'),
            opt('bedsheets', 'Bedsheets'),
          ],
          'image_slot': [
            opt('body', 'Body'),
            opt('pallu', 'Pallu'),
            opt('border', 'Border'),
            opt('blouse', 'Blouse'),
            // Belongs to a different product type — must not be swept in,
            // even under the broader null-or-matching-parent filter.
            opt('flat-lay', 'Flat lay', parent: 'bedsheets'),
          ],
        };

        expect(
          sareeDefaultImageSlots(options, 'saree').toSet(),
          {'body', 'pallu', 'border', 'blouse'},
          reason: 'new_record_screen.dart calls this directly once it finds '
              "the defaulted product type is Saree — see its own defaults "
              "block, which setProductType's tests above cannot reach.",
        );
      },
    );
  });

  group('Saree sub type defaults to With Blouse', () {
    final options = <String, List<CoreOption>>{
      'product_type': [
        opt('saree', 'Saree', parent: 'clothing'),
        opt('bedsheets', 'Bedsheets'),
      ],
      'garment_type': [
        opt('with-blouse', 'With Blouse', parent: 'saree'),
        opt('without-blouse', 'Without Blouse', parent: 'saree'),
      ],
      'blouse_status': [
        opt('stitched', 'Stitched'),
        // The vocabulary's own spelling — a plain "Unstitched" is not what
        // production actually calls it.
        opt('unstitched', 'UnStitched'),
      ],
    };

    testWidgets('choosing Saree defaults the sub type to With Blouse',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.setProductType(options, 'productType', 'saree');
      await tester.pump();

      expect(fields.attrs['garmentType'], 'with-blouse');
      // Nobody can tell an unstitched blouse from one nobody asked about —
      // the default cascades all the way to Blouse status.
      expect(fields.attrs['blouseStatus'], 'unstitched');
    });

    testWidgets(
      'REGRESSION: re-confirming Saree does not overwrite a deliberate Without Blouse',
      (tester) async {
        late _HarnessState fields;
        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        fields.attrs['productType'] = 'saree';
        fields.attrs['garmentType'] = 'without-blouse';

        fields.setProductType(options, 'productType', 'saree');
        await tester.pump();

        expect(fields.attrs['garmentType'], 'without-blouse');
      },
    );

    testWidgets('picking the sub type by hand also defaults Blouse status',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.setGarmentType(options, 'with-blouse');
      await tester.pump();

      expect(fields.attrs['blouseStatus'], 'unstitched');
    });

    testWidgets('an already-chosen Blouse status is never overwritten',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.attrs['blouseStatus'] = 'stitched';
      fields.setGarmentType(options, 'with-blouse');
      await tester.pump();

      expect(fields.attrs['blouseStatus'], 'stitched');
    });

    testWidgets(
      'REGRESSION: a record that opens already defaulted to Saree still gets '
      'With Blouse, All Over and UnStitched',
      (tester) async {
        // defaultAttributes() writes attrs['productType'] directly — same as
        // the image-slots regression above — so NewRecordScreen calls
        // applySareeExtras itself rather than relying on setProductType,
        // which never runs when Saree is only ever the vocabulary's own
        // default and nobody touches the picker.
        final withStyle = <String, List<CoreOption>>{
          ...options,
          'saree_style': [opt('all-over', 'All Over'), opt('panelled', 'Panelled')],
        };

        late _HarnessState fields;
        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        fields.attrs['productType'] = 'saree';
        fields.applySareeExtras(withStyle, 'saree');
        await tester.pump();

        expect(fields.attrs['garmentType'], 'with-blouse');
        expect(fields.attrs['blouseStatus'], 'unstitched');
        expect(fields.attrs['sareeStyle'], 'all-over');
      },
    );
  });

  group('Kalamkari defaults Craft sub type to Hand Screen', () {
    final options = <String, List<CoreOption>>{
      'craft_technique': [
        opt('kalamkari', 'Kalamkari'),
        opt('block-print', 'Block Print'),
      ],
      'craft_sub_type': [
        opt('hand-block', 'Hand Block'),
        opt('hand-screen', 'Hand Screen'),
      ],
    };

    testWidgets('choosing Kalamkari defaults the sub type to Hand Screen',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.setCraftTechnique(options, 'kalamkari');
      await tester.pump();

      expect(fields.attrs['craftSubType'], 'hand-screen');
    });

    testWidgets(
      'REGRESSION: re-confirming Kalamkari does not overwrite a deliberate Hand Block',
      (tester) async {
        late _HarnessState fields;
        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        fields.attrs['craftTechnique'] = 'kalamkari';
        fields.attrs['craftSubType'] = 'hand-block';

        fields.setCraftTechnique(options, 'kalamkari');
        await tester.pump();

        expect(fields.attrs['craftSubType'], 'hand-block');
      },
    );

    testWidgets('a technique other than Kalamkari never sets a sub type',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.setCraftTechnique(options, 'block-print');
      await tester.pump();

      expect(fields.attrs['craftSubType'], isNull);
    });

    testWidgets(
      'REGRESSION: a record that opens already defaulted to Kalamkari still '
      'gets Hand Screen',
      (tester) async {
        // Kalamkari is also the vocabulary's own default craft technique —
        // defaultAttributes() writes attrs['craftTechnique'] directly, so
        // NewRecordScreen calls applyCraftTechniqueExtras itself rather than
        // relying on setCraftTechnique, which never runs when nobody
        // touches the picker.
        late _HarnessState fields;
        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        fields.attrs['craftTechnique'] = 'kalamkari';
        fields.applyCraftTechniqueExtras(options);
        await tester.pump();

        expect(fields.attrs['craftSubType'], 'hand-screen');
      },
    );
  });

  group('subTypeRequired — only a garment has a cut to name', () {
    final options = <String, List<CoreOption>>{
      'industry': [opt('clothing', 'Clothing'), opt('home', 'Home')],
      'product_type': [
        opt('saree', 'Saree', parent: 'clothing'),
        opt('kurthi', 'Kurthi', parent: 'clothing'),
        opt('dupatta', 'Dupatta', parent: 'clothing'),
      ],
      'garment_type': [
        opt('with-blouse', 'With Blouse', parent: 'saree'),
        opt('a-line', 'A-line', parent: 'kurthi'),
      ],
    };

    testWidgets('a kurthi requires it', (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();
      fields.attrs['industry'] = 'clothing';
      fields.attrs['productType'] = 'kurthi';
      expect(fields.subTypeRequired(options), isTrue);
    });

    testWidgets('a saree does not, nor a type with no sub types, nor the home industry',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.attrs['industry'] = 'clothing';
      fields.attrs['productType'] = 'saree';
      expect(fields.subTypeRequired(options), isFalse);

      fields.attrs['productType'] = 'dupatta';
      expect(fields.subTypeRequired(options), isFalse);

      fields.attrs['industry'] = 'home';
      fields.attrs['productType'] = 'kurthi';
      expect(fields.subTypeRequired(options), isFalse);
    });
  });

  group('Saree defaults to All Over', () {
    final options = <String, List<CoreOption>>{
      'product_type': [
        opt('saree', 'Saree', parent: 'clothing'),
        opt('bedsheets', 'Bedsheets'),
      ],
      'saree_style': [
        // The vocabulary's own capitalisation — "All over" matches nothing.
        opt('all-over', 'All Over'),
        opt('panelled', 'Panelled'),
      ],
    };

    testWidgets('choosing Saree defaults Saree style to All Over',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.setProductType(options, 'productType', 'saree');
      await tester.pump();

      expect(fields.attrs['sareeStyle'], 'all-over');
    });

    testWidgets(
      'REGRESSION: re-confirming Saree does not overwrite a deliberate Panelled',
      (tester) async {
        late _HarnessState fields;
        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        fields.attrs['productType'] = 'saree';
        fields.attrs['sareeStyle'] = 'panelled';

        fields.setProductType(options, 'productType', 'saree');
        await tester.pump();

        expect(fields.attrs['sareeStyle'], 'panelled');
      },
    );
  });

  group('Saree motif cascades from Craft & Design to body, pallu and border', () {
    testWidgets('picking Craft & Design\'s Motif fills all three blanks',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.setMotif('peacock');
      await tester.pump();

      expect(fields.attrs['motif'], 'peacock');
      expect(fields.attrs['sareeBodyMotif'], 'peacock');
      expect(fields.attrs['palluMotif'], 'peacock');
      expect(fields.attrs['borderMotif'], 'peacock');
    });

    testWidgets('a motif already chosen for one part is left alone',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.attrs['borderMotif'] = 'floral';

      fields.setMotif('peacock');
      await tester.pump();

      expect(fields.attrs['sareeBodyMotif'], 'peacock');
      expect(fields.attrs['palluMotif'], 'peacock');
      expect(fields.attrs['borderMotif'], 'floral');
    });

    testWidgets(
      'picking Saree body motif directly cascades to Pallu and Border too',
      (tester) async {
        late _HarnessState fields;
        await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
        await tester.pump();

        fields.setSareeBodyMotif('lotus');
        await tester.pump();

        expect(fields.attrs['palluMotif'], 'lotus');
        expect(fields.attrs['borderMotif'], 'lotus');
      },
    );

    testWidgets('clearing Craft & Design\'s Motif touches nothing else',
        (tester) async {
      late _HarnessState fields;
      await tester.pumpWidget(_Harness(onReady: (f) => fields = f));
      await tester.pump();

      fields.attrs['sareeBodyMotif'] = 'lotus';

      fields.setMotif(null);
      await tester.pump();

      expect(fields.attrs['motif'], isNull);
      expect(fields.attrs['sareeBodyMotif'], 'lotus');
    });
  });
}

/// Minimal StatefulWidget wired to the mixin under test, so `setProductType`
/// can be called and its effect on `imageSlots` observed directly — no
/// network, no navigation, no real form UI required.
class _Harness extends StatefulWidget {
  const _Harness({required this.onReady});

  final void Function(_HarnessState) onReady;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with RecordFormFields<_Harness> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady(this));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
