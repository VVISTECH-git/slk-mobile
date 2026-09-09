import 'dart:convert';

import 'package:flutter/material.dart';

/// The shapes slk-core's Inventory API speaks in.
///
/// Deliberately a subset. slk-core's record carries thirty-four taxonomy
/// attributes; this app reads the handful the floor answers and passes the
/// rest through untouched. Modelling all of them here would mean editing this
/// file every time the vocabulary grows a question.

// ── Shared conversions ──────────────────────────────────────────────────────

/// A vocabulary hex — "#F0F8FF" — as a colour, or null if it is not one.
Color? _swatchOf(String? hex) {
  if (hex == null) return null;

  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return null;

  final parsed = int.tryParse(cleaned, radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}

/// A number, whatever shape it arrived in.
///
/// Postgres hands `bigint` back as a string, so the price columns reached this
/// app as "349999" while the API's own type said `number`. That is fixed at
/// the source now — but a phone cannot be redeployed the way a server can, and
/// a screen that refuses to open because a field changed shape is a worse
/// failure than a price that reads oddly for an afternoon.
int? _intOf(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt();
  return null;
}

/// "₹2,850" — grouped the Indian way, which is what a price looks like here.
String _rupees(int? minor) {
  if (minor == null) return '—';

  final rupees = (minor / 100).round().toString();

  // 12,34,567 rather than 1,234,567: last three, then twos.
  if (rupees.length <= 3) return '₹$rupees';

  final head = rupees.substring(0, rupees.length - 3);
  final tail = rupees.substring(rupees.length - 3);

  return '₹${head.replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},')},$tail';
}

/// Who is signed in to slk-core.
class CoreActor {
  const CoreActor({
    required this.id,
    required this.code,
    required this.name,
    required this.role,
  });

  final String id;
  final String code;
  final String name;

  /// floor · office · owner. The API enforces it; this is for showing.
  ///
  /// No client-side gate on creating or editing a record: every signed-in
  /// actor may, floor included, because whoever is holding the delivery is
  /// who enters it and who is best placed to correct their own typo. The API
  /// is still the one deciding — a 403 is what to check, not a rule copied
  /// here.
  final String role;

  factory CoreActor.fromJson(Map<String, dynamic> json) => CoreActor(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'code': code, 'name': name, 'role': role};

  String encode() => jsonEncode(toJson());

  static CoreActor decode(String raw) =>
      CoreActor.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
}

/// One value in the controlled vocabulary.
class CoreOption {
  const CoreOption({
    required this.id,
    required this.label,
    this.parentId,
    this.soldById,
    this.hex,
    this.isDefault = false,
  });

  final String id;
  final String label;

  /// The value this one sits under. Product Type parents to Industry, Textile
  /// Material to Fibre — which is what lets a list narrow as answers arrive.
  final String? parentId;

  /// How a product type is measured. Only product types carry one, and it is
  /// shown rather than asked: a saree is sold by the Piece, fabric by the
  /// Metre, and a record where those disagreed would be priced per nothing.
  final String? soldById;

  /// A real colour from the vocabulary, not a guess from the name.
  final String? hex;

  final bool isDefault;

  Color? get swatch => _swatchOf(hex);

  factory CoreOption.fromJson(Map<String, dynamic> json) => CoreOption(
        id: json['id'] as String,
        label: json['label'] as String,
        parentId: json['parentId'] as String?,
        soldById: json['soldById'] as String?,
        hex: json['hex'] as String?,
        isDefault: json['isDefault'] == true,
      );
}

/// Every list, by list code — `industry`, `colour`, `fibre_type` and so on.
typedef CoreOptions = Map<String, List<CoreOption>>;

CoreOptions parseCoreOptions(Map<String, dynamic> json) {
  final out = <String, List<CoreOption>>{};

  for (final entry in json.entries) {
    out[entry.key] = [
      for (final value in (entry.value as List))
        CoreOption.fromJson((value as Map).cast<String, dynamic>()),
    ];
  }

  return out;
}

/// One row of the catalogue, as the list screen needs it.
///
/// A deliberate subset of what `GET /records` returns — that answer carries
/// every attribute so the web's Columns menu can offer them, and a phone shows
/// six. The rest are ignored rather than modelled: a field this app never
/// draws is a field that cannot break it.
class CoreRecordRow {
  const CoreRecordRow({
    required this.id,
    required this.code,
    required this.name,
    this.colour,
    this.colourHex,
    this.productType,
    this.fibreType,
    this.craftTechnique,
    this.uom,
    this.productCode,
    required this.quantity,
    required this.pieces,
    required this.isSerialised,
    this.priceMinor,
    required this.sold,
    required this.syncStatus,
  });

