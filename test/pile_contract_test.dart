import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/models/core.dart';

/// The Piles contract with slk-core, pinned — same rule as
/// core_contract_test.dart: if one of these fails, the API changed. Fix the
/// model to match the API, never the fixture to match the model.
void main() {
  group('CoreColour', () {
    // GET /api/v1/piles/colours
    test('parses a colour', () {
      final c = CoreColour.fromJson(const {'id': 'rani-pink', 'label': 'Rani pink'});
      expect(c.id, 'rani-pink');
      expect(c.label, 'Rani pink');
    });

    test('falls back to the id when there is no label', () {
      expect(CoreColour.fromJson(const {'id': 'teal'}).label, 'teal');
    });
  });

  group('CorePile', () {
    // GET /api/v1/piles?status=draft — one row.
    const row = {
      'id': '5f1c0b7e-2a8f-4c1e-9c3d-7a2b1e9f0d11',
      'code': 'P00000012',
      'name': 'Peacock florals',
      'photoUrl': 'https://r2.example/piles/P00000012.jpg',
      'mainColourId': 'teal',
      'mainColour': 'Teal',
      'createdStage': 'Print',
      'status': 'draft',
      'thaanCount': 14,
      'baleCodes': ['B00000031', 'B00000032'],
      'createdAt': '2026-09-19T05:35:12.000Z',
      'createdByName': 'API Test',
    };

    test('parses a list row', () {
      final p = CorePile.fromJson(row);
      expect(p.id, '5f1c0b7e-2a8f-4c1e-9c3d-7a2b1e9f0d11');
      expect(p.code, 'P00000012');
      expect(p.name, 'Peacock florals');
      expect(p.photoUrl, 'https://r2.example/piles/P00000012.jpg');
      expect(p.mainColourId, 'teal');
      expect(p.mainColour, 'Teal');
      expect(p.createdStage, 'Print');
      expect(p.status, 'draft');
      expect(p.thaanCount, 14);
      expect(p.baleCodes, ['B00000031', 'B00000032']);
      expect(p.createdAt, '2026-09-19T05:35:12.000Z');
      expect(p.createdByName, 'API Test');
      expect(p.thaans, isEmpty);
      expect(p.events, isEmpty);
    });

    test('parses the detail with its Thaans and events', () {
      // GET /api/v1/piles/:id
      final detail = {
        ...row,
        'thaans': [
          {
            'id': 't-1',
            'code': 'T00002041',
            'baleCode': 'B00000031',
            'voidedAt': null,
            'openStage': 'Nellateeta',
            'completedStages': 4,
          },
          {
            'id': 't-2',
            'code': 'T00002042',
            'baleCode': 'B00000031',
            'voidedAt': '2026-09-20T09:00:00.000Z',
            'openStage': null,
            'completedStages': ['Label Stitching', 'Salava', 'Karakkaya', 'Print', 'Nellateeta'],
          },
        ],
        'events': [
          {
            'id': 'e-1',
            'kind': 'created',
            'stage': 'Print',
            'thaanCode': null,
            'detail': {},
            'actorName': 'API Test',
            'at': '2026-09-19T05:35:12.000Z',
          },
          {
            'id': 'e-2',
            'kind': 'moved',
            'stage': 'Nellateeta',
            'thaanCode': 'T00002041',
            'detail': {'from': 'P00000011'},
            'actorName': 'API Test',
            'at': '2026-09-21T10:12:00.000Z',
          },
        ],
      };
      final p = CorePile.fromJson(detail);

      expect(p.thaans, hasLength(2));
      expect(p.thaans[0].id, 't-1');
      expect(p.thaans[0].code, 'T00002041');
      expect(p.thaans[0].baleCode, 'B00000031');
      expect(p.thaans[0].voidedAt, isNull);
      expect(p.thaans[0].openStage, 'Nellateeta');
      expect(p.thaans[0].completedStages, 4);
      // A list of stage names reads as its count.
      expect(p.thaans[1].completedStages, 5);
      expect(p.thaans[1].voidedAt, isNotNull);
      expect(p.thaans[1].openStage, isNull);

      expect(p.events, hasLength(2));
      expect(p.events[0].kind, 'created');
      expect(p.events[0].stage, 'Print');
      expect(p.events[0].thaanCode, isNull);
      expect(p.events[0].from, isNull);
      expect(p.events[1].kind, 'moved');
      expect(p.events[1].thaanCode, 'T00002041');
      expect(p.events[1].from, 'P00000011');
      expect(p.events[1].actorName, 'API Test');
      expect(p.events[1].at, '2026-09-21T10:12:00.000Z');
    });

    test('survives missing optional fields', () {
      final p = CorePile.fromJson(const {'id': 'x', 'code': 'P1', 'name': 'n', 'status': 'live'});
      expect(p.photoUrl, isNull);
      expect(p.mainColour, isNull);
      expect(p.createdStage, isNull);
      expect(p.thaanCount, 0);
      expect(p.baleCodes, isEmpty);
    });

    // Phase 2 — the record behind the pile, and what is still to fill in.
    test('parses the Phase 2 fields', () {
      final p = CorePile.fromJson({
        ...row,
        'colourwayId': 'cw-7',
        'designCode': 'KC-0412',
        'recordName': 'Peacock florals · Teal',
        'stage': 'Nellateeta',
        'needs': ['motif', 'craft'],
      });
      expect(p.colourwayId, 'cw-7');
      expect(p.designCode, 'KC-0412');
      expect(p.recordName, 'Peacock florals · Teal');
      expect(p.stage, 'Nellateeta');
      expect(p.stageLabel, 'Nellateeta');
      expect(p.needs, ['motif', 'craft']);
      expect(p.recordLabel, 'KC-0412 · Peacock florals · Teal');
    });

    test('a pile with no record yet has null colourway and an empty needs list', () {
      final p = CorePile.fromJson({...row, 'colourwayId': null, 'designCode': null, 'recordName': null, 'needs': []});
      expect(p.colourwayId, isNull);
      expect(p.recordLabel, isNull);
      expect(p.needs, isEmpty);
    });

    test('REGRESSION: a Phase 1 server (no stage, no needs) still parses', () {
      final p = CorePile.fromJson(row);
      expect(p.stage, '');
      expect(p.stageLabel, 'Print'); // falls back to where it was made
      expect(p.needs, isEmpty);
      expect(p.colourwayId, isNull);
      expect(p.recordLabel, isNull);
    });
  });

  group('CorePileDraft', () {
    // GET /api/v1/piles/:id/draft
    const draft = {
      'pileId': '5f1c0b7e-2a8f-4c1e-9c3d-7a2b1e9f0d11',
      'pileCode': 'P00000012',
      'pileName': 'Peacock florals',
      'stage': 'Nellateeta',
      'colourwayId': null,
      'designCode': null,
      'recordName': null,
      'inherited': [
        {'key': 'productType', 'label': 'Product type', 'valueLabel': 'Saree'},
        {'key': 'fibreType', 'label': 'Fibre', 'valueLabel': 'Cotton'},
      ],
      'extra': {'lengthCm': 550, 'widthCm': 112},
      'colourId': 'teal',
      'colourLabel': 'Teal',
      'secondaryColourId': null,
      'secondaryColourLabel': null,
      'fields': [
        {'key': 'motif', 'label': 'Motif', 'list': 'motif', 'valueId': null, 'valueLabel': null, 'required': true},
        {'key': 'craftTechnique', 'label': 'Craft', 'list': 'craft_technique', 'valueId': 'kalamkari', 'valueLabel': 'Kalamkari', 'required': true},
        {'key': 'borderStyle', 'label': 'Border', 'list': 'border_style', 'valueId': null, 'valueLabel': null, 'required': false},
      ],
      'needs': ['motif'],
    };

    test('parses the draft', () {
      final d = CorePileDraft.fromJson(draft);
      expect(d.pileId, '5f1c0b7e-2a8f-4c1e-9c3d-7a2b1e9f0d11');
      expect(d.pileCode, 'P00000012');
      expect(d.pileName, 'Peacock florals');
      expect(d.stage, 'Nellateeta');
      expect(d.colourwayId, isNull);
      expect(d.inherited, hasLength(2));
      expect(d.inherited[0].key, 'productType');
      expect(d.inherited[0].label, 'Product type');
      expect(d.inherited[0].valueLabel, 'Saree');
      expect(d.lengthCm, 550);
      expect(d.widthCm, 112);
      expect(d.sareeSize, '550 × 112 cm');
      expect(d.colourId, 'teal');
      expect(d.colourLabel, 'Teal');
      expect(d.secondaryColourId, isNull);
      expect(d.fields, hasLength(3));
      expect(d.fields[0].key, 'motif');
      expect(d.fields[0].list, 'motif');
      expect(d.fields[0].valueId, isNull);
      expect(d.fields[0].required, isTrue);
      expect(d.fields[1].key, 'craftTechnique');
      expect(d.fields[1].list, 'craft_technique');
      expect(d.fields[1].valueId, 'kalamkari');
      expect(d.fields[1].valueLabel, 'Kalamkari');
      expect(d.fields[2].required, isFalse);
      expect(d.needs, ['motif']);
    });

    test('a size given as decimals or strings still reads cleanly', () {
      final d = CorePileDraft.fromJson({...draft, 'extra': {'lengthCm': 550.0, 'widthCm': '112.5'}});
      expect(d.sareeSize, '550 × 112.5 cm');
    });

    test('no extra, no inherited, no fields — still a draft', () {
      final d = CorePileDraft.fromJson(const {'pileId': 'x', 'pileCode': 'P1', 'pileName': 'n', 'stage': 'Print'});
      expect(d.sareeSize, isNull);
      expect(d.inherited, isEmpty);
      expect(d.fields, isEmpty);
      expect(d.needs, isEmpty);
      expect(d.colourId, isNull);
    });
  });

  group('CoreThaanForReceive', () {
    // POST /api/v1/handovers/lookup-receive — `thaan`, with the pile fields.
    const thaan = {
      'id': 'a3c9e1f0-1b2c-4d5e-8f90-1234567890ab',
      'code': 'T00002041',
      'baleCode': 'B00000031',
      'baleType': 'Saree',
      'itemName': 'Kalamkari cotton',
      'stage': 'Nellateeta',
      'throughStage': null,
      'vendorId': 'v-1',
      'vendorName': 'Ravi',
      'pileId': 'p-1',
      'pileCode': 'P00000011',
      'pileName': 'Mango leaves',
      'canPile': true,
    };

    test('parses the pile fields', () {
      final t = CoreThaanForReceive.fromJson(thaan);
      expect(t.pileId, 'p-1');
      expect(t.pileCode, 'P00000011');
      expect(t.pileName, 'Mango leaves');
      expect(t.canPile, isTrue);
    });

    test('REGRESSION: a server without piles still parses, and cannot pile', () {
      final stale = Map<String, dynamic>.from(thaan)
        ..remove('pileId')
        ..remove('pileCode')
        ..remove('pileName')
        ..remove('canPile');
      final t = CoreThaanForReceive.fromJson(stale);
      expect(t.pileId, isNull);
      expect(t.pileName, isNull);
      expect(t.canPile, isFalse);
    });

    test('a Thaan not yet back from Print has no pile and cannot pile', () {
      final t = CoreThaanForReceive.fromJson({
        ...thaan,
        'stage': 'Salava',
        'pileId': null,
        'pileCode': null,
        'pileName': null,
        'canPile': false,
      });
      expect(t.pileId, isNull);
      expect(t.canPile, isFalse);
    });
  });

  group('CoreThaan', () {
    // GET /api/v1/thaans/lookup?code=… — the fields the pile rows read.
    const lookup = {
      'id': 'a3c9e1f0-1b2c-4d5e-8f90-1234567890ab',
      'code': 'T00002041',
      'baleCode': 'B00000031',
      'supplierName': 'Sri Textiles',
      'itemName': 'Kalamkari cotton',
      'baleType': 'Saree',
      'billEntryDate': '12 Sep 2026',
      'perThaanMetres': 6.5,
      'metresReceived': 130,
      'uom': 'm',
      'needsSecondPrint': false,
      'baleCount': 1,
      'baleStatus': 'cut',
      'pipelineStatus': 'Ready for Nellateeta',
      'qrGeneratedAt': '14 Sep 2026, 05:35 AM',
      'voidedAt': null,
      'lastVendorId': 'v-1',
      'lastVendorName': 'Ravi',
      'lastStage': 'Print',
      'pileId': 'p-1',
      'pileCode': 'P00000011',
      'pileName': 'Mango leaves',
    };

    test('parses the id and pile fields', () {
      final t = CoreThaan.fromJson(lookup);
      expect(t.id, 'a3c9e1f0-1b2c-4d5e-8f90-1234567890ab');
      expect(t.pileId, 'p-1');
      expect(t.pileCode, 'P00000011');
      expect(t.pileName, 'Mango leaves');
    });

    test('REGRESSION: a server without piles still parses', () {
      final stale = Map<String, dynamic>.from(lookup)
        ..remove('id')
        ..remove('pileId')
        ..remove('pileCode')
        ..remove('pileName');
      final t = CoreThaan.fromJson(stale);
      expect(t.id, isNull);
      expect(t.pileId, isNull);
      expect(t.pileName, isNull);
      expect(t.code, 'T00002041');
    });
  });
}
