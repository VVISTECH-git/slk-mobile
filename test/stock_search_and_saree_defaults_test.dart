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
          opt('body', 'Body', parent: 'saree'),
          opt('pallu', 'Pallu', parent: 'saree'),
          opt('border', 'Border', parent: 'saree'),
          opt('blouse', 'Blouse', parent: 'saree'),
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