  final String id;

  /// The design code — SAR-SRI-SIL-0001. Internal, and it repeats.
  ///
  /// Not what is on the label: a QR carries the item code or the product
  /// code. This is here to be searched on, not to be led with — see
  /// [productCode], which is the number anybody on the floor is holding.
  final String code;
  final String name;

  final String? colour;
  final String? colourHex;
  final String? productType;
  final String? fibreType;
  final String? craftTechnique;

  /// Piece or Metre. What the price and the count are *of*.
  final String? uom;

  /// The newest consignment — 300001 and up. Null until one has arrived.
  final String? productCode;

  /// On hand, derived from the ledger. Never stored.
  final int quantity;

  /// How many physical pieces carry their own QR. Zero for unserialised stock.
  final int pieces;

  final bool isSerialised;

  /// Retail, in paise. Null means unpriced, which is not the same as free.
  final int? priceMinor;

  /// Every "sold" movement against this colourway, summed from the ledger —
  /// not a count Shopify itself is asked for.
  final int sold;

  /// Whether the newest consignment is listed on Shopify — the same
  /// per-batch fact the Publish tab shows for one record at a time, echoed
  /// here so the list doesn't hide it behind a tap.
  final CoreSyncStatus syncStatus;

  Color? get swatch => _swatchOf(colourHex);

  String get price => _rupees(priceMinor);

  /// Everything somebody might type to find this row.
  String get haystack => [
        code,
        name,
        colour ?? '',
        productType ?? '',
        fibreType ?? '',
        craftTechnique ?? '',
        productCode ?? '',
      ].join(' ').toLowerCase();

  factory CoreRecordRow.fromJson(Map<String, dynamic> json) => CoreRecordRow(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        colour: json['colour'] as String?,
        colourHex: json['colourHex'] as String?,
        productType: json['productType'] as String?,
        fibreType: json['fibreType'] as String?,
        craftTechnique: json['craftTechnique'] as String?,
        uom: json['uom'] as String?,
        productCode: json['productCode'] as String?,
        quantity: _intOf(json['quantity']) ?? 0,
        pieces: _intOf(json['pieces']) ?? 0,
        isSerialised: json['isSerialised'] == true,
        priceMinor: _intOf(json['priceMinor']),
        sold: _intOf(json['sold']) ?? 0,
        syncStatus: CoreSyncStatus.fromJson(json['syncStatus'] as String?),
      );
}

/// Whether a record's newest consignment is listed on Shopify.
///
/// [fromJson] falls back to [none] for anything it doesn't recognise —
/// server and client vocabularies for this need not release in lockstep,
/// and an unfamiliar status should read as "nothing to report" rather than
/// crash the list that shows it.
enum CoreSyncStatus {
  /// Nobody has ever tried to publish this consignment, on any channel.
  none,

  /// Tried on some channels but not all.
  pending,

  /// Listed everywhere it has been tried, with nothing outstanding.
  synced,

  /// The most recent attempt on at least one channel failed.
  error;

  factory CoreSyncStatus.fromJson(String? value) => switch (value) {
        'pending' => CoreSyncStatus.pending,
        'synced' => CoreSyncStatus.synced,
        'error' => CoreSyncStatus.error,
        _ => CoreSyncStatus.none,
      };
}

/// A record with photographs still to take.
class CoreShotListRow {
  const CoreShotListRow({
    required this.id,
    required this.name,
    required this.designCode,
    required this.pending,
    this.productCode,
    this.colour,
    this.colourHex,
  });

  final String id;
  final String name;
  final String designCode;

  /// The slots still empty, by name — "Pallu", "Border".
  final List<String> pending;

  final String? productCode;
  final String? colour;
  final String? colourHex;

  Color? get swatch => _swatchOf(colourHex);

  String get haystack =>
      [designCode, name, colour ?? '', productCode ?? '', ...pending]
          .join(' ')
          .toLowerCase();

  factory CoreShotListRow.fromJson(Map<String, dynamic> json) =>
      CoreShotListRow(
        id: json['id'] as String,
        name: json['name'] as String,
        designCode: json['designCode'] as String,
        pending: [
          for (final s in (json['pending'] as List? ?? const [])) '$s',
        ],
        productCode: json['productCode'] as String?,
        colour: json['colour'] as String?,
        colourHex: json['colourHex'] as String?,
      );
}

/// One physical saree, as a scan answers for it.
class CorePiece {
  const CorePiece({
    required this.id,
    required this.itemCode,
    required this.designCode,
    required this.name,
    required this.isHeld,
    this.productCode,
    this.colour,
    this.productType,
    this.location,
    this.receivedInto,
    this.receivedAt,
    this.reference,
    this.priceMinor,
  });

