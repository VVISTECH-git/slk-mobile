import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/models/core.dart';

/// The contract with slk-core, pinned.
///
/// Every fixture below is a verbatim response from a running slk-core, not a
/// hand-written guess at one. That is the whole point: the app and the API are
/// in different repositories and different languages, so nothing but a test
/// like this notices when one of them changes its mind about a field name.
///
/// If one of these fails, the API changed. Fix the model to match the API —
/// never the fixture to match the model.
void main() {
  group('CoreActor', () {
    // GET /api/v1/auth/me
    const me = {
      'id': '96b1aa3e-0f34-4758-a79a-39b7200eb678',
      'code': 'apitest',
      'name': 'API Test',
      'role': 'owner',
    };

    test('parses the sign-in response', () {
      final actor = CoreActor.fromJson(me);

      expect(actor.id, '96b1aa3e-0f34-4758-a79a-39b7200eb678');
      expect(actor.code, 'apitest');
      expect(actor.name, 'API Test');
      expect(actor.role, 'owner');
    });

    test('survives being cached and read back', () {
      final restored = CoreActor.decode(CoreActor.fromJson(me).encode());
      expect(restored.id, me['id']);
      expect(restored.role, me['role']);
    });

    test('keeps whatever role the server sent, without interpreting it', () {
      // Deliberately no `canCreateRecords` here. Creating is open to every
      // signed-in actor, floor included; anything else the API gates is
      // answered by the API, and a copy of its rules in Dart is a copy that
      // silently disagrees the day one of them changes.
      for (final role in ['floor', 'office', 'owner']) {
        expect(
          CoreActor(id: 'x', code: 'c', name: 'n', role: role).role,
          role,
        );
      }
    });
  });

  group('CoreOptions', () {
    // GET /api/v1/options — one colour and one product type, verbatim.
    final options = <String, dynamic>{
      'colour': [
        {
          'id': 'f108d888-018a-4eaa-ba69-dade5989d310',
          'label': 'Alice Blue',
          'parentId': null,
          'soldById': null,
          'isDefault': false,
          'hex': '#F0F8FF',
        },
      ],
      'product_type': [
        {
          'id': '11111111-1111-1111-1111-111111111111',
          'label': 'Saree',
          'parentId': '22222222-2222-2222-2222-222222222222',
          'soldById': '33333333-3333-3333-3333-333333333333',
          'isDefault': true,
          'hex': null,
        },
      ],
    };

    test('groups values by list code', () {
      final parsed = parseCoreOptions(options);
      expect(parsed.keys, containsAll(<String>['colour', 'product_type']));
      expect(parsed['colour']!, hasLength(1));
    });

    test('turns the vocabulary hex into a real swatch', () {
      final colour = parseCoreOptions(options)['colour']!.single;

      // Opaque, and the exact colour the vocabulary holds — not a guess from
      // the name, which is what the old hardcoded map did.
      expect(colour.swatch, const Color(0xFFF0F8FF));
    });

    test('a value with no hex has no swatch', () {
      expect(parseCoreOptions(options)['product_type']!.single.swatch, isNull);
    });

    test('carries the parent, which is how a list narrows', () {
      final type = parseCoreOptions(options)['product_type']!.single;
      expect(type.parentId, '22222222-2222-2222-2222-222222222222');
      expect(type.soldById, '33333333-3333-3333-3333-333333333333');
      expect(type.isDefault, isTrue);
    });

    test('a malformed hex is ignored rather than thrown', () {
      final odd = parseCoreOptions({
        'colour': [
          {'id': 'a', 'label': 'Bad', 'parentId': null, 'soldById': null,
           'isDefault': false, 'hex': 'not-a-colour'},
        ],
      });

      expect(odd['colour']!.single.swatch, isNull);
    });
  });

  group('CoreShotListRow', () {
    // GET /api/v1/photographs — verbatim.
    final shot = <String, dynamic>{
      'id': '6fa57655-fe13-4475-b93d-b707b112b8af',
      'name': 'Kalamkari Cotton Saree',
      'productCode': '300041',
      'designCode': 'SAR-GEN-COT-0008',
      'colour': 'Alice Blue',
      'colourHex': '#F0F8FF',
      'pending': ['Body', 'Pallu'],
    };

    test('parses a record with photographs outstanding', () {
      final row = CoreShotListRow.fromJson(shot);

      expect(row.id, '6fa57655-fe13-4475-b93d-b707b112b8af');
      expect(row.productCode, '300041');
      expect(row.designCode, 'SAR-GEN-COT-0008');
      expect(row.pending, ['Body', 'Pallu']);
      expect(row.swatch, const Color(0xFFF0F8FF));
    });

    test('a record with no consignment yet still parses', () {
      // The list is about photographs, not deliveries, so a design nobody has
      // received against still belongs on it — and the screen falls back to
      // the design code for that one row rather than showing nothing.
      final row = CoreShotListRow.fromJson({...shot, 'productCode': null});

      expect(row.productCode, isNull);
      expect(row.designCode, 'SAR-GEN-COT-0008');
    });

    test('the search matches a slot name, not only the product', () {
      // Somebody with a light set up for pallus wants the pallu rows.
      expect(CoreShotListRow.fromJson(shot).haystack, contains('pallu'));
    });
  });

  group('CorePiece', () {
    // GET /api/v1/pieces/500066 — verbatim.
    final piece = <String, dynamic>{
      'id': '60ec2171-7149-4f17-bd63-9b5ea06f6964',
      'itemCode': '500066',
      'productCode': '300032',
      'serial': 1,
      'designCode': 'SAR-GEN-SIL-0001',
      'name': 'Kalamkari Silk Saree',
      'colour': 'Beige',
      'productType': 'Saree',
      'motifCategory': 'Kolam',
      'motif': null,
      'location': 'Warehouse',
      'isHeld': true,
      'receivedInto': 'Warehouse',
      'receivedAt': '02 Sep 2026',
      'receivedOn': '2026-09-02',
      'reference': null,
      'priceMinor': 349999,
    };

    test('parses a scan', () {
      final parsed = CorePiece.fromJson(piece);

      expect(parsed.itemCode, '500066');
      expect(parsed.productCode, '300032');
      expect(parsed.location, 'Warehouse');
      expect(parsed.isHeld, isTrue);
      expect(parsed.price, '₹3,500');
    });

    test('a piece that has left us reads as gone, not as unknown', () {
      // The ledger nulls the location once it is sold, written off or sent
      // on. "Is this still ours" is the first thing a scan answers, so the
      // two must not be confused.
      final gone = CorePiece.fromJson({
        ...piece,
        'isHeld': false,
        'location': null,
      });

      expect(gone.isHeld, isFalse);
      expect(gone.location, isNull);
    });

    test('a price arriving as a string is still a price', () {
      // bigint through db.execute used to reach the app as "349999". The API
      // casts now, but a phone cannot be redeployed the way a server can.
      expect(CorePiece.fromJson({...piece, 'priceMinor': '349999'}).price,
          '₹3,500');
    });

    test('an unpriced piece says so rather than reading as free', () {
      expect(CorePiece.fromJson({...piece, 'priceMinor': null}).price, '—');
    });
  });

  group('CoreLocation', () {
    // GET /api/v1/locations — verbatim, in the order the API returns.
    final locations = [
      {'id': 'c4d1d549-e313-431b-b71d-7cf20954f7b5', 'code': 'WH-MAIN', 'name': 'Warehouse', 'isInternal': true},
      {'id': 'f07b21a7-6357-4ea8-8e07-fc57db586876', 'code': 'SHOP-01', 'name': 'Retail Unit 1', 'isInternal': true},
      {'id': '9c6bcd2e-fa23-47f7-88d5-12a06db2bce0', 'code': 'SHOP-02', 'name': 'Retail Unit 2', 'isInternal': true},
      {'id': 'ee1aee45-cfb2-4272-9810-ac0733eb170b', 'code': 'PRODUCTION', 'name': 'Production', 'isInternal': false},
      {'id': 'd2c9db35-293b-4780-94ff-758d1f03e628', 'code': 'CUSTOMER', 'name': 'Customer', 'isInternal': false},
      {'id': '8f6fde25-805e-46e1-a02e-d9710ef403ca', 'code': 'SCRAP', 'name': 'Scrap', 'isInternal': false},
    ];

    test('parses, and the API sends internal ones first', () {
      final parsed = [for (final row in locations) CoreLocation.fromJson(row)];

      expect(parsed.first.name, 'Warehouse');
      expect(parsed.first.isInternal, isTrue);
      expect(parsed.last.isInternal, isFalse);
    });

    test('the form offers only the three we hold stock in', () {
      // Opening stock arrives *from* Production into somewhere we own, so
      // Production, Customer and Scrap must never be offered as the "where".
      final internal =
          [for (final row in locations) CoreLocation.fromJson(row)]
              .where((l) => l.isInternal)
              .map((l) => l.name)
              .toList();

      expect(internal, ['Warehouse', 'Retail Unit 1', 'Retail Unit 2']);
    });
  });
}
