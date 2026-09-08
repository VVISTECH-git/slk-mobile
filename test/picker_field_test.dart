import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/theme/app_theme.dart';
import 'package:slk_mobile/widgets/picker_field.dart';

void main() {
  Widget harness(Widget Function(BuildContext) builder) => ProviderScope(
        child: MaterialApp(
          theme: SlkThemes.kalamkari.toThemeData(),
          home: Scaffold(body: Builder(builder: builder)),
        ),
      );

  const options = [
    PickerOption('block', 'Hand Block'),
    PickerOption('screen', 'Hand Screen'),
  ];

  group('PickerField wheel sheet', () {
    testWidgets(
        'REGRESSION: an already-answered, clearable field still offers Done',
        (tester) async {
      // The exact shape that broke: Craft sub type already holds a value and
      // is optional, same as Secondary colour, Weave structure and most
      // other fields once answered. Clear alone meant a scroll to a new
      // choice had nothing to confirm it with.
      await tester.pumpWidget(harness(
        (context) => PickerField(
          label: 'Craft sub type',
          value: 'block',
          allowClear: true,
          options: options,
          onChanged: (_) {},
        ),
      ));

      await tester.tap(find.text('Hand Block'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('Done confirms whatever the wheel is currently on',
        (tester) async {
      String? picked;

      await tester.pumpWidget(harness(
        (context) => PickerField(
          label: 'Craft sub type',
          value: 'block',
          allowClear: true,
          options: options,
          onChanged: (v) => picked = v,
        ),
      ));

      await tester.tap(find.text('Hand Block'));
      await tester.pumpAndSettle();

      // Scroll the wheel down one row's worth to bring Hand Screen to centre.
      await tester.drag(find.text('Hand Screen'), const Offset(0, -54));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(picked, 'screen');
    });

    testWidgets('Clear still reports null and closes the sheet',
        (tester) async {
      String? picked = 'unset';

      await tester.pumpWidget(harness(
        (context) => PickerField(
          label: 'Craft sub type',
          value: 'block',
          allowClear: true,
          options: options,
          onChanged: (v) => picked = v,
        ),
      ));

      await tester.tap(find.text('Hand Block'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      expect(find.text('Cancel'), findsNothing); // the sheet is gone
    });

    testWidgets('a mandatory field (no allowClear) only ever shows Done',
        (tester) async {
      await tester.pumpWidget(harness(
        (context) => PickerField(
          label: 'Fibre type',
          value: 'block',
          options: options,
          onChanged: (_) {},
        ),
      ));

      await tester.tap(find.text('Hand Block'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('nothing chosen yet shows Done alone, same as before',
        (tester) async {
      await tester.pumpWidget(harness(
        (context) => PickerField(
          label: 'Secondary colour',
          value: null,
          allowClear: true,
          options: options,
          onChanged: (_) {},
        ),
      ));

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
    });
  });
}