  final String id;

  /// 500001 and up. On the label stuck to this saree.
  final String itemCode;
  final String designCode;
  final String name;

  /// Whether we still hold it. False once the ledger says it has been sold,
  /// written off or sent on — which is the first thing a scan should answer.
  final bool isHeld;

  /// 300001 and up. Shared with everything in the same consignment.
  final String? productCode;

  final String? colour;
  final String? productType;

  /// Where the ledger says it is now, not where it arrived. Null once gone.
  final String? location;

  /// Where the consignment came in, which never changes.
  final String? receivedInto;
  final String? receivedAt;
  final String? reference;

  final int? priceMinor;

  String get price => _rupees(priceMinor);

  factory CorePiece.fromJson(Map<String, dynamic> json) => CorePiece(
        id: json['id'] as String,
        itemCode: json['itemCode'] as String,
        designCode: json['designCode'] as String,
        name: json['name'] as String,
        isHeld: json['isHeld'] == true,
        productCode: json['productCode'] as String?,
        colour: json['colour'] as String?,
        productType: json['productType'] as String?,
        location: json['location'] as String?,
        receivedInto: json['receivedInto'] as String?,
        receivedAt: json['receivedAt'] as String?,
        reference: json['reference'] as String?,
        priceMinor: _intOf(json['priceMinor']),
      );
}

/// Somewhere stock can be counted in.
class CoreLocation {
  const CoreLocation({
    required this.id,
    required this.code,
    required this.name,
    required this.isInternal,
  });

  final String id;
  final String code;
  final String name;

  /// Stock we own sits in internal locations. Production, Customer and Scrap
  /// are external — which is what makes "how many do we have" one sum.
  final bool isInternal;

  factory CoreLocation.fromJson(Map<String, dynamic> json) => CoreLocation(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        isInternal: json['isInternal'] == true,
      );
}

/// An internal location that currently holds stock of a reservation's
/// colourway, and how much — precomputed server-side so packing doesn't need
/// a second request to ask where.
class CoreHoldingLocation {
  const CoreHoldingLocation({
    required this.id,
    required this.name,
    required this.qty,
  });

  final String id;
  final String name;
  final int qty;

  factory CoreHoldingLocation.fromJson(Map<String, dynamic> json) =>
      CoreHoldingLocation(
        id: json['id'] as String,
        name: json['name'] as String,
        qty: _intOf(json['qty']) ?? 0,
      );
}

/// An order Shopify has already reserved but nobody has packed yet.
///
/// Reserving and packing are different acts, deliberately: nothing physical
/// happens when an order arrives, so nothing is written to the ledger until
/// somebody here says the piece has actually left.
class CoreReservation {
  const CoreReservation({
    required this.id,
    required this.channelName,
    required this.productCode,
    required this.designName,
    required this.qty,
    required this.createdAt,
    required this.holding,
    this.colour,
    this.externalOrderName,
  });

  final String id;
  final String channelName;
  final String productCode;
  final String designName;
  final String? colour;
  final int qty;

  /// For a human reading the list — never used as a key.
  final String? externalOrderName;
  final String createdAt;
  final List<CoreHoldingLocation> holding;

  factory CoreReservation.fromJson(Map<String, dynamic> json) =>
      CoreReservation(
        id: json['id'] as String,
        channelName: json['channelName'] as String? ?? '',
        productCode: json['productCode'] as String? ?? '',
        designName: json['designName'] as String? ?? '',
        colour: json['colour'] as String?,
        qty: _intOf(json['qty']) ?? 0,
        externalOrderName: json['externalOrderName'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        holding: [
          for (final h in (json['holding'] as List? ?? const []))
            CoreHoldingLocation.fromJson((h as Map).cast<String, dynamic>()),
        ],
      );
}

/// A record, whole — everything the editor needs, ported field for field from
/// `RecordDetail` on the server rather than trimmed to a subset.
///
/// `CoreRecordRow` is deliberately a subset because the catalogue is a list of
/// a hundred and fifty of these; this is the one somebody is looking at, and
/// an editor that cannot show a field cannot let anyone correct it.
class CoreRecordDetail {
  const CoreRecordDetail({
    required this.id,
    required this.designId,
    required this.code,
    required this.name,
    required this.nameIsCustom,
    required this.isSerialised,
    this.notes,
    this.colourId,
    this.secondaryColourId,
    this.costMinor,
    this.makingMinor,
    this.wholesaleMinor,
    this.retailMinor,
    this.mrpMinor,
    required this.attributes,
    required this.siblings,
    required this.stock,
    required this.consignments,
    required this.images,
    required this.descriptors,
    required this.movements,
  });

