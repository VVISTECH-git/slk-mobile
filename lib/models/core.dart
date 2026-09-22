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

/// A string, or null — never a stringified "null".
String? _stringOf(Object? value) => value == null ? null : '$value';

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
    this.jobRoles = const [],
  });

  final String id;
  final String code;
  final String name;

  /// floor · office · owner — a historical label now. slk-core retired Role
  /// as a source of access (see its own auth.ts, ADMIN_OVERRIDE_JOB_ROLE);
  /// [jobRoles] below is what the API actually checks, and what this app
  /// checks too, via [hasAnyJobRole].
  final String role;

  /// What this actor is actually allowed to do — "Admin", "Bale Custodian",
  /// "Handler", and so on. Empty means a sign-in that can reach nothing at
  /// all; the Staff screen refuses to create one like that, but an older
  /// account or one edited by hand could still arrive this way.
  final List<String> jobRoles;

  /// The one job role that means "everywhere" — matches
  /// ADMIN_OVERRIDE_JOB_ROLE in slk-core's own auth.ts exactly. Duplicated
  /// rather than fetched, the same reasoning slk-core's own sidebar gives for
  /// duplicating it client-side: this is a plain string, not worth a round
  /// trip to agree on.
  static const _adminJobRole = 'Admin';

  /// Whether holding any of [needed] would let this actor through a
  /// job-role gate — true unconditionally for Admin, same as the API's own
  /// `hasAnyJobRole` in auth.ts. This is the one check every screen that
  /// hides itself by job role should call, so a mismatch between what is
  /// shown and what the API actually allows can only ever happen in one
  /// place if it happens at all.
  bool hasAnyJobRole(List<String> needed) =>
      jobRoles.contains(_adminJobRole) ||
      needed.any((role) => jobRoles.contains(role));

  factory CoreActor.fromJson(Map<String, dynamic> json) => CoreActor(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        jobRoles: switch (json['jobRoles']) {
          List<dynamic> raw => raw.map((r) => r as String).toList(),
          _ => const [],
        },
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'role': role,
        'jobRoles': jobRoles,
      };

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
    this.pipeline = const CoreRecordPipeline(),
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

  /// The Thaans behind this record, if any — how many, where they are,
  /// what is still to fill in. Empty (all zero) on a server that predates
  /// records-with-Thaans.
  final CoreRecordPipeline pipeline;

  int get thaanCount => pipeline.thaanCount;
  int get finishedCount => pipeline.finishedCount;
  int get shelvedCount => pipeline.shelvedCount;
  String? get stage => pipeline.stage;
  List<String> get needs => pipeline.needs;

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
        pipeline: CoreRecordPipeline.fromJson(json),
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
    this.pipeline = const CoreRecordPipeline(),
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

  /// The Thaans behind this record — see [CoreRecordPipeline]. All zero on
  /// a server that doesn't send `pipeline`.
  final CoreRecordPipeline pipeline;

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
        pipeline: json['pipeline'] is Map
            ? CoreRecordPipeline.fromJson((json['pipeline'] as Map).cast<String, dynamic>())
            : const CoreRecordPipeline(),
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

