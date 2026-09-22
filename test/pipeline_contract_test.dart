import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/handovers/handover_providers.dart';
import 'package:slk_mobile/models/core.dart';

/// The production-pipeline contract with slk-core, pinned — same rule as
/// core_contract_test.dart: if one of these fails, the API changed. Fix the
/// model to match the API, never the fixture to match the model.
void main() {
  group('CoreRecordRow', () {
    // GET /api/v1/records — one row, with the pipeline counts.
    const row = {
      'id': 'cw-7',
      'code': 'KC-0412',
      'name': 'Peacock florals · Teal',
      'colour': 'Teal',
      'colourHex': '#008080',
      'productType': 'Saree',
      'quantity': 0,
      'pieces': 0,
      'isSerialised': true,
      'priceMinor': null,
      'sold': 0,
      'syncStatus': 'none',
      'thaanCount': 6,
      'finishedCount': 2,
      'shelvedCount': 1,
      'stage': 'Nellateeta',
      'needs': ['craft'],
    };

    test('parses the pipeline fields', () {
      final r = CoreRecordRow.fromJson(row);
      expect(r.thaanCount, 6);
      expect(r.finishedCount, 2);
      expect(r.shelvedCount, 1);
      expect(r.stage, 'Nellateeta');
      expect(r.needs, ['craft']);
      expect(r.pipeline.inPipeline, 3);
      expect(r.pipeline.line, '6 Thaans · Nellateeta · needs craft');
    });

    test('a record with no Thaans has no pipeline line', () {
      final r = CoreRecordRow.fromJson({...row, 'thaanCount': 0, 'finishedCount': 0, 'shelvedCount': 0, 'stage': null, 'needs': []});
      expect(r.pipeline.line, isNull);
    });

    test('REGRESSION: a server without the pipeline fields still parses', () {
      final stale = Map<String, dynamic>.from(row)
        ..remove('thaanCount')
        ..remove('finishedCount')
        ..remove('shelvedCount')
        ..remove('stage')
        ..remove('needs');
      final r = CoreRecordRow.fromJson(stale);
      expect(r.thaanCount, 0);
      expect(r.finishedCount, 0);
      expect(r.shelvedCount, 0);
      expect(r.stage, isNull);
      expect(r.needs, isEmpty);
      expect(r.pipeline.line, isNull);
      expect(r.name, 'Peacock florals · Teal');
    });
  });

  group('CoreRecordDetail', () {
    // GET /api/v1/records/:id — the fields this test cares about.
    const detail = {
      'id': 'cw-7',
      'designId': 'd-1',
      'code': 'KC-0412',
      'name': 'Peacock florals · Teal',
      'nameIsCustom': false,
      'isSerialised': true,
      'attributes': {'motif': 'm-peacock'},
      'siblings': [],
      'stock': {'onHand': 0, 'received': 0, 'sold': 0, 'damaged': 0, 'returned': 0, 'adjusted': 0, 'byLocation': []},
      'consignments': [],
      'images': [],
      'descriptors': [],
      'movements': [],
      'pipeline': {
        'thaanCount': 6,
        'finishedCount': 2,
        'shelvedCount': 1,
        'stage': 'Nellateeta',
        'needs': ['craft', 'border'],
      },
    };

    test('parses the pipeline block', () {
      final d = CoreRecordDetail.fromJson(detail);
      expect(d.pipeline.thaanCount, 6);
      expect(d.pipeline.finishedCount, 2);
      expect(d.pipeline.shelvedCount, 1);
      expect(d.pipeline.inPipeline, 3);
      expect(d.pipeline.stage, 'Nellateeta');
      expect(d.pipeline.needs, ['craft', 'border']);
    });

    test('REGRESSION: a server without `pipeline` reads as no Thaans', () {
      final stale = Map<String, dynamic>.from(detail)..remove('pipeline');
      final d = CoreRecordDetail.fromJson(stale);
      expect(d.pipeline.thaanCount, 0);
      expect(d.pipeline.finishedCount, 0);
      expect(d.pipeline.shelvedCount, 0);
      expect(d.pipeline.stage, isNull);
      expect(d.pipeline.needs, isEmpty);
      expect(d.code, 'KC-0412');
    });

    test('a null `pipeline` is the same as none', () {
      final d = CoreRecordDetail.fromJson({...detail, 'pipeline': null});
      expect(d.pipeline.thaanCount, 0);
    });
  });

  group('CorePipelineRecord', () {
    // GET /api/v1/records/pipeline?status=in_pipeline — one row.
    const row = {
      'id': 'cw-7',
      'code': 'KC-0412',
      'name': 'Peacock florals · Teal',
      'colour': 'Teal',
      'colourHex': '#008080',
      'motif': 'Peacock',
      'motifCategory': 'Birds',
      'thaanCount': 6,
      'finishedCount': 0,
      'shelvedCount': 0,
      'stage': 'Print',
      'needs': ['craft'],
    };

    test('parses a row', () {
      final r = CorePipelineRecord.fromJson(row);
      expect(r.id, 'cw-7');
      expect(r.code, 'KC-0412');
      expect(r.name, 'Peacock florals · Teal');
      expect(r.colour, 'Teal');
      expect(r.motif, 'Peacock');
      expect(r.motifCategory, 'Birds');
      expect(r.thaanCount, 6);
      expect(r.stage, 'Print');
      expect(r.needs, ['craft']);
      expect(r.swatch, isNotNull);
      expect(r.summary, 'KC-0412 · Teal · Peacock · 6 Thaans');
    });

    test('is searchable by code, name, colour and motif', () {
      final r = CorePipelineRecord.fromJson(row);
      expect(r.haystack, contains('kc-0412'));
      expect(r.haystack, contains('peacock'));
      expect(r.haystack, contains('teal'));
      expect(r.haystack, contains('birds'));
    });

    test('survives missing optional fields', () {
      final r = CorePipelineRecord.fromJson(const {'id': 'x', 'code': 'C', 'name': 'n'});
      expect(r.colour, isNull);
      expect(r.motif, isNull);
      expect(r.thaanCount, 0);
      expect(r.needs, isEmpty);
      expect(r.swatch, isNull);
      expect(r.summary, 'C · 0 Thaans');
    });
  });

  group('CorePipelineThaan', () {
    // GET /api/v1/records/:id/thaans
    test('parses a Thaan still in the pipeline', () {
      final t = CorePipelineThaan.fromJson(const {
        'id': 't-1',
        'code': 'T00002041',
        'baleCode': 'B00000031',
        'voidedAt': null,
        'openStage': 'Nellateeta',
        'completedStages': 4,
        'pieceCode': null,
        'locationName': null,
        'isHeld': false,
      });
      expect(t.id, 't-1');
      expect(t.code, 'T00002041');
      expect(t.baleCode, 'B00000031');
      expect(t.voidedAt, isNull);
      expect(t.openStage, 'Nellateeta');
      expect(t.completedStages, 4);
      expect(t.pieceCode, isNull);
      expect(t.isHeld, isFalse);
      expect(t.where, 'Out for Nellateeta');
    });

    test('parses a shelved Thaan with its piece and location', () {
      final t = CorePipelineThaan.fromJson(const {
        'id': 't-2',
        'code': 'T00002042',
        'baleCode': 'B00000031',
        'voidedAt': null,
        'openStage': null,
        'completedStages': ['Label Stitching', 'Salava', 'Karakkaya', 'Print', 'Nellateeta', 'Udukulu', 'Ironing'],
        'pieceCode': 'T00002042',
        'locationName': 'Shop',
        'isHeld': true,
      });
      // A list of stage names reads as its count.
      expect(t.completedStages, 7);
      expect(t.pieceCode, 'T00002042');
      expect(t.locationName, 'Shop');
      expect(t.isHeld, isTrue);
      expect(t.where, '7 stages done');
    });

    test('survives a bare row', () {
      final t = CorePipelineThaan.fromJson(const {'id': 'x', 'code': 'T1'});
      expect(t.completedStages, 0);
      expect(t.isHeld, isFalse);
      expect(t.where, '0 stages done');
    });
  });

  group('CoreRecordFill', () {
    // GET /api/v1/records/:id/fill
    const fill = {
      'colourwayId': 'cw-7',
      'designCode': 'KC-0412',
      'recordName': 'Peacock florals',
      'stage': 'Nellateeta',
      'thaanCount': 6,
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
        {'key': 'motif', 'label': 'Motif', 'list': 'motif', 'valueId': 'm-peacock', 'valueLabel': 'Peacock', 'required': true},
        {'key': 'craftTechnique', 'label': 'Craft', 'list': 'craft_technique', 'valueId': null, 'valueLabel': null, 'required': true},
        {'key': 'borderStyle', 'label': 'Border', 'list': 'border_style', 'valueId': null, 'valueLabel': null, 'required': false},
      ],
      'needs': ['craft'],
    };

    test('parses the draft', () {
      final d = CoreRecordFill.fromJson(fill);
      expect(d.colourwayId, 'cw-7');
      expect(d.designCode, 'KC-0412');
      expect(d.recordName, 'Peacock florals');
      expect(d.recordLabel, 'KC-0412 · Peacock florals');
      expect(d.stage, 'Nellateeta');
      expect(d.thaanCount, 6);
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
      expect(d.fields[0].valueId, 'm-peacock');
      expect(d.fields[0].valueLabel, 'Peacock');
      expect(d.fields[0].required, isTrue);
      expect(d.fields[1].valueId, isNull);
      expect(d.fields[2].required, isFalse);
      expect(d.needs, ['craft']);
    });

    test('a size given as decimals or strings still reads cleanly', () {
      final d = CoreRecordFill.fromJson({...fill, 'extra': {'lengthCm': 550.0, 'widthCm': '112.5'}});
      expect(d.sareeSize, '550 × 112.5 cm');
    });

    test('no extra, no inherited, no fields — still a draft', () {
      final d = CoreRecordFill.fromJson(const {'colourwayId': 'x'});
      expect(d.recordLabel, isNull);
      expect(d.sareeSize, isNull);
      expect(d.inherited, isEmpty);
      expect(d.fields, isEmpty);
      expect(d.needs, isEmpty);
      expect(d.colourId, isNull);
      expect(d.stage, '');
      expect(d.thaanCount, 0);
    });
  });

  group('CoreRecordShelf', () {
    // GET /api/v1/records/:id/shelf
    const shelf = {
      'colourwayId': 'cw-7',
      'designCode': 'KC-0412',
      'recordName': 'Peacock florals · Teal',
      'pieceTracked': true,
      'finished': [
        {'id': 't-1', 'code': 'T00002041'},
        {'id': 't-2', 'code': 'T00002042'},
      ],
      'shelved': [
        {'id': 't-0', 'code': 'T00002040'},
      ],
      'inPipeline': 3,
      'prices': {'cost': '', 'making': '', 'wholesale': '', 'retail': '2850', 'mrp': '3200'},
      'locations': [
        {'id': 'loc-1', 'name': 'Shop', 'code': 'SHOP'},
        {'id': 'loc-2', 'name': 'Godown', 'code': 'GDN'},
      ],
      'needs': ['border'],
      'blockers': [],
    };

    test('parses the draft', () {
      final d = CoreRecordShelf.fromJson(shelf);
      expect(d.colourwayId, 'cw-7');
      expect(d.designCode, 'KC-0412');
      expect(d.recordName, 'Peacock florals · Teal');
      expect(d.recordLabel, 'KC-0412 · Peacock florals · Teal');
      expect(d.pieceTracked, isTrue);
      expect(d.finished, hasLength(2));
      expect(d.finished[0].id, 't-1');
      expect(d.finished[0].code, 'T00002041');
      expect(d.shelved, hasLength(1));
      expect(d.shelved[0].code, 'T00002040');
      expect(d.inPipeline, 3);
      expect(d.prices.retail, '2850');
      expect(d.prices.mrp, '3200');
      expect(d.prices.cost, '');
      expect(d.locations, hasLength(2));
      expect(d.locations[0].id, 'loc-1');
      expect(d.locations[0].name, 'Shop');
      expect(d.locations[0].code, 'SHOP');
      expect(d.needs, ['border']);
      expect(d.blockers, isEmpty);
    });

    test("blockers come through in the server's words", () {
      final d = CoreRecordShelf.fromJson({
        ...shelf,
        'finished': [],
        'blockers': ['Nothing is back from Ironing yet', 'The record still needs a motif'],
      });
      expect(d.finished, isEmpty);
      expect(d.blockers, hasLength(2));
      expect(d.blockers[0], 'Nothing is back from Ironing yet');
    });

    test('prices go up in the same shape they came down', () {
      const p = CoreShelfPrices(retail: '2850', mrp: '3200');
      expect(p.toJson(), {'cost': '', 'making': '', 'wholesale': '', 'retail': '2850', 'mrp': '3200'});
      expect(CoreShelfPrices.fromJson(p.toJson()).retail, '2850');
    });

    test('a bare draft — no lists, no prices, no needs — still parses', () {
      final d = CoreRecordShelf.fromJson(const {'colourwayId': 'x'});
      expect(d.recordLabel, isNull);
      expect(d.pieceTracked, isFalse);
      expect(d.finished, isEmpty);
      expect(d.shelved, isEmpty);
      expect(d.inPipeline, 0);
      expect(d.prices.retail, '');
      expect(d.locations, isEmpty);
      expect(d.needs, isEmpty);
      expect(d.blockers, isEmpty);
    });
  });

  group('CoreThaanForReceive', () {
    // POST /api/v1/handovers/lookup-receive — `thaan`, with the record fields.
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
      'colourwayId': 'cw-7',
      'recordCode': 'KC-0412',
      'recordName': 'Peacock florals',
      'recordColour': 'Teal',
      'canRecord': true,
    };

    test('parses the record fields', () {
      final t = CoreThaanForReceive.fromJson(thaan);
      expect(t.colourwayId, 'cw-7');
      expect(t.recordCode, 'KC-0412');
      expect(t.recordName, 'Peacock florals');
      expect(t.recordColour, 'Teal');
      expect(t.canRecord, isTrue);
      expect(t.recordLabel, 'KC-0412 · Peacock florals · Teal');
    });

    test('REGRESSION: a server without the record fields still parses, and cannot sort', () {
      final stale = Map<String, dynamic>.from(thaan)
        ..remove('colourwayId')
        ..remove('recordCode')
        ..remove('recordName')
        ..remove('recordColour')
        ..remove('canRecord');
      final t = CoreThaanForReceive.fromJson(stale);
      expect(t.colourwayId, isNull);
      expect(t.recordName, isNull);
      expect(t.recordLabel, isNull);
      expect(t.canRecord, isFalse);
      expect(t.code, 'T00002041');
    });

    test('a Thaan not yet back from Print has no record and cannot be sorted', () {
      final t = CoreThaanForReceive.fromJson({
        ...thaan,
        'stage': 'Salava',
        'colourwayId': null,
        'recordCode': null,
        'recordName': null,
        'recordColour': null,
        'canRecord': false,
      });
      expect(t.colourwayId, isNull);
      expect(t.recordLabel, isNull);
      expect(t.canRecord, isFalse);
    });
  });

  group('CoreThaan', () {
    // GET /api/v1/thaans/lookup?code=… — the record and stock fields.
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
      'pipelineStatus': 'Finished',
      'qrGeneratedAt': '14 Sep 2026, 05:35 AM',
      'voidedAt': null,
      'lastVendorId': 'v-1',
      'lastVendorName': 'Ravi',
      'lastStage': 'Ironing',
      'colourwayId': 'cw-7',
      'recordCode': 'KC-0412',
      'recordName': 'Peacock florals',
      'recordColour': 'Teal',
      'pieceCode': 'T00002041',
      'productCode': '300032',
      'locationName': 'Shop',
      'isHeld': true,
      'priceMinor': 285000,
      'stockStatus': 'On shelf',
    };

    test('parses the record and stock fields', () {
      final t = CoreThaan.fromJson(lookup);
      expect(t.id, 'a3c9e1f0-1b2c-4d5e-8f90-1234567890ab');
      expect(t.colourwayId, 'cw-7');
      expect(t.recordCode, 'KC-0412');
      expect(t.recordName, 'Peacock florals');
      expect(t.recordColour, 'Teal');
      expect(t.recordLabel, 'KC-0412 · Peacock florals · Teal');
      expect(t.pieceCode, 'T00002041');
      expect(t.productCode, '300032');
      expect(t.locationName, 'Shop');
      expect(t.isHeld, isTrue);
      expect(t.priceMinor, 285000);
      expect(t.price, '₹2,850');
      expect(t.stockStatus, 'On shelf');
    });

    test('a Thaan still in the pipeline has no piece, no location, no held flag', () {
      final t = CoreThaan.fromJson({
        ...lookup,
        'pieceCode': null,
        'productCode': null,
        'locationName': null,
        'isHeld': null,
        'priceMinor': null,
        'stockStatus': 'In pipeline',
      });
      expect(t.pieceCode, isNull);
      expect(t.isHeld, isNull);
      expect(t.priceMinor, isNull);
      expect(t.stockStatus, 'In pipeline');
    });

    test('REGRESSION: a server without the record and stock fields still parses', () {
      final stale = Map<String, dynamic>.from(lookup)
        ..remove('id')
        ..remove('colourwayId')
        ..remove('recordCode')
        ..remove('recordName')
        ..remove('recordColour')
        ..remove('pieceCode')
        ..remove('productCode')
        ..remove('locationName')
        ..remove('isHeld')
        ..remove('priceMinor')
        ..remove('stockStatus');
      final t = CoreThaan.fromJson(stale);
      expect(t.id, isNull);
      expect(t.colourwayId, isNull);
      expect(t.recordLabel, isNull);
      expect(t.pieceCode, isNull);
      expect(t.isHeld, isNull);
      expect(t.stockStatus, isNull);
      expect(t.code, 'T00002041');
    });
  });

  group('ReceiveRecordSpec', () {
    // POST /api/v1/handovers/receive — one entry of `records`.
    test('an existing record goes up by colourway id', () {
      const spec = ReceiveRecordSpec(colourwayId: 'cw-7', thaanIds: ['t-1', 't-2']);
      expect(spec.toJson(), {
        'colourwayId': 'cw-7',
        'newRecord': null,
        'thaanIds': ['t-1', 't-2'],
      });
    });

    test('a new record goes up with its colour, motif category and motif', () {
      const spec = ReceiveRecordSpec(
        newRecord: (colourId: 'red', secondaryColourId: 'gold', motifCategoryId: 'birds', motifId: 'peacock'),
        thaanIds: ['t-1'],
      );
      expect(spec.toJson(), {
        'colourwayId': null,
        'newRecord': {
          'colourId': 'red',
          'secondaryColourId': 'gold',
          'motifCategoryId': 'birds',
          'motifId': 'peacock',
        },
        'thaanIds': ['t-1'],
      });
    });

    test('a new record without a secondary colour sends null for it', () {
      const spec = ReceiveRecordSpec(
        newRecord: (colourId: 'red', secondaryColourId: null, motifCategoryId: 'birds', motifId: 'peacock'),
        thaanIds: ['t-1'],
      );
      expect((spec.toJson()['newRecord'] as Map)['secondaryColourId'], isNull);
    });
  });
}
