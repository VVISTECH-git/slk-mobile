import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import 'core_auth.dart';
import 'new_record_screen.dart';
import 'record_fields.dart';
import 'record_form_fields.dart';
import 'record_photos_screen.dart';
import 'records_list_screen.dart';

/// A record that already exists, shown the way it was entered and open to
/// correction.
///
/// The fields are [RecordFormFields] — the same ones [NewRecordScreen] asks,
/// seeded from the record instead of the vocabulary's defaults. What is
/// particular to editing: a Stock tab that is a ledger rather than an opening
/// count, a warning where an attribute is shared with other colours of the
/// same design, and a save that changes only what this screen shows rather
/// than minting anything.
///
/// `floor`, matching creation — the API's PATCH accepts the same actor a
/// create does, on the same reasoning: whoever is holding the delivery is
/// best placed to correct their own typo.
class RecordDetailScreen extends ConsumerStatefulWidget {
  const RecordDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  ConsumerState<RecordDetailScreen> createState() =>
      _RecordDetailScreenState();
}

class _RecordDetailScreenState extends ConsumerState<RecordDetailScreen>
    with RecordFormFields {
  late Future<CoreRecordDetail> _record = _load();

  /// What the header leads with — the product code where a consignment
  /// exists, the design code otherwise. See the rule this app follows
  /// everywhere: the product code is the identification, the design code is
  /// internal.
  String? _displayCode;

  /// Blank means "leave the ledger alone" — the same convention the server's
  /// own draft uses, so a correction is only ever a stated intention.
  final _quantity = TextEditingController();
  final _quantityFocus = FocusNode();

  bool _busy = false;
  CoreRecordDetail? _current;

  Future<CoreRecordDetail> _load() async {
    final api = ref.read(coreApiProvider);
    final data = ((await api.get('/records/${widget.recordId}')) as Map)
        .cast<String, dynamic>();

    final record = CoreRecordDetail.fromJson(data);

    /*
      In a setState, not a bare assignment.

      `_seed` sets the fields the AppBar reads — the product code in the
      title, the camera button's enabled state — and the AppBar is built
      alongside the FutureBuilder, not inside it. FutureBuilder rebuilding
      itself when this future resolves does not reach a sibling; without this,
      the title sat on "Product" until something else happened to rebuild the
      screen.
    */
    if (mounted) {
      setState(() => _seed(record));
    } else {
      _seed(record);
    }

    return record;
  }

  /// Populate the shared form fields from the record as it stands — the
  /// starting point for a partial update, same as `draftFromRecord` on the
  /// server.
  void _seed(CoreRecordDetail record) {
    _current = record;
    attrs
      ..clear()
      ..addAll(record.attributes);
    descriptors = List.of(record.descriptors);
    imageSlots = [
      for (final image in record.images)
        if (image.slotId != null) image.slotId!,
    ];
    colourId = record.colourId;
    secondaryColourId = record.secondaryColourId;

    for (final p in priceKinds) {
      final minor = switch (p.key) {
        'cost' => record.costMinor,
        'making' => record.makingMinor,
        'wholesale' => record.wholesaleMinor,
        'retail' => record.retailMinor,
        'mrp' => record.mrpMinor,
        _ => null,
      };
      prices[p.key]!.text = minor == null ? '' : '${minor / 100}';
    }

    notesField.text = record.notes ?? '';
    nameField.text = record.nameIsCustom ? record.name : '';
    nameIsCustom = record.nameIsCustom;

    _displayCode = record.consignments.isEmpty
        ? record.code
        : record.consignments.first.code;
  }

  @override
  void dispose() {
    disposeFormFields();
    _quantity.dispose();
    _quantityFocus.dispose();
    super.dispose();
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  Future<void> _submit(CoreOptions options) async {
    setState(() {
      _busy = true;
      fieldErrors = const {};
    });

    try {
      final api = ref.read(coreApiProvider);
      final correction = _quantity.text.trim();

      final answer = ((await api.patch('/records/${widget.recordId}', body: {
        'attributes': attributesForSubmit(options),
        'descriptors': descriptors,
        'colourId': colourId,
        'secondaryColourId': secondaryColourId,
        'prices': {
          for (final p in priceKinds) p.key: prices[p.key]!.text.trim(),
        },
        'imageSlots': imageSlots,
        'notes': notesField.text.trim(),
        'name': nameIsCustom ? nameField.text.trim() : '',
        'nameIsCustom': nameIsCustom,
        // Omitted rather than sent blank: the server reads a missing key as
        // "do not touch the ledger" and an empty one the same way, but
        // omitting says it plainly instead of relying on a value nobody typed.
        if (correction.isNotEmpty) 'quantity': correction,
      })) as Map)
          .cast<String, dynamic>();

      if (!mounted) return;

      /*
        How far this reached, said plainly.

        Attributes belong to the design, which a colour shares with its
        siblings — so an edit to the fibre of one record silently changes it
        for every colour of that saree. The API says so in its answer; a
        screen that could not repeat it back would be the one place that
        does not warn anyone.
      */
      final also = answer['alsoChanged'] as int?;
      showOk(
        context,
        also == null || also == 0
            ? 'Saved.'
            : 'Saved. Also changed on $also other colour${also == 1 ? '' : 's'}.',
      );

      _quantity.clear();
      setState(() {
        _record = _load();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errors.isNotEmpty) setState(() => fieldErrors = e.errors);
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPhotos() {
    final code = _displayCode ?? widget.recordId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RecordPhotosScreen(recordId: widget.recordId, code: code),
      ),
    );
  }

  /// A new colourway of this same design, one tap away from the record it
  /// came from rather than thirty fields re-typed from a saree lying next to
  /// it. See [NewRecordScreen.seedFrom] for exactly what carries over.
  void _duplicate() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewRecordScreen(seedFrom: _current),
      ),
    );
  }

  /// Archive, or — for an owner — delete outright. The dialog does its own
  /// talking to the API and hands back the server's own sentence on success;
  /// this only has to act on it. Shown before popping so the same
  /// ScaffoldMessenger carries it over onto the list the record vanished
  /// from — staying here to read it makes no sense once it's gone or
  /// inactive.
  Future<void> _archive() async {
    final canDelete = ref.read(coreAuthProvider).actor?.role == 'owner';

    final message = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ArchiveDialog(recordId: widget.recordId, canDelete: canDelete),
    );

    if (message == null || !mounted) return;
    showOk(context, message);
    // Otherwise Products List still shows this row until somebody pulls to
    // refresh — it was never told the record it's holding just vanished.
    ref.invalidate(coreRecordsProvider);
    Navigator.of(context).pop();
  }

  // ── Building ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(coreOptionsProvider);
    final locations = ref.watch(coreLocationsProvider);
    final actor = ref.watch(coreAuthProvider).actor;

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: context.p.surface1,
        appBar: AppBar(
          title: _Title(code: _displayCode, designCode: _current?.code),
          actions: [
            IconButton(
              tooltip: 'Duplicate as a new colourway',
              icon: const Icon(Icons.copy_outlined),
              onPressed: _current == null ? null : _duplicate,
            ),
            IconButton(
              tooltip: 'Photographs',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: _current == null ? null : _openPhotos,
            ),
            // Desk work, by this app's own reasoning (see core_home_screen's
            // doc comment) — shown at all only to office and owner, the same
            // way the web's "Delete instead" only appears for an owner. The
            // real gate is the server's guard("office")/guard("owner");
            // hiding the icon here is a courtesy, not the enforcement.
            if (actor != null &&
                (actor.role == 'office' || actor.role == 'owner'))
              IconButton(
                tooltip: 'Archive or delete',
                icon: const Icon(Icons.archive_outlined),
                onPressed: _current == null ? null : _archive,
              ),
          ],
          bottom: TabBar(
            // Seven tabs since Publish joined the other six — the fixed
            // width that fit six no longer does, so a scroll affordance
            // beats a clipped label.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: context.p.onAppBar,
            unselectedLabelColor: context.p.onAppBar.withValues(alpha: 0.72),
            indicatorColor: context.p.onAppBar,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            labelStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 12.5),
            tabs: () {
              final counts = tabErrorCounts(fieldErrors);
              return [
                tabWithErrorBadge('Basic', counts[0] ?? 0),
                tabWithErrorBadge('Craft', counts[1] ?? 0),
                const Tab(text: 'Details'),
                tabWithErrorBadge('Prices', counts[3] ?? 0),
                const Tab(text: 'Images'),
                tabWithErrorBadge('Stock', counts[5] ?? 0),
                const Tab(text: 'Publish'),
              ];
            }(),
          ),
        ),
        // A numeric keypad has no return key of its own to dismiss it with —
        // tapping anywhere outside the field it belongs to is the fallback
        // every other kind of field already gets for free.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: AsyncView<CoreOptions>(
            value: options,
            onRetry: () => ref.invalidate(coreOptionsProvider),
            data: (opts) => FutureBuilder<CoreRecordDetail>(
              future: _record,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _Retry(
                    message: '${snap.error}',
                    onRetry: () => setState(() {
                      _record = _load();
                    }),
                  );
                }

                return _tabs(
                    opts, snap.data!, actor, locations.value ?? const []);
              },
            ),
          ),
        ),
        bottomNavigationBar: RecordSaveBar(
          busy: _busy,
          errors: fieldErrors,
          label: 'Save changes',
          focusNodes: {...priceFocusNodes, 'quantity': _quantityFocus},
          onSave: () {
            final opts = options.value;
            if (opts != null) _submit(opts);
          },
        ),
      ),
    );
  }

  Widget _tabs(
    CoreOptions o,
    CoreRecordDetail record,
    CoreActor? actor,
    List<CoreLocation> locations,
  ) {
    final industry = labelOf(o, 'industry', attrs['industry']);
    final home = isHomeIndustry(industry);

    final productType = home
        ? labelOf(o, 'home_product_type', attrs['homeProductType'])
        : labelOf(o, 'product_type', attrs['productType']);

    final isSaree = !home && productType == 'Saree';

    final subTypes = narrow(o['garment_type'], attrs['productType']);
    final hasSubTypes = !home && subTypes.isNotEmpty;

    final isGarment = hasSubTypes && !isSaree && (attrs['garmentType'] != null);

    final withBlouse =
        labelOf(o, 'garment_type', attrs['garmentType']) == 'With Blouse';

    final uom = labelOf(o, 'uom', attrs['uom']);
    final craft = labelOf(o, 'craft_technique', attrs['craftTechnique']);

    return TabBarView(
      children: [
        buildBasicTab(
          o: o,
          home: home,
          hasSubTypes: hasSubTypes,
          isSaree: isSaree,
          isGarment: isGarment,
          uom: uom,
          header: [
            if (actor != null) ...[
              SignedInActor(actor: actor),
              const SizedBox(height: 14),
            ],
            /*
              Attributes belong to the design, not the colour.

              Said before anyone changes one, not discovered after: a design
              with more than one active colour shares every field on this tab,
              on Craft and on Details, and a fibre corrected here is corrected
              on all of them. Colour, prices, images and stock stay this
              colourway's own.
            */
            if (record.siblings.length > 1)
              RecordNote(
                'These attributes belong to the design, which has '
                '${record.siblings.length} colours — '
                '${record.siblings.map((s) => s.colour ?? "unset").join(", ")}. '
                'A change here applies to all of them. Colour, prices and '
                'stock are for this one only.',
              ),
          ],
        ),
        buildCraftTab(o, craft),
        buildDetailsTab(o, isSaree, withBlouse),
        buildPricesTab(uom),
        buildImagesTab(
          o,
          home,
          note: 'A slot with a photograph in it is not removed by '
              'un-ticking it here — that would delete the photograph by '
              'implication. Remove one from the Photographs screen instead.',
        ),
        _stock(record, uom, locations),
        _publish(record, actor),
      ],
    );
  }

  // ── Stock ─────────────────────────────────────────────────────────────────

  Widget _stock(
    CoreRecordDetail record,
    String? uom,
    List<CoreLocation> locations,
  ) {
    final unit = record.isSerialised ? 'pieces' : 'units';
    final stock = record.stock;

    final tiles = <(String, int, String)>[
      ('Available', stock.onHand, 'on the shelf now'),
      ('Received', stock.received, 'all time'),
      ('Sold', stock.sold, 'all time'),
      ('Damaged', stock.damaged, 'written off'),
      ('Returned', stock.returned, 'came back'),
      ('Adjusted', stock.adjusted, 'count corrections'),
    ];

    return RecordTabBody(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.05,
          children: [for (final t in tiles) _StockTile(t.$1, t.$2, t.$3)],
        ),

        const RecordSectionHeading('Stock availability'),
        if (stock.byLocation.isEmpty)
          RecordNote('Nothing on hand.')
        else
          _LocationTable(rows: stock.byLocation, unit: unit),

        const RecordSectionHeading('Record a movement'),
        Text(
          'Received, returned, sold, damaged or transferred — one line added '
          'to the ledger, never a total overwritten.',
          style: TextStyle(fontSize: 12, color: context.p.textSecondary),
        ),
        const SizedBox(height: 8),
        _RecordMovementForm(
          recordId: widget.recordId,
          stock: stock,
          locations: locations,
          uom: uom,
          onRecorded: (message) {
            showOk(context, message);
            setState(() {
              _record = _load();
            });
          },
        ),

        if (record.movements.isNotEmpty) ...[
          const RecordSectionHeading('Recent movements'),
          for (final m in record.movements) _MovementCard(m),
        ],

        const RecordSectionHeading('Consignments received'),
        Text(
          'Each delivery has its own product code, and the pieces in it '
          'their own item codes.',
          style: TextStyle(fontSize: 12, color: context.p.textSecondary),
        ),
        const SizedBox(height: 8),
        if (record.consignments.isEmpty)
          RecordNote(
            'Nothing recorded as received yet. Stock entered before '
            'consignments existed shows only in the counts above.',
          )
        else
          for (final c in record.consignments) _ConsignmentCard(c),

        const RecordSectionHeading('Correct the count'),
        Text(
          'For when the shelf and the system disagree and nobody knows why. '
          'This writes an adjustment; it never overwrites the number.',
          style: TextStyle(fontSize: 12, color: context.p.textSecondary),
        ),
        const SizedBox(height: 8),
        RecordFieldWrap(
          error: fieldErrors['quantity'],
          child: TextField(
            controller: _quantity,
            focusNode: _quantityFocus,
            enabled: !record.isSerialised,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(
              () => fieldErrors = {...fieldErrors}..remove('quantity'),
            ),
            decoration: InputDecoration(
              labelText: uom == null
                  ? 'Quantity on hand'
                  : 'Quantity on hand ($uom)',
              hintText: '${stock.onHand}',
              border: const OutlineInputBorder(),
              helperText: record.isSerialised
                  ? 'Serialised — the count is how many pieces are tagged, so '
                      'it changes piece by piece.'
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  // ── Publish ───────────────────────────────────────────────────────────────

  Widget _publish(CoreRecordDetail record, CoreActor? actor) {
    final canPublish =
        actor != null && (actor.role == 'office' || actor.role == 'owner');

    final checklist = <(String, bool)>[
      ('Retail price set', prices['retail']!.text.trim().isNotEmpty),
      ('At least one photograph', record.images.any((i) => i.url != null)),
      ('Colour set', colourId != null),
      ('Fibre type set', attrs['fibreType'] != null),
      ('Craft technique set', attrs['craftTechnique'] != null),
    ];

    return RecordTabBody(
      children: [
        const RecordSectionHeading('Ready to be seen?'),
        Text(
          'Publishing still works either way — a listing missing these just '
          'says less than it could.',
          style: TextStyle(fontSize: 12, color: context.p.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final item in checklist) _ChecklistRow(item.$1, item.$2),

        if (!canPublish) ...[
          const SizedBox(height: 8),
          RecordNote(
            'Publishing is office and above. What follows is here to see, '
            "not to use — ask whoever holds that role on this account.",
          ),
        ],

        const RecordSectionHeading('Consignments'),
        if (record.consignments.isEmpty)
          RecordNote(
            'Nothing recorded as received yet — nothing to publish until '
            'something has.',
          )
        else
          for (final c in record.consignments)
            _PublishConsignmentPanel(
              recordId: widget.recordId,
              consignment: c,
              canPublish: canPublish,
              onChanged: () => setState(() {
                _record = _load();
              }),
            ),
      ],
    );
  }
}

// ── Chrome specific to this screen ───────────────────────────────────────────

class _Title extends StatelessWidget {
  const _Title({required this.code, required this.designCode});

  final String? code;
  final String? designCode;

  @override
  Widget build(BuildContext context) {
    if (code == null) return const Text('Product');

    // The design code shown only when it differs from what is already
    // leading — a record with no consignment leads with it too, and showing
    // the same thing twice says nothing a second time.
    final showDesignCode = designCode != null && designCode != code;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code!,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (showDesignCode)
          Text(
            designCode!,
            style: TextStyle(
              fontSize: 11.5,
              color: context.p.onAppBar.withValues(alpha: 0.75),
            ),
          ),
      ],
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile(this.label, this.value, this.detail);

  final String label;
  final int value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: p.textSecondary)),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: label == 'Damaged' && value > 0 ? p.danger : p.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(detail,
              style: TextStyle(fontSize: 10, color: p.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _LocationTable extends StatelessWidget {
  const _LocationTable({required this.rows, required this.unit});

  final List<CoreStockAtLocation> rows;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final total = rows.fold<int>(0, (sum, r) => sum + r.qty);

    return Container(
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.location,
                        style: TextStyle(fontSize: 13, color: p.textSecondary)),
                  ),
                  Text(
                    '${r.qty} $unit',
                    style: TextStyle(
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: p.surface3,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Total',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                ),
                Text(
                  '$total $unit',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsignmentCard extends StatelessWidget {
  const _ConsignmentCard(this.consignment);

  final CoreConsignment consignment;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                consignment.code,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: p.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '${consignment.qty} · ${consignment.location ?? "gone"}',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              consignment.receivedAt,
              if (consignment.reference != null) consignment.reference!,
            ].join(' · '),
            style: TextStyle(fontSize: 11.5, color: p.textMuted),
          ),
          if (consignment.items.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final item in consignment.items)
                  Text(
                    item,
                    style: TextStyle(
                      fontSize: 11,
                      color: p.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the ledger — the vocabulary from the web's `MOVEMENT_KINDS`,
/// kept here as plain data rather than a network round trip to read a
/// constant.
const _movementKinds = [
  (key: 'received', label: 'Received', dir: 'in'),
  (key: 'returned', label: 'Returned', dir: 'in'),
  (key: 'sold', label: 'Sold', dir: 'out'),
  (key: 'damaged', label: 'Damaged', dir: 'out'),
  (key: 'transferred', label: 'Transferred', dir: 'out'),
];

String movementDirOf(String kind) =>
    _movementKinds.firstWhere((k) => k.key == kind, orElse: () => _movementKinds.first).dir;

/// Locations to offer for the "from"/"location" field, given the movement's
/// direction.
///
/// Unfiltered for an "in" movement — stock can land anywhere internal. For
/// an "out" movement, narrowed to locations the ledger summary says
/// currently hold something, the same UX assistance the web gives (the
/// authoritative check stays server-side in `recordMovement`). Never left
/// with nothing to choose from: a summary that disagrees with reality —
/// stale, or a location just added — falls back to the full internal list
/// rather than locking the field.
List<CoreLocation> movementLocationOptions({
  required String kind,
  required List<CoreLocation> internal,
  required List<CoreStockAtLocation> byLocation,
}) {
  if (movementDirOf(kind) == 'in') return internal;

  final holding = {for (final s in byLocation) if (s.qty > 0) s.location};
  final narrowed = [for (final l in internal) if (holding.contains(l.name)) l];
  return narrowed.isEmpty ? internal : narrowed;
}

/// Received, returned, sold, damaged or transferred — one append to the
/// ledger. Never a total overwritten, which is the whole reason this is a
/// form and not a number somebody edits.
class _RecordMovementForm extends ConsumerStatefulWidget {
  const _RecordMovementForm({
    required this.recordId,
    required this.stock,
    required this.locations,
    required this.uom,
    required this.onRecorded,
  });

  final String recordId;
  final CoreStock stock;
  final List<CoreLocation> locations;
  final String? uom;

  /// Called with the server's own sentence describing what happened —
  /// "Received 12 into Warehouse", not a generic "Saved."
  final void Function(String message) onRecorded;

  @override
  ConsumerState<_RecordMovementForm> createState() =>
      _RecordMovementFormState();
}

class _RecordMovementFormState extends ConsumerState<_RecordMovementForm> {
  String _kind = 'received';
  String? _locationId;
  String? _toLocationId;
  final _qty = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();

  bool _busy = false;
  String? _error;

  /// Kept across retries of the same attempt, the same way a new record's
  /// save key is — cleared only once the server has actually recorded it, so
  /// a dropped connection followed by pressing Record again is recognised as
  /// the same intent rather than becoming a second line in the ledger.
  String? _key;

  @override
  void dispose() {
    _qty.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  List<CoreLocation> get _internal =>
      [for (final l in widget.locations) if (l.isInternal) l];

  /// Narrowed to where this design currently holds stock, for an "out"
  /// movement — the same UX assistance the web gives, not the authoritative
  /// check, which stays server-side. Falls back to every internal location
  /// rather than leaving the field with nothing to choose, since the ledger
  /// summary and this list can disagree in ways worth letting through rather
  /// than silently hiding (a location added since the summary was fetched,
  /// for one).
  List<CoreLocation> get _fromOptions => movementLocationOptions(
        kind: _kind,
        internal: _internal,
        byLocation: widget.stock.byLocation,
      );

  List<CoreLocation> get _toOptions =>
      [for (final l in _internal) if (l.id != _locationId) l];

  Future<void> _submit() async {
    if (_locationId == null) {
      setState(() => _error = 'Choose a location.');
      return;
    }
    if (_kind == 'transferred' && _toLocationId == null) {
      setState(() => _error = 'Choose where it is going.');
      return;
    }
    final qty = _qty.text.trim();
    if (qty.isEmpty) {
      setState(() => _error = 'How many? It has to be a number above zero.');
      return;
    }

    final key = _key ??= idempotencyKey();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data = await ref.read(coreApiProvider).post(
        '/records/${widget.recordId}/movements',
        headers: {'Idempotency-Key': key},
        body: {
          'kind': _kind,
          'locationId': _locationId,
          if (_kind == 'transferred') 'toLocationId': _toLocationId,
          'qty': qty,
          'reference': _reference.text.trim(),
          'note': _note.text.trim(),
        },
      );

      _key = null;
      _qty.clear();
      _reference.clear();
      _note.clear();
      if (mounted) {
        setState(() {
          _locationId = null;
          _toLocationId = null;
        });
      }

      final message = (data as Map)['message'] as String? ?? 'Recorded.';
      widget.onRecorded(message);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isTransfer = _kind == 'transferred';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in _movementKinds)
              ChoiceChip(
                label: Text(k.label),
                selected: _kind == k.key,
                onSelected: (_) => setState(() {
                  _kind = k.key;
                  _locationId = null;
                  _toLocationId = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        RecordFieldWrap(
          child: PickerField(
            label: isTransfer ? 'From' : 'Location',
            value: _locationId,
            options: [
              for (final l in _fromOptions) PickerOption(l.id, l.name),
            ],
            onChanged: (v) => setState(() {
              _locationId = v;
              if (_toLocationId == v) _toLocationId = null;
            }),
          ),
        ),
        if (isTransfer)
          RecordFieldWrap(
            child: PickerField(
              label: 'To',
              value: _toLocationId,
              hint: _locationId == null ? 'Choose From first' : 'Select',
              options: [for (final l in _toOptions) PickerOption(l.id, l.name)],
              onChanged: (v) => setState(() => _toLocationId = v),
            ),
          ),
        RecordFieldWrap(
          child: TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: widget.uom == null ? 'How many' : 'How many (${widget.uom})',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        RecordFieldWrap(
          child: TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Reference',
              hintText: 'Invoice or challan number',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        RecordFieldWrap(
          child: TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Record'),
          ),
        ),
      ],
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard(this.movement);

  final CoreMovement movement;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final kindLabel = _movementKinds
        .firstWhere(
          (k) => k.key == movement.kind,
          orElse: () => (key: movement.kind, label: movement.kind, dir: 'in'),
        )
        .label;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                kindLabel,
                style: TextStyle(fontWeight: FontWeight.w700, color: p.text),
              ),
              const Spacer(),
              Text(
                '${movement.qty}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (movement.from != null && movement.to != null)
                '${movement.from} → ${movement.to}'
              else if (movement.to != null)
                'into ${movement.to}'
              else if (movement.from != null)
                'out of ${movement.from}',
              movement.occurredAt,
              if (movement.reason != null) movement.reason!,
            ].whereType<String>().join(' · '),
            style: TextStyle(fontSize: 11.5, color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Archive, or — one step further, for an owner — delete outright.
///
/// One dialog for both, escalating rather than offering two entry points:
/// "Delete instead" only appears at all once you can do it, and choosing it
/// swaps the whole dialog to a stronger warning instead of opening a second
/// one. A dialog is not a permission — the server's `guard` decides what
/// actually happens; this only decides what somebody has to click through
/// first.
class _ArchiveDialog extends ConsumerStatefulWidget {
  const _ArchiveDialog({required this.recordId, required this.canDelete});

  final String recordId;
  final bool canDelete;

  @override
  ConsumerState<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends ConsumerState<_ArchiveDialog> {
  bool _confirmingDelete = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<dynamic> Function(ApiClient api) call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await call(ref.read(coreApiProvider));
      final message = (data as Map)['message'] as String? ?? 'Done.';
      if (mounted) Navigator.of(context).pop(message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return AlertDialog(
      title: Text(_confirmingDelete ? 'Delete this record?' : 'Archive this record?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _confirmingDelete
                ? 'This cannot be undone, and the stock history goes with '
                    'it — every movement, piece and photograph this colour '
                    'has.'
                : 'Taken out of the active catalogue. Its stock history is '
                    'kept, and this can be undone on the web.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.canDelete && !_confirmingDelete)
          TextButton(
            onPressed:
                _busy ? null : () => setState(() => _confirmingDelete = true),
            child: Text('Delete instead', style: TextStyle(color: p.danger)),
          ),
        FilledButton(
          style: _confirmingDelete
              ? FilledButton.styleFrom(backgroundColor: p.danger)
              : null,
          onPressed: _busy
              ? null
              : () => _confirmingDelete
                  ? _run((api) => api.delete('/records/${widget.recordId}'))
                  : _run((api) => api.post('/records/${widget.recordId}/archive')),
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_confirmingDelete ? 'Delete' : 'Archive'),
        ),
      ],
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.p.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow(this.label, this.done);

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? p.success : p.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: done ? p.text : p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One consignment's place on every channel this business sells through,
/// and the listing wording it can override. Every channel is always shown,
/// published or not — "which channels exist" is simply every row of the
/// channel table, the same as the web.
class _PublishConsignmentPanel extends ConsumerStatefulWidget {
  const _PublishConsignmentPanel({
    required this.recordId,
    required this.consignment,
    required this.canPublish,
    required this.onChanged,
  });

  final String recordId;
  final CoreConsignment consignment;
  final bool canPublish;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PublishConsignmentPanel> createState() =>
      _PublishConsignmentPanelState();
}

class _PublishConsignmentPanelState
    extends ConsumerState<_PublishConsignmentPanel> {
  late final _title = TextEditingController(text: widget.consignment.title ?? '');
  late final _description =
      TextEditingController(text: widget.consignment.description ?? '');
  late final _weight = TextEditingController(
    text: widget.consignment.weightGrams?.toString() ?? '',
  );
  late final _hsn = TextEditingController(text: widget.consignment.hsnCode ?? '');

  /// Which channel is mid-publish, if any — so one button shows its own
  /// spinner rather than every button on the panel freezing for a request
  /// that only concerns one of them.
  String? _publishing;
  bool _savingListing = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _weight.dispose();
    _hsn.dispose();
    super.dispose();
  }

  Future<void> _publish(String channelCode) async {
    setState(() {
      _publishing = channelCode;
      _error = null;
    });
    try {
      final data = await ref.read(coreApiProvider).post(
        '/records/${widget.recordId}/consignments/${widget.consignment.id}/publish',
        body: {'channelCode': channelCode},
      );
      final message = (data as Map)['message'] as String? ?? 'Published.';
      if (mounted) {
        showOk(context, message);
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _publishing = null);
    }
  }

  Future<void> _saveListing() async {
    setState(() {
      _savingListing = true;
      _error = null;
    });
    try {
      final weight = _weight.text.trim();
      await ref.read(coreApiProvider).patch(
        '/records/${widget.recordId}/consignments/${widget.consignment.id}/listing',
        body: {
          'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
          'description':
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          'weightGrams': weight.isEmpty ? null : int.tryParse(weight),
          'hsnCode': _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
        },
      );
      if (mounted) {
        showOk(context, 'Listing saved.');
        widget.onChanged();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _savingListing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = widget.consignment;
    final disabled = !widget.canPublish;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                c.code,
                style: TextStyle(fontWeight: FontWeight.w700, color: p.primary),
              ),
              const Spacer(),
              Text(
                '${c.qty} · ${c.location ?? "gone"}',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final ch in c.channels)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    ch.isPublished ? Icons.check_circle : Icons.circle_outlined,
                    size: 16,
                    color: ch.isPublished ? p.success : p.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ch.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: ch.isPublished ? p.text : p.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: disabled || _publishing != null
                          ? null
                          : () => _publish(ch.code),
                      child: _publishing == ch.code
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(ch.isPublished ? 'Republish' : 'Publish'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'Listing overrides',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
            children: [
              RecordFieldWrap(
                child: TextField(
                  controller: _title,
                  enabled: !disabled,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Blank composes it from the design',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              RecordFieldWrap(
                child: TextField(
                  controller: _description,
                  enabled: !disabled,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              RecordFieldWrap(
                child: TextField(
                  controller: _weight,
                  enabled: !disabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Weight (grams)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              RecordFieldWrap(
                child: TextField(
                  controller: _hsn,
                  enabled: !disabled,
                  decoration: const InputDecoration(
                    labelText: 'HSN code',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: disabled || _savingListing ? null : _saveListing,
                  child: _savingListing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save listing'),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
            ),
        ],
      ),
    );
  }
}