  final String id;
  final String designId;

  /// The design code — SAR-SRI-SIL-0001. See [CoreRecordRow.code].
  final String code;
  final String name;
  final bool nameIsCustom;
  final bool isSerialised;
  final String? notes;

  final String? colourId;
  final String? secondaryColourId;

  final int? costMinor;
  final int? makingMinor;
  final int? wholesaleMinor;
  final int? retailMinor;
  final int? mrpMinor;

  /// Attribute key → chosen lookup value id. The same shape the create form
  /// sends, so an edit can be seeded from it and diffed against nothing.
  final Map<String, String?> attributes;

  /// Every other colour under this design. Attributes belong to the design,
  /// not the colourway — changing one here changes it for all of them, which
  /// is worth saying before somebody does it by accident.
  final List<CoreSibling> siblings;

  final CoreStock stock;

  /// What arrived, and when — newest first. See [CoreShotListRow] for the
  /// photograph side of a record; this is the goods side.
  final List<CoreConsignment> consignments;

  /// The photographs this product wants. A null `url` is an empty slot — the
  /// shot list, from inside the one record it belongs to.
  final List<CoreImageSlot> images;

  /// The adjectives on the design, as lookup value ids.
  final List<String> descriptors;

  /// The last few ledger events, newest first — the same rows Record A
  /// Movement writes, read back.
  final List<CoreMovement> movements;

  factory CoreRecordDetail.fromJson(Map<String, dynamic> json) =>
      CoreRecordDetail(
        id: json['id'] as String,
        designId: json['designId'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        nameIsCustom: json['nameIsCustom'] == true,
        isSerialised: json['isSerialised'] == true,
        notes: json['notes'] as String?,
        colourId: json['colourId'] as String?,
        secondaryColourId: json['secondaryColourId'] as String?,
        costMinor: _intOf(json['costMinor']),
        makingMinor: _intOf(json['makingMinor']),
        wholesaleMinor: _intOf(json['wholesaleMinor']),
        retailMinor: _intOf(json['retailMinor']),
        mrpMinor: _intOf(json['mrpMinor']),
        attributes: {
          for (final e in ((json['attributes'] as Map?) ?? const {}).entries)
            '${e.key}': e.value as String?,
        },
        siblings: [
          for (final s in (json['siblings'] as List? ?? const []))
            CoreSibling.fromJson((s as Map).cast<String, dynamic>()),
        ],
        stock: CoreStock.fromJson(
          ((json['stock'] as Map?) ?? const {}).cast<String, dynamic>(),
        ),
        consignments: [
          for (final c in (json['consignments'] as List? ?? const []))
            CoreConsignment.fromJson((c as Map).cast<String, dynamic>()),
        ],
        images: [
          for (final i in (json['images'] as List? ?? const []))
            CoreImageSlot.fromJson((i as Map).cast<String, dynamic>()),
        ],
        descriptors: [
          for (final d in (json['descriptors'] as List? ?? const [])) '$d',
        ],
        movements: [
          for (final m in (json['movements'] as List? ?? const []))
            CoreMovement.fromJson((m as Map).cast<String, dynamic>()),
        ],
      );
}

/// One line of the ledger — always positive, always between two places (or
/// one, when the other end is outside the business: Production, Customer,
/// Scrap). See `MOVEMENT_KINDS` on the web for the fixed vocabulary of
/// `kind`: received, returned, sold, damaged, transferred.
class CoreMovement {
  const CoreMovement({
    required this.id,
    required this.kind,
    required this.qty,
    required this.occurredAt,
    this.reason,
    this.from,
    this.to,
  });

  final int id;
  final String kind;
  final int qty;

  /// Already formatted by the server ("05 Sep 2026") — displayed as-is.
  final String occurredAt;

  /// Set on some movements (adjustments, order sync) and not others: Record A
  /// Movement's own form writes a reference and a note instead, which this
  /// endpoint does not currently echo back. Null here is common, not missing.
  final String? reason;

  final String? from;
  final String? to;

  factory CoreMovement.fromJson(Map<String, dynamic> json) => CoreMovement(
        id: _intOf(json['id']) ?? 0,
        kind: json['kind'] as String? ?? '',
        qty: _intOf(json['qty']) ?? 0,
        occurredAt: json['occurredAt'] as String? ?? '',
        reason: json['reason'] as String?,
        from: json['from'] as String?,
        to: json['to'] as String?,
      );
}

/// Another colour under the same design as the record being edited.
class CoreSibling {
  const CoreSibling({required this.id, this.colour});
  final String id;
  final String? colour;

