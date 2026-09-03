import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'core_auth.dart';
import 'record_fields.dart';
import 'record_form_fields.dart';
import 'record_photos_screen.dart';

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

  // ── Building ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(coreOptionsProvider);
    final actor = ref.watch(coreAuthProvider).actor;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: context.p.surface1,
        appBar: AppBar(
          title: _Title(code: _displayCode, designCode: _current?.code),
          actions: [
            IconButton(
              tooltip: 'Photographs',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: _current == null ? null : _openPhotos,
            ),
          ],
          bottom: TabBar(
            labelColor: context.p.onAppBar,
            unselectedLabelColor: context.p.onAppBar.withValues(alpha: 0.72),
            indicatorColor: context.p.onAppBar,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 12.5),
            tabs: const [
              Tab(text: 'Basic'),
              Tab(text: 'Craft'),
              Tab(text: 'Details'),
              Tab(text: 'Prices'),
              Tab(text: 'Images'),
              Tab(text: 'Stock'),
            ],
          ),
        ),
        body: AsyncView<CoreOptions>(
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

              return _tabs(opts, snap.data!, actor);
            },
          ),
        ),
        bottomNavigationBar: RecordSaveBar(
          busy: _busy,
          errors: fieldErrors,
          label: 'Save changes',
          onSave: () {
            final opts = options.value;
            if (opts != null) _submit(opts);
          },
        ),
      ),
    );
  }

  Widget _tabs(CoreOptions o, CoreRecordDetail record, CoreActor? actor) {
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
        _stock(record, uom),
      ],
    );
  }

  // ── Stock ─────────────────────────────────────────────────────────────────

  Widget _stock(CoreRecordDetail record, String? uom) {
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
            enabled: !record.isSerialised,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