/// A supplier of raw kora cloth — Bale Intake's Supplier field.
///
/// Its own table on slk-core, not vocabulary from `/options`: see
/// `packages/db/src/schema/production.ts`'s own note on why Kora to Shelf is
/// deliberately independent of the catalogue.
class CoreSupplier {
  const CoreSupplier({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String name;

  /// `active` or `inactive` — an inactive supplier stays on old bales but
  /// drops out of the picker for a new one.
  final String status;

  factory CoreSupplier.fromJson(Map<String, dynamic> json) => CoreSupplier(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
      );
}

/// A named kind of cloth — Bale Intake's Item field.
class CoreClothItem {
  const CoreClothItem({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String name;
  final String status;

  factory CoreClothItem.fromJson(Map<String, dynamic> json) => CoreClothItem(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
      );
}

/// One bale entry, as the intake list shows it back — field-for-field what
/// `loadBales()` returns on slk-core.
class CoreBale {
  const CoreBale({
    required this.id,
    required this.code,
    required this.supplierName,
    required this.type,
    required this.metresReceived,
    required this.uom,
    required this.itemName,
    required this.baleCount,
    required this.status,
    required this.billEntryDate,
    this.thaanCount = 0,
    this.qrGeneratedCount = 0,
  });

  final String id;
  final String code;
  final String supplierName;
  final String type;
  final double metresReceived;
  final String uom;
  final String itemName;
  final int baleCount;

  /// `awaiting_cutting`, `cutting_in_progress`, `cut`, or `returned`.
  final String status;

  /// "14 Sep 2026" — already formatted server-side.
  final String billEntryDate;

  /// How many Thaans have been recorded from this bale so far. Zero while
  /// still `awaiting_cutting`; only ever grows, across as many recordings
  /// as cutting takes.
  final int thaanCount;

  /// How many of those Thaans already have a permanent QR code. Never
  /// exceeds [thaanCount]; once it equals it, there is nothing left for
  /// "Generate QR codes" to do.
  final int qrGeneratedCount;

  factory CoreBale.fromJson(Map<String, dynamic> json) => CoreBale(
        id: json['id'] as String,
        code: json['code'] as String,
        supplierName: json['supplierName'] as String,
        type: json['type'] as String,
        metresReceived: (json['metresReceived'] as num).toDouble(),
        uom: json['uom'] as String,
        itemName: json['itemName'] as String,
        baleCount: (json['baleCount'] as num).toInt(),
        status: json['status'] as String,
        billEntryDate: json['billEntryDate'] as String,
        thaanCount: (json['thaanCount'] as num?)?.toInt() ?? 0,
        qrGeneratedCount: (json['qrGeneratedCount'] as num?)?.toInt() ?? 0,
      );
}

/// One Thaan's own details, as `/api/v1/thaans/lookup?code=` returns
/// them — what scanning a printed label resolves to. Same fields slk-core's
/// own Thaans table shows per row.
class CoreThaan {
  const CoreThaan({
    required this.code,
    required this.baleCode,
    required this.supplierName,
    required this.itemName,
    required this.baleType,
    required this.billEntryDate,
    required this.perThaanMetres,
    required this.transporter,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.invoiceAmount,
    required this.metresReceived,
    required this.uom,
    required this.gradeCode,
    required this.needsSecondPrint,
    required this.baleCount,
    required this.baleNotes,
    required this.baleStatus,
    this.fibre,
    this.textileMaterial,
    this.weave,
    this.productionMethod,
    this.audience,
    this.borderStyle,
    this.borderHeight,
    this.pallu,
    this.hasBlouse,
    this.blouseStyle,
    this.blouseMaterial,
    this.sareeLengthCm,
    this.sareeWidthCm,
    this.palluLengthCm,
    this.blouseLengthCm,
    required this.pipelineStatus,
    required this.qrGeneratedAt,
    required this.voidedAt,
    required this.lastVendorId,
    required this.lastVendorName,
    required this.lastStage,
    this.id,
    this.colourwayId,
    this.recordCode,
    this.recordName,
    this.recordColour,
    this.pieceCode,
    this.productCode,
    this.locationName,
    this.isHeld,
    this.priceMinor,
    this.stockStatus,
  });

  /// The row id — what `/records/:id/thaans` wants. Nullable because the
  /// lookup predates records-with-Thaans and an older server may not send it.
  final String? id;

  final String? code;
  final String baleCode;
  final String supplierName;
  final String itemName;
  final String baleType;
  final String billEntryDate;
  final double? perThaanMetres;

  /// Everything else the bale carries — read live off it by slk-core, not
  /// copied onto the Thaan, so a correction to the bale shows here too.
  final String? transporter;
  final String? invoiceNumber;
  final String? invoiceDate;
  final double? invoiceAmount;

  /// The whole bale's metres; [perThaanMetres] is this Thaan's share of it.
  final double metresReceived;
  final String uom;
  final String? gradeCode;
  final bool needsSecondPrint;
  final int baleCount;
  final String? baleNotes;

  /// `awaiting_cutting`, `cutting_in_progress`, `cut` or `returned`.
  final String baleStatus;

  /// The cloth item's own properties (Product Management's lists), read live
  /// by slk-core — null means the item never fixed that fact.
  final String? fibre;
  final String? textileMaterial;
  final String? weave;
  final String? productionMethod;
  final String? audience;
  final String? borderStyle;
  final String? borderHeight;
  final String? pallu;
  final bool? hasBlouse;
  final String? blouseStyle;
  final String? blouseMaterial;
  final double? sareeLengthCm;
  final double? sareeWidthCm;
  final double? palluLengthCm;
  final double? blouseLengthCm;

  /// "Out for Salava", "Ready for Karakkaya", "Finished" — see slk-core's
  /// own `pipelineStatus()` in `lib/thaans.ts` for exactly how this reads.
  final String pipelineStatus;

  /// "14 Sep 2026, 05:35 AM" — already formatted server-side. Null until a
  /// code has been generated for this Thaan.
  final String? qrGeneratedAt;

  /// Set once someone voids this Thaan — never unset.
  final String? voidedAt;

  /// Whoever most recently held this Thaan for a stage — null if it has no
  /// handover history yet. What "Flag as damaged" pre-fills from.
  final String? lastVendorId;
  final String? lastVendorName;
  final String? lastStage;

  /// The Product Management record this Thaan is linked to, if any — the
  /// colourway it was sorted into when it came back from Print. All null
  /// when it isn't in one (or the server predates the link).
  final String? colourwayId;
  final String? recordCode;
  final String? recordName;
  final String? recordColour;

  /// Once shelved: the piece it became (the same code as the QR label
  /// already on it), the product it sits under, and where the ledger says
  /// it is. Null while it is still in the pipeline.
  final String? pieceCode;
  final String? productCode;
  final String? locationName;

  /// Still ours, once shelved — null while there is no piece to hold.
  final bool? isHeld;

  /// Retail, in paise, once shelved.
  final num? priceMinor;

  /// "In pipeline", "On shelf", "Gone" or "Voided" — the server's one-word
  /// answer to "where is it". Null from a server that predates it.
  final String? stockStatus;

  /// "KC-0412 · Peacock florals · Teal", or null when not in a record.
  String? get recordLabel {
    if (colourwayId == null) return null;
    final parts = [
      if (recordCode != null && recordCode!.isNotEmpty) recordCode!,
      if (recordName != null && recordName!.isNotEmpty) recordName!,
      if (recordColour != null && recordColour!.isNotEmpty) recordColour!,
    ];
    return parts.isEmpty ? 'Record' : parts.join(' · ');
  }

  String get price => _rupees(priceMinor?.toInt());

  factory CoreThaan.fromJson(Map<String, dynamic> json) => CoreThaan(
        id: _stringOf(json['id']),
        colourwayId: _stringOf(json['colourwayId']),
        recordCode: _stringOf(json['recordCode']),
        recordName: _stringOf(json['recordName']),
        recordColour: _stringOf(json['recordColour']),
        pieceCode: _stringOf(json['pieceCode']),
        productCode: _stringOf(json['productCode']),
        locationName: _stringOf(json['locationName']),
        isHeld: json['isHeld'] is bool ? json['isHeld'] as bool : null,
        priceMinor: _numOf(json['priceMinor']),
        stockStatus: _stringOf(json['stockStatus']),
        code: json['code'] as String?,
        baleCode: json['baleCode'] as String,
        supplierName: json['supplierName'] as String,
        itemName: json['itemName'] as String,
        baleType: json['baleType'] as String,
        billEntryDate: json['billEntryDate'] as String,
        perThaanMetres: (json['perThaanMetres'] as num?)?.toDouble(),
        transporter: json['transporter'] as String?,
        invoiceNumber: json['invoiceNumber'] as String?,
        invoiceDate: json['invoiceDate'] as String?,
        invoiceAmount: (json['invoiceAmount'] as num?)?.toDouble(),
        metresReceived: (json['metresReceived'] as num).toDouble(),
        uom: json['uom'] as String,
        gradeCode: json['gradeCode'] as String?,
        needsSecondPrint: json['needsSecondPrint'] as bool,
        baleCount: json['baleCount'] as int,
        baleNotes: json['baleNotes'] as String?,
        baleStatus: json['baleStatus'] as String,
        fibre: json['fibre'] as String?,
        textileMaterial: json['textileMaterial'] as String?,
        weave: json['weave'] as String?,
        productionMethod: json['productionMethod'] as String?,
        audience: json['audience'] as String?,
        borderStyle: json['borderStyle'] as String?,
        borderHeight: json['borderHeight'] as String?,
        pallu: json['pallu'] as String?,
        hasBlouse: json['hasBlouse'] as bool?,
        blouseStyle: json['blouseStyle'] as String?,
        blouseMaterial: json['blouseMaterial'] as String?,
        sareeLengthCm: (json['sareeLengthCm'] as num?)?.toDouble(),
        sareeWidthCm: (json['sareeWidthCm'] as num?)?.toDouble(),
        palluLengthCm: (json['palluLengthCm'] as num?)?.toDouble(),
        blouseLengthCm: (json['blouseLengthCm'] as num?)?.toDouble(),
        pipelineStatus: json['pipelineStatus'] as String,
        qrGeneratedAt: json['qrGeneratedAt'] as String?,
        voidedAt: json['voidedAt'] as String?,
        lastVendorId: json['lastVendorId'] as String?,
        lastVendorName: json['lastVendorName'] as String?,
        lastStage: json['lastStage'] as String?,
      );
}

/// Who a batch can be sent to — Handovers' Send screen's vendor picker.
/// Deliberately thin: id, name and which stages they do, not the billing
/// totals `/vendors` on the web carries — a floor phone sending a batch has
/// no reason to read those.
class CoreVendor {
  const CoreVendor({required this.id, required this.name, required this.stages});

  final String id;
  final String name;

  /// Which stage(s) this vendor normally does — informational for the
  /// picker, not enforced: any vendor can be picked for any stage, the same
  /// as the web screen allows.
  final List<String> stages;

  factory CoreVendor.fromJson(Map<String, dynamic> json) => CoreVendor(
        id: json['id'] as String,
        name: json['name'] as String,
        stages: [for (final s in (json['stages'] as List? ?? const [])) '$s'],
      );
}

/// One vendor with what's owed and what's been paid — Finance Manager's
/// own vendor list on mobile. Narrows slk-core's own `VendorRow`
/// (apps/web/src/lib/vendors.ts) to what a phone needs.
class CoreVendorFinance {
  const CoreVendorFinance({
    required this.id,
    required this.code,
    required this.name,
    required this.primaryPhone,
    required this.secondaryPhone,
    required this.village,
    required this.stages,
    required this.totalEarned,
    required this.totalPaid,
    required this.balanceDue,
    required this.currentlyHolding,
  });

  final String id;
  final String code;
  final String name;
  final String? primaryPhone;
  final String? secondaryPhone;
  final String? village;
  final List<String> stages;
  final double totalEarned;
  final double totalPaid;
  final double balanceDue;
  final int currentlyHolding;

  factory CoreVendorFinance.fromJson(Map<String, dynamic> json) => CoreVendorFinance(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        primaryPhone: json['primaryPhone'] as String?,
        secondaryPhone: json['secondaryPhone'] as String?,
        village: json['village'] as String?,
        stages: [for (final s in (json['stages'] as List? ?? const [])) '$s'],
        totalEarned: (json['totalEarned'] as num).toDouble(),
        totalPaid: (json['totalPaid'] as num).toDouble(),
        balanceDue: (json['balanceDue'] as num).toDouble(),
        currentlyHolding: json['currentlyHolding'] as int,
      );
}

/// One entry in a vendor's ledger — a billed transaction or a payment, the
/// same rows slk-core's own `VendorLedgerEntry` carries
/// (apps/web/src/lib/vendors.ts). `amount` null on a transaction means "not
/// priced yet" (see [status]) — always a real number on a payment.
class CoreVendorLedgerEntry {
  const CoreVendorLedgerEntry({
    required this.kind,
    required this.id,
    required this.date,
    required this.stage,
    required this.pieceCount,
    required this.amount,
    required this.notes,
    required this.baleCodes,
    required this.approvedAt,
    required this.paidAt,
  });

  /// 'transaction' | 'payment'.
  final String kind;
  final String id;
  final String date;
  final String? stage;
  final int? pieceCount;
  final double? amount;
  final String? notes;
  final List<String>? baleCodes;
  final String? approvedAt;
  final String? paidAt;

  bool get isTransaction => kind == 'transaction';

  /// 'needs_pricing' | 'unapproved' | 'approved' | 'paid' — same vocabulary
  /// as slk-core's own `vendorTransactionStatus` (lib/vendor-status.ts).
  /// Null for a payment row, which has no status of its own.
  String? get status {
    if (!isTransaction) return null;
    if (amount == null) return 'needs_pricing';
    if (paidAt != null) return 'paid';
    if (approvedAt != null) return 'approved';
    return 'unapproved';
  }

  factory CoreVendorLedgerEntry.fromJson(Map<String, dynamic> json) => CoreVendorLedgerEntry(
        kind: json['kind'] as String,
        id: json['id'] as String,
        date: json['date'] as String,
        stage: json['stage'] as String?,
        pieceCount: json['pieceCount'] as int?,
        amount: (json['amount'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
        baleCodes: json['baleCodes'] == null ? null : [for (final b in json['baleCodes'] as List) '$b'],
        approvedAt: json['approvedAt'] as String?,
        paidAt: json['paidAt'] as String?,
      );
}

/// A Thaan flagged damaged against one vendor — same rows slk-core's own
/// `DamagedThaanRow` carries (apps/web/src/lib/thaan-damage.ts).
class CoreDamagedThaan {
  const CoreDamagedThaan({
    required this.id,
    required this.thaanCode,
    required this.baleCode,
    required this.stage,
    required this.notes,
    required this.flaggedAt,
    required this.flaggedByName,
    required this.addressedAt,
    required this.writtenOffAt,
  });

  final String id;
  final String? thaanCode;
  final String baleCode;
  final String? stage;
  final String? notes;
  final String flaggedAt;
  final String? flaggedByName;
  final String? addressedAt;
  final String? writtenOffAt;

  /// 'flagged' | 'addressed' | 'written_off' — same vocabulary as
  /// slk-core's own `damagedThaanStatus` (lib/damaged-status.ts).
  String get status {
    if (writtenOffAt != null) return 'written_off';
    if (addressedAt != null) return 'addressed';
    return 'flagged';
  }

  factory CoreDamagedThaan.fromJson(Map<String, dynamic> json) => CoreDamagedThaan(
        id: json['id'] as String,
        thaanCode: json['thaanCode'] as String?,
        baleCode: json['baleCode'] as String,
        stage: json['stage'] as String?,
        notes: json['notes'] as String?,
        flaggedAt: json['flaggedAt'] as String,
        flaggedByName: json['flaggedByName'] as String?,
        addressedAt: json['addressedAt'] as String?,
        writtenOffAt: json['writtenOffAt'] as String?,
      );
}

/// How many Thaans currently sit at one point in the pipeline — "Not
/// started", one of the stage names, or "Finished" — and how long the
/// oldest one there has been waiting. Same rows slk-core's own
/// `StageSummaryRow` carries (apps/web/src/lib/thaans.ts). A count alone
/// means nothing at real volume; `oldestDaysWaiting` is the actual signal.
class CoreStageSummaryRow {
  const CoreStageSummaryRow({
    required this.bucket,
    required this.count,
    required this.oldestDaysWaiting,
    required this.oldestSince,
  });

  final String bucket;
  final int count;
  final int? oldestDaysWaiting;
  final String? oldestSince;

  factory CoreStageSummaryRow.fromJson(Map<String, dynamic> json) => CoreStageSummaryRow(
        bucket: json['bucket'] as String,
        count: json['count'] as int,
        oldestDaysWaiting: json['oldestDaysWaiting'] as int?,
        oldestSince: json['oldestSince'] as String?,
      );
}

/// One vendor-and-bale group behind a stage-summary bucket's count — the
/// drill-down, grouped rather than one row per Thaan so a bucket with
/// hundreds in it is still readable. Same rows slk-core's own
/// `StageGroupRow` carries.
class CoreStageGroup {
  const CoreStageGroup({
    required this.baleCode,
    required this.vendorName,
    required this.count,
    required this.daysWaiting,
    required this.since,
  });

  final String baleCode;

  /// Who currently has it, if this bucket means "out for" that stage — null otherwise.
  final String? vendorName;
  final int count;
  final int? daysWaiting;
  final String? since;

  factory CoreStageGroup.fromJson(Map<String, dynamic> json) => CoreStageGroup(
        baleCode: json['baleCode'] as String,
        vendorName: json['vendorName'] as String?,
        count: json['count'] as int,
        daysWaiting: json['daysWaiting'] as int?,
        since: json['since'] as String?,
      );
}

/// One bale type's own completion — "Sarees", "Fabric", "Chunnies",
/// "Bedsheets" or "Pillows" — how many of its Thaans are Finished against
/// how many exist at all. Same rows slk-core's own `TypeSummaryRow`
/// carries (apps/web/src/lib/thaans.ts). A type near 100% finished with
/// nothing left behind it is a type about to run out of stock to cut.
class CoreTypeSummaryRow {
  const CoreTypeSummaryRow({required this.type, required this.total, required this.finished});

  final String type;
  final int total;
  final int finished;

  double get finishedFraction => total == 0 ? 0 : finished / total;

  factory CoreTypeSummaryRow.fromJson(Map<String, dynamic> json) => CoreTypeSummaryRow(
        type: json['type'] as String,
        total: json['total'] as int,
        finished: json['finished'] as int,
      );
}

/// One Thaan, as a Send-screen scan answers for it — the same shape
/// `ThaanForSend` on the web carries.
class CoreThaanForSend {
  const CoreThaanForSend({
    required this.id,
    required this.code,
    required this.baleCode,
    required this.baleType,
    required this.itemName,
  });

  final String id;
  final String code;
  final String baleCode;
  final String baleType;
  final String itemName;

  factory CoreThaanForSend.fromJson(Map<String, dynamic> json) => CoreThaanForSend(
        id: json['id'] as String,
        code: json['code'] as String,
        baleCode: json['baleCode'] as String,
        baleType: json['baleType'] as String,
        itemName: json['itemName'] as String,
      );
}

/// One Thaan, as a Receive-screen scan answers for it — [CoreThaanForSend]'s
/// fields plus which stage and vendor it's actually out for right now.
class CoreThaanForReceive {
  const CoreThaanForReceive({
    required this.id,
    required this.code,
    required this.baleCode,
    required this.baleType,
    required this.itemName,
    required this.stage,
    this.throughStage,
    this.vendorId,
    required this.vendorName,
    this.colourwayId,
    this.recordCode,
    this.recordName,
    this.recordColour,
    this.canRecord = false,
  });

  final String id;
  final String code;
  final String baleCode;
  final String baleType;
  final String itemName;
  final String stage;

  /// The record this Thaan is already linked to, if any — receiving it into
  /// another record moves it, and the Receive screen says so.
  final String? colourwayId;
  final String? recordCode;
  final String? recordName;
  final String? recordColour;

  /// Whether this receive is Print or later — the only point from which a
  /// Thaan can be sorted into a record. False when the server didn't say.
  final bool canRecord;

  /// "KC-0412 · Teal", or null when not in a record yet.
  String? get recordLabel {
    if (colourwayId == null) return null;
    final parts = [
      if (recordCode != null && recordCode!.isNotEmpty) recordCode!,
      if (recordName != null && recordName!.isNotEmpty) recordName!,
      if (recordColour != null && recordColour!.isNotEmpty) recordColour!,
    ];
    return parts.isEmpty ? 'a record' : parts.join(' · ');
  }

  /// The last stage of a combined trip, or null for an ordinary one-stage
  /// trip. Receiving closes every stage up to it in one go.
  final String? throughStage;

  /// Null means in-house — see [vendorName], which reads "In-house" then.
  final String? vendorId;
  final String vendorName;

  factory CoreThaanForReceive.fromJson(Map<String, dynamic> json) => CoreThaanForReceive(
        id: json['id'] as String,
        code: json['code'] as String,
        baleCode: json['baleCode'] as String,
        baleType: json['baleType'] as String,
        itemName: json['itemName'] as String,
        stage: json['stage'] as String,
        throughStage: json['throughStage'] as String?,
        vendorId: json['vendorId'] as String?,
        vendorName: json['vendorName'] as String,
        colourwayId: _stringOf(json['colourwayId']),
        recordCode: _stringOf(json['recordCode']),
        recordName: _stringOf(json['recordName']),
        recordColour: _stringOf(json['recordColour']),
        canRecord: json['canRecord'] == true,
      );
}

// ── The production pipeline behind a record ─────────────────────────────────

/// `needs` as the server sends it — a list of short words — or nothing.
List<String> _needsOf(Object? raw) => [
      for (final n in (raw is List ? raw : const []))
        if (n != null && '$n'.isNotEmpty) '$n',
    ];

num? _numOf(Object? value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

/// "550" for 550.0, "112.5" for 112.5 — a size without a trailing ".0".
String _plainNum(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

/// "6 Thaans · Nellateeta · needs craft" — the one line a list row or a
/// detail header says about a record's Thaans. Null when it has none.
String? _pipelineLine({
  required int thaanCount,
  required String? stage,
  required List<String> needs,
}) {
  if (thaanCount <= 0) return null;
  return [
    '$thaanCount Thaan${thaanCount == 1 ? '' : 's'}',
    if (stage != null && stage.isNotEmpty) stage,
    if (needs.isNotEmpty) 'needs ${needs.join(', ')}',
  ].join(' · ');
}

/// How far a record's Thaans have got — the same five facts on a list row
/// (`GET /records`) and, as `pipeline`, on the detail (`GET /records/:id`).
/// An older server sends none of them, which reads as "no Thaans".
class CoreRecordPipeline {
  const CoreRecordPipeline({
    this.thaanCount = 0,
    this.finishedCount = 0,
    this.shelvedCount = 0,
    this.stage,
    this.needs = const [],
  });

  /// Every Thaan linked to the record, voided ones aside.
  final int thaanCount;

  /// Back from Ironing and not stock yet — what "Put on the shelf" takes.
  final int finishedCount;

  /// Already on the shelf as pieces.
  final int shelvedCount;

  /// Where the Thaans are now — the stage most of them are at.
  final String? stage;

  /// Short words for what is still to be filled in ("motif", "craft");
  /// empty once every detail decided so far is in.
  final List<String> needs;

  /// Still out at a stage — neither finished nor shelved.
  int get inPipeline {
    final n = thaanCount - finishedCount - shelvedCount;
    return n < 0 ? 0 : n;
  }

  String? get line => _pipelineLine(thaanCount: thaanCount, stage: stage, needs: needs);

  factory CoreRecordPipeline.fromJson(Map<String, dynamic> json) => CoreRecordPipeline(
        thaanCount: _intOf(json['thaanCount']) ?? 0,
        finishedCount: _intOf(json['finishedCount']) ?? 0,
        shelvedCount: _intOf(json['shelvedCount']) ?? 0,
        stage: _stringOf(json['stage']),
        needs: _needsOf(json['needs']),
      );
}

/// One row of `GET /records/pipeline` — a record with Thaans behind it,
/// slim enough for a picker: which record, what it looks like, how far
/// along it is.
class CorePipelineRecord {
  const CorePipelineRecord({
    required this.id,
    required this.code,
    required this.name,
    this.colour,
    this.colourHex,
    this.motif,
    this.motifCategory,
    this.thaanCount = 0,
    this.finishedCount = 0,
    this.shelvedCount = 0,
    this.stage,
    this.needs = const [],
  });

  final String id;
  final String code;
  final String name;
  final String? colour;
  final String? colourHex;
  final String? motif;
  final String? motifCategory;
  final int thaanCount;
  final int finishedCount;
  final int shelvedCount;
  final String? stage;
  final List<String> needs;

  Color? get swatch => _swatchOf(colourHex);

  /// "KC-0412 · Teal · Peacock · 6 Thaans" — the picker's one line.
  String get summary => [
        code,
        if (colour != null && colour!.isNotEmpty) colour!,
        if (motif != null && motif!.isNotEmpty) motif!,
        '$thaanCount Thaan${thaanCount == 1 ? '' : 's'}',
      ].join(' · ');

  /// Everything somebody might type to find this row.
  String get haystack => [code, name, colour ?? '', motif ?? '', motifCategory ?? ''].join(' ').toLowerCase();

  factory CorePipelineRecord.fromJson(Map<String, dynamic> json) => CorePipelineRecord(
        id: '${json['id']}',
        code: _stringOf(json['code']) ?? '',
        name: _stringOf(json['name']) ?? '',
        colour: _stringOf(json['colour']),
        colourHex: _stringOf(json['colourHex']),
        motif: _stringOf(json['motif']),
        motifCategory: _stringOf(json['motifCategory']),
        thaanCount: _intOf(json['thaanCount']) ?? 0,
        finishedCount: _intOf(json['finishedCount']) ?? 0,
        shelvedCount: _intOf(json['shelvedCount']) ?? 0,
        stage: _stringOf(json['stage']),
        needs: _needsOf(json['needs']),
      );
}

/// One Thaan linked to a record, as `GET /records/:id/thaans` lists it.
class CorePipelineThaan {
  const CorePipelineThaan({
    required this.id,
    required this.code,
    this.baleCode,
    this.voidedAt,
    this.openStage,
    this.completedStages = 0,
    this.pieceCode,
    this.locationName,
    this.isHeld = false,
  });

  final String id;
  final String code;
  final String? baleCode;
  final String? voidedAt;

  /// The stage it's out for right now, or null when it's in hand.
  final String? openStage;

  /// How many stages it has finished — a count whether the server sent a
  /// number or the list of stage names.
  final int completedStages;

  /// Its shelf piece code once shelved — the QR label already on it. Null
  /// while it is still in the pipeline.
  final String? pieceCode;

  /// Where the piece is, once shelved.
  final String? locationName;

  /// Still ours, once shelved — sold, written off or sent on make it false.
  final bool isHeld;

  /// "Out for Nellateeta" / "4 stages done" — where it is, in a phrase.
  String get where => openStage != null
      ? 'Out for $openStage'
      : '$completedStages stage${completedStages == 1 ? '' : 's'} done';

  factory CorePipelineThaan.fromJson(Map<String, dynamic> json) {
    final done = json['completedStages'];
    return CorePipelineThaan(
      id: '${json['id']}',
      code: _stringOf(json['code']) ?? '',
      baleCode: _stringOf(json['baleCode']),
      voidedAt: _stringOf(json['voidedAt']),
      openStage: _stringOf(json['openStage']),
      completedStages: done is List ? done.length : (_intOf(done) ?? 0),
      pieceCode: _stringOf(json['pieceCode']),
      locationName: _stringOf(json['locationName']),
      isHeld: json['isHeld'] == true,
    );
  }
}

/// A detail already settled by the bale's cloth item, shown on the fill
/// screen so nobody types it again.
class CoreRecordInherited {
  const CoreRecordInherited({required this.key, required this.label, required this.valueLabel});

  final String key;
  final String label;
  final String valueLabel;

  factory CoreRecordInherited.fromJson(Map<String, dynamic> json) => CoreRecordInherited(
        key: _stringOf(json['key']) ?? '',
        label: _stringOf(json['label']) ?? _stringOf(json['key']) ?? '',
        valueLabel: _stringOf(json['valueLabel']) ?? '—',
      );
}

/// One detail to decide on the fill screen: which attribute, which Master
/// List to pick from, and what (if anything) is picked so far.
class CoreRecordFillField {
  const CoreRecordFillField({
    required this.key,
    required this.label,
    required this.list,
    this.valueId,
    this.valueLabel,
    this.required = false,
  });

  /// The attribute key sent back in `POST /records/:id/fill`.
  final String key;
  final String label;

  /// The Master List code — `motif`, `craft_technique`, `border_style` —
  /// which is the key into [CoreOptions].
  final String list;
  final String? valueId;
  final String? valueLabel;
  final bool required;

  factory CoreRecordFillField.fromJson(Map<String, dynamic> json) => CoreRecordFillField(
        key: _stringOf(json['key']) ?? '',
        label: _stringOf(json['label']) ?? _stringOf(json['key']) ?? '',
        list: _stringOf(json['list']) ?? '',
        valueId: _stringOf(json['valueId']),
        valueLabel: _stringOf(json['valueLabel']),
        required: json['required'] == true,
      );
}

/// `GET /records/:id/fill` — everything the fill screen needs: what is
/// inherited from the cloth item, what is to be decided, and what has been
/// decided already.
class CoreRecordFill {
  const CoreRecordFill({
    required this.colourwayId,
    this.designCode,
    this.recordName,
    this.stage = '',
    this.thaanCount = 0,
    this.inherited = const [],
    this.lengthCm,
    this.widthCm,
    this.colourId,
    this.colourLabel,
    this.secondaryColourId,
    this.secondaryColourLabel,
    this.fields = const [],
    this.needs = const [],
  });

  final String colourwayId;
  final String? designCode;
  final String? recordName;
  final String stage;
  final int thaanCount;
  final List<CoreRecordInherited> inherited;

  /// `extra.lengthCm` / `extra.widthCm` — the saree size, when the item
  /// carries one.
  final num? lengthCm;
  final num? widthCm;
  final String? colourId;
  final String? colourLabel;
  final String? secondaryColourId;
  final String? secondaryColourLabel;
  final List<CoreRecordFillField> fields;
  final List<String> needs;

  /// "KC-0412 · Peacock florals", or null when the server named neither.
  String? get recordLabel {
    if (designCode == null && recordName == null) return null;
    return [?designCode, ?recordName].join(' · ');
  }

  /// "550 × 112 cm", or null when the item has no size.
  String? get sareeSize {
    if (lengthCm == null || widthCm == null) return null;
    return '${_plainNum(lengthCm!)} × ${_plainNum(widthCm!)} cm';
  }

  factory CoreRecordFill.fromJson(Map<String, dynamic> json) {
    final extra = (json['extra'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CoreRecordFill(
      colourwayId: '${json['colourwayId']}',
      designCode: _stringOf(json['designCode']),
      recordName: _stringOf(json['recordName']),
      stage: _stringOf(json['stage']) ?? '',
      thaanCount: _intOf(json['thaanCount']) ?? 0,
      inherited: [
        for (final i in (json['inherited'] as List? ?? const []))
          CoreRecordInherited.fromJson((i as Map).cast<String, dynamic>()),
      ],
      lengthCm: _numOf(extra['lengthCm']),
      widthCm: _numOf(extra['widthCm']),
      colourId: _stringOf(json['colourId']),
      colourLabel: _stringOf(json['colourLabel']),
      secondaryColourId: _stringOf(json['secondaryColourId']),
      secondaryColourLabel: _stringOf(json['secondaryColourLabel']),
      fields: [
        for (final f in (json['fields'] as List? ?? const []))
          CoreRecordFillField.fromJson((f as Map).cast<String, dynamic>()),
      ],
      needs: _needsOf(json['needs']),
    );
  }
}

// ── From the pipeline to the shelf ──

/// A Thaan as the shelf draft lists it — just enough to name it.
class CoreShelfThaan {
  const CoreShelfThaan({required this.id, required this.code});

  final String id;
  final String code;

  factory CoreShelfThaan.fromJson(Map<String, dynamic> json) => CoreShelfThaan(
        id: '${json['id']}',
        code: _stringOf(json['code']) ?? '',
      );
}

/// A location the shelved pieces can go to, as the draft offers it.
class CoreShelfLocation {
  const CoreShelfLocation({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory CoreShelfLocation.fromJson(Map<String, dynamic> json) => CoreShelfLocation(
        id: '${json['id']}',
        name: _stringOf(json['name']) ?? _stringOf(json['code']) ?? '',
        code: _stringOf(json['code']) ?? '',
      );
}

/// The five prices a shelved product carries, as rupee strings — "" when
/// unset. Same shape going up in `POST /records/:id/shelf` as coming down.
class CoreShelfPrices {
  const CoreShelfPrices({
    this.cost = '',
    this.making = '',
    this.wholesale = '',
    this.retail = '',
    this.mrp = '',
  });

  final String cost;
  final String making;
  final String wholesale;
  final String retail;
  final String mrp;

  factory CoreShelfPrices.fromJson(Map<String, dynamic> json) => CoreShelfPrices(
        cost: _stringOf(json['cost']) ?? '',
        making: _stringOf(json['making']) ?? '',
        wholesale: _stringOf(json['wholesale']) ?? '',
        retail: _stringOf(json['retail']) ?? '',
        mrp: _stringOf(json['mrp']) ?? '',
      );

  Map<String, String> toJson() => {
        'cost': cost,
        'making': making,
        'wholesale': wholesale,
        'retail': retail,
        'mrp': mrp,
      };
}

/// `GET /records/:id/shelf` — what the shelf screen shows: which Thaans are
/// back from Ironing and would go, which are on the shelf already, the
/// prices set so far, where they can go, and anything in the way.
class CoreRecordShelf {
  const CoreRecordShelf({
    required this.colourwayId,
    this.designCode,
    this.recordName,
    this.pieceTracked = false,
    this.finished = const [],
    this.shelved = const [],
    this.inPipeline = 0,
    this.prices = const CoreShelfPrices(),
    this.locations = const [],
    this.needs = const [],
    this.blockers = const [],
  });

  final String colourwayId;
  final String? designCode;
  final String? recordName;

  /// Whether the record tracks each piece by its own code.
  final bool pieceTracked;

  /// Back from Ironing, not yet stock — these are what go on the shelf.
  final List<CoreShelfThaan> finished;

  /// Already on the shelf as pieces.
  final List<CoreShelfThaan> shelved;

  /// Still out at a stage — neither finished nor shelved.
  final int inPipeline;
  final CoreShelfPrices prices;
  final List<CoreShelfLocation> locations;

  /// Details still to fill in before the record is whole — see
  /// [CoreRecordPipeline.needs].
  final List<String> needs;

  /// Why the Thaans can't go on the shelf yet, in the server's words. Empty
  /// when they can.
  final List<String> blockers;

  /// "KC-0412 · Peacock florals", or null when the server named neither.
  String? get recordLabel {
    if (designCode == null && recordName == null) return null;
    return [?designCode, ?recordName].join(' · ');
  }

  factory CoreRecordShelf.fromJson(Map<String, dynamic> json) => CoreRecordShelf(
        colourwayId: '${json['colourwayId']}',
        designCode: _stringOf(json['designCode']),
        recordName: _stringOf(json['recordName']),
        pieceTracked: json['pieceTracked'] == true,
        finished: [
          for (final t in (json['finished'] as List? ?? const []))
            CoreShelfThaan.fromJson((t as Map).cast<String, dynamic>()),
        ],
        shelved: [
          for (final t in (json['shelved'] as List? ?? const []))
            CoreShelfThaan.fromJson((t as Map).cast<String, dynamic>()),
        ],
        inPipeline: _intOf(json['inPipeline']) ?? 0,
        prices: json['prices'] is Map
            ? CoreShelfPrices.fromJson((json['prices'] as Map).cast<String, dynamic>())
            : const CoreShelfPrices(),
        locations: [
          for (final l in (json['locations'] as List? ?? const []))
            CoreShelfLocation.fromJson((l as Map).cast<String, dynamic>()),
        ],
        needs: _needsOf(json['needs']),
        blockers: _needsOf(json['blockers']),
      );
}