  factory CoreSibling.fromJson(Map<String, dynamic> json) => CoreSibling(
        id: json['id'] as String,
        colour: json['colour'] as String?,
      );
}

/// The ledger, summarised — six running totals and where what remains sits.
class CoreStock {
  const CoreStock({
    required this.onHand,
    required this.received,
    required this.sold,
    required this.damaged,
    required this.returned,
    required this.adjusted,
    required this.byLocation,
  });

  final int onHand;
  final int received;
  final int sold;
  final int damaged;
  final int returned;
  final int adjusted;
  final List<CoreStockAtLocation> byLocation;

  factory CoreStock.fromJson(Map<String, dynamic> json) => CoreStock(
        onHand: _intOf(json['onHand']) ?? 0,
        received: _intOf(json['received']) ?? 0,
        sold: _intOf(json['sold']) ?? 0,
        damaged: _intOf(json['damaged']) ?? 0,
        returned: _intOf(json['returned']) ?? 0,
        adjusted: _intOf(json['adjusted']) ?? 0,
        byLocation: [
          for (final l in (json['byLocation'] as List? ?? const []))
            CoreStockAtLocation.fromJson((l as Map).cast<String, dynamic>()),
        ],
      );
}

class CoreStockAtLocation {
  const CoreStockAtLocation({required this.location, required this.qty});
  final String location;
  final int qty;

  factory CoreStockAtLocation.fromJson(Map<String, dynamic> json) =>
      CoreStockAtLocation(
        location: json['location'] as String,
        qty: _intOf(json['qty']) ?? 0,
      );
}

/// One delivery — a product code and the item codes minted under it.
class CoreConsignment {
  const CoreConsignment({
    required this.id,
    required this.code,
    required this.qty,
    this.location,
    required this.receivedAt,
    this.reference,
    this.note,
    required this.items,
    this.title,
    this.description,
    this.weightGrams,
    this.hsnCode,
    required this.channels,
  });

  final String id;

  /// 300001 and up.
  final String code;
  final int qty;
  final String? location;

  /// "03 Sep 2026", already formatted — the same reason `CorePiece` gets one.
  final String receivedAt;
  final String? reference;
  final String? note;

  /// The item codes minted under this consignment. Empty for unserialised
  /// cloth, which arrives as a quantity rather than as pieces.
  final List<String> items;

  /// What this consignment is listed as, where it differs from the rest of
  /// the line. Null means "compose it" — see @slk/domain/listing — not
  /// "unset the same way as an empty string".
  final String? title;
  final String? description;

  /// Grams. Null until entered — there is no honest default for a weight.
  final int? weightGrams;
  final String? hsnCode;

  /// Every channel this business sells through, and whether this specific
  /// consignment is listed on it yet.
  final List<CoreChannel> channels;

  factory CoreConsignment.fromJson(Map<String, dynamic> json) =>
      CoreConsignment(
        id: json['id'] as String,
        code: json['code'] as String,
        qty: _intOf(json['qty']) ?? 0,
        location: json['location'] as String?,
        receivedAt: json['receivedAt'] as String,
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        items: [
          for (final i in (json['items'] as List? ?? const [])) '$i',
        ],
        title: json['title'] as String?,
        description: json['description'] as String?,
        weightGrams: _intOf(json['weightGrams']),
        hsnCode: json['hsnCode'] as String?,
        channels: [
          for (final c in (json['channels'] as List? ?? const []))
            CoreChannel.fromJson((c as Map).cast<String, dynamic>()),
        ],
      );
}

/// One sales channel, and whether this consignment is listed on it yet. A
/// batch can be on some channels and not others — each is its own decision.
class CoreChannel {
  const CoreChannel({
    required this.code,
    required this.name,
    this.shopifyProductId,
  });

  final String code;
  final String name;

  /// Null until first published — that, not a separate flag, is "not
  /// published yet".
  final String? shopifyProductId;

  bool get isPublished => shopifyProductId != null;

  factory CoreChannel.fromJson(Map<String, dynamic> json) => CoreChannel(
        code: json['code'] as String,
        name: json['name'] as String,
        shopifyProductId: json['shopifyProductId'] as String?,
      );
}

/// One wanted photograph, whether or not it has been taken.
class CoreImageSlot {
  const CoreImageSlot({this.slotId, this.url});

  final String? slotId;

  /// Null until somebody photographs it — this is the shot list.
  final String? url;

  factory CoreImageSlot.fromJson(Map<String, dynamic> json) => CoreImageSlot(
        slotId: json['slotId'] as String?,
        url: json['url'] as String?,
      );
}
