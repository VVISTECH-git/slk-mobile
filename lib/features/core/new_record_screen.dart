import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import 'core_auth.dart';
import 'core_sign_in_screen.dart';
import 'multi_picker_field.dart';
import 'record_fields.dart';
import 'record_photos_screen.dart';

/// A new record, with every question the web editor asks.
///
/// Field-for-field parity with /records, laid out as tabs rather than a
/// wizard: the web editor's steps assume a mouse and a wide screen, and a
/// phone that hides Prices three taps deep is a phone somebody stops using.
///
/// The rules are ported, not re-invented — which matters more than the fields.
/// Product Type narrows to the industry and switches list entirely for the
/// home one; Motif narrows to its category; Textile Material narrows to the
/// fibre and falls through to the unparented ten when that fibre names none;
/// Unit of Measure is shown and never asked. Getting a rule slightly different
/// here from the web is how two people filing the same saree produce two
/// different records.
class NewRecordScreen extends ConsumerStatefulWidget {
  const NewRecordScreen({super.key});

  @override
  ConsumerState<NewRecordScreen> createState() => _NewRecordScreenState();
}

class _NewRecordScreenState extends ConsumerState<NewRecordScreen> {
  /// Attribute key → chosen lookup value id.
  final Map<String, String?> _attrs = {};

  List<String> _descriptors = [];
  List<String> _imageSlots = [];

  String? _colourId;
  String? _secondaryColourId;
  String? _location;

  final _prices = {
    for (final p in priceKinds) p.key: TextEditingController(),
  };
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  final _name = TextEditingController();

  bool _nameIsCustom = false;
  bool _defaultsApplied = false;
  bool _busy = false;

  /// Held so the Basic tab can name who is filing, without threading the
  /// actor through five layers of builder to reach one chip.
  CoreActor? _actor;

  /// The name of the save in progress.
  ///
  /// Minted on the first Create and kept for every retry of the same draft, so
  /// a lost answer followed by a second press is recognised as the same intent
  /// rather than becoming a second record. Cleared only on success, which is
  /// what makes the next record a genuinely new one.
  ///
  /// Minting it per tap instead would be the bug: that is precisely how
  /// SAR-GEN-COT-0009 came to exist.
  String? _saveKey;

  Map<String, String> _errors = const {};

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    _qty.dispose();
    _notes.dispose();
    _name.dispose();
    super.dispose();
  }

  // ── Reading the vocabulary ────────────────────────────────────────────────

  String? _labelOf(CoreOptions options, String list, String? id) {
    if (id == null) return null;
    for (final o in options[list] ?? const <CoreOption>[]) {
      if (o.id == id) return o.label;
    }
    return null;
  }

  CoreOption? _optionOf(CoreOptions options, String list, String? id) {
    if (id == null) return null;
    for (final o in options[list] ?? const <CoreOption>[]) {
      if (o.id == id) return o;
    }
    return null;
  }

  List<PickerOption> _pick(List<CoreOption>? values) => [
        for (final o in values ?? const <CoreOption>[])
          PickerOption(o.id, o.label, color: o.swatch),
      ];

  void _set(String key, String? value) => setState(() {
        _attrs[key] = value;
        _errors = {..._errors}..remove(key);
      });

  // ── Saving ────────────────────────────────────────────────────────────────

  Future<void> _submit(CoreOptions options) async {
    final home = isHomeIndustry(_labelOf(options, 'industry', _attrs['industry']));

    /*
      Only the keys this form actually asks, and only under the industry that
      owns them. The API refuses a record carrying both a Saree and a Bedsheets
      product type — rightly, since nobody could explain it later — so the
      other industry's answers are dropped rather than sent and rejected.
    */
    final attributes = <String, String?>{};
    for (final key in attributeLists.keys) {
      if (home && (key == 'productType' || key == 'garmentType')) continue;
      if (!home && (key == 'homeProductType' || key == 'homeWeavingCategory')) {
        continue;
      }
      if (_attrs.containsKey(key)) attributes[key] = _attrs[key];
    }

    // Kept across retries, minted only when there is no save in flight.
    final key = _saveKey ??= idempotencyKey();

    setState(() {
      _busy = true;
      _errors = const {};
    });

    try {
      final api = ref.read(coreApiProvider);

      final created = await api.post('/records', headers: {
        'Idempotency-Key': key,
      }, body: {
        'attributes': attributes,
        'descriptors': _descriptors,
        'colourId': _colourId,
        'secondaryColourId': _secondaryColourId,
        'prices': {
          for (final p in priceKinds) p.key: _prices[p.key]!.text.trim(),
        },
        'openingStock': [
          if (_location != null && _qty.text.trim().isNotEmpty)
            {'locationId': _location, 'qty': _qty.text.trim()},
        ],
        'imageSlots': _imageSlots,
        'notes': _notes.text.trim(),
        'name': _nameIsCustom ? _name.text.trim() : '',
        'nameIsCustom': _nameIsCustom,
      });

      final id = ((created as Map).cast<String, dynamic>())['id'] as String;

      // Read it back for the code — SAR-SRI-SIL-0042 — which is what gets
      // printed on the label and what the person who just filed it will be
      // asked about.
      String? code;
      try {
        final record = await api.get('/records/$id');
        code = ((record as Map).cast<String, dynamic>())['code'] as String?;
      } catch (_) {
        // The record exists either way.
      }

      if (!mounted) return;

      showOk(context, code == null ? 'Record created.' : 'Created $code.');

      final slots = _imageSlots.isNotEmpty;
      _resetForNext();

      /*
        Straight on to the camera, if this record asked for photographs.

        The record now exists, which is the only reason it could not be done
        before — a photograph belongs to a colourway. Making somebody find the
        record again afterwards is how shot lists stay empty.
      */
      if (slots && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecordPhotosScreen(
              recordId: id,
              code: code ?? 'new record',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errors.isNotEmpty) setState(() => _errors = e.errors);
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Keep what repeats, clear what does not.
  ///
  /// A delivery is ten of nearly the same thing: same taxonomy, same location,
  /// different colour, price and count. Clearing everything would make the
  /// second record as slow as the first.
  void _resetForNext() {
    setState(() {
      // The save that key named is finished. The next record is a new intent
      // and gets a new name; keeping this one would make it a "duplicate" of
      // the record just created and be refused.
      _saveKey = null;
      _colourId = null;
      _secondaryColourId = null;
      for (final c in _prices.values) {
        c.clear();
      }
      _qty.clear();
      _notes.clear();
      _name.clear();
      _nameIsCustom = false;
      _errors = const {};
    });
  }

  // ── Building ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(coreAuthProvider);
    if (!auth.isSignedIn) return const _SignInPrompt();

    final options = ref.watch(coreOptionsProvider);
    final locations = ref.watch(coreLocationsProvider);

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: context.p.surface1,
        appBar: AppBar(
          title: const Text('New record'),
          actions: [
            IconButton(
              tooltip: 'Sign out of slk-core',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(coreAuthProvider.notifier).signOut(),
            ),
          ],
          /*
            Six fixed tabs, none of them scrollable.

            A scrollable bar put Basic off the left edge — the first tab, on a
            form that opens on it — and even fixed that, a bar you have to
            scroll hides half the form from somebody who does not know it is
            there. Six short labels fit, so the whole shape of the record is
            visible at a glance.

            "Craft" rather than the web's "Craft & Design", for the same
            reason: the tab has to fit a sixth of a phone.
          */
          bottom: TabBar(
            /*
              Colours stated, not inherited.

              The app defines no TabBarTheme, so Material 3 defaults the
              selected label to colorScheme.primary — which is this app bar's
              own terracotta. The selected tab painted itself onto its own
              background and vanished, and since the form opens on Basic, the
              tab that vanished was the one you were looking at.
            */
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
          data: (opts) => AsyncView<List<CoreLocation>>(
            value: locations,
            onRetry: () => ref.invalidate(coreLocationsProvider),
            data: (places) {
              // Applied once, after the vocabulary arrives — Clothing, Saree
              // and the rest, so the common case is already filled in.
              if (!_defaultsApplied) {
                _defaultsApplied = true;
                _attrs.addAll(defaultAttributes(opts));
              }

              return _tabs(opts, places, auth.actor!);
            },
          ),
        ),
        bottomNavigationBar: _SaveBar(
          busy: _busy,
          errors: _errors,
          onSave: () {
            final opts = options.value;
            if (opts != null) _submit(opts);
          },
        ),
      ),
    );
  }

  Widget _tabs(CoreOptions o, List<CoreLocation> places, CoreActor actor) {
    _actor = actor;

    final industry = _labelOf(o, 'industry', _attrs['industry']);
    final home = isHomeIndustry(industry);

    final productType = home
        ? _labelOf(o, 'home_product_type', _attrs['homeProductType'])
        : _labelOf(o, 'product_type', _attrs['productType']);

    final isSaree = !home && productType == 'Saree';

    // Which sub types a product type has is data, not code — a saree's are its
    // layouts, a garment's its cuts, and a type with none is not asked.
    final subTypes = narrow(o['garment_type'], _attrs['productType']);
    final hasSubTypes = !home && subTypes.isNotEmpty;

    final isGarment =
        hasSubTypes && !isSaree && (_attrs['garmentType'] != null);

    final withBlouse =
        _labelOf(o, 'garment_type', _attrs['garmentType']) == 'With Blouse';

    final uom = _labelOf(o, 'uom', _attrs['uom']);
    final craft = _labelOf(o, 'craft_technique', _attrs['craftTechnique']);

    return TabBarView(
      children: [
        _basic(o, places, home, hasSubTypes, isSaree, isGarment, uom),
        _craft(o, craft),
        _details(o, isSaree, withBlouse),
        _pricesTab(uom),
        _images(o, home),
        _stock(o, places, uom),
      ],
    );
  }

  // ── Basic ─────────────────────────────────────────────────────────────────

  Widget _basic(
    CoreOptions o,
    List<CoreLocation> places,
    bool home,
    bool hasSubTypes,
    bool isSaree,
    bool isGarment,
    String? uom,
  ) {
    return _Tab(
      children: [
        // Who is filing this. On a shared floor phone that is not obvious,
        // and every movement this record opens with is recorded against them.
        _Signed(actor: _actor!),
        const SizedBox(height: 14),

        _Field(
          error: _errors['industry'],
          child: PickerField(
            label: 'Industry *',
            value: _attrs['industry'],
            options: _pick(o['industry']),
            onChanged: (v) => setState(() {
              _attrs['industry'] = v;
              // The old product type belongs to the old industry's list.
              _attrs['productType'] = null;
              _attrs['homeProductType'] = null;
              _attrs['garmentType'] = null;
              _errors = {..._errors}..remove('industry');
            }),
          ),
        ),

        // Two different lists behind one question. A bedsheet is not a kind of
        // saree, and offering Saree, Dupatta and Fabric to somebody filing a
        // bedsheet is offering them nothing they can use.
        if (home) ...[
          _Field(
            error: _errors['homeProductType'],
            child: PickerField(
              label: 'Product type *',
              value: _attrs['homeProductType'],
              options: _pick(o['home_product_type']),
              onChanged: (v) => _setProductType(o, 'homeProductType', v),
            ),
          ),
          _Field(
            child: PickerField(
              label: 'Weaving category',
              value: _attrs['homeWeavingCategory'],
              allowClear: true,
              options: _pick(o['home_weaving_category']),
              onChanged: (v) => _set('homeWeavingCategory', v),
            ),
          ),
        ] else ...[
          _Field(
            error: _errors['productType'],
            child: PickerField(
              label: 'Product type *',
              value: _attrs['productType'],
              hint: _attrs['industry'] == null
                  ? 'Choose an industry first'
                  : 'Select',
              // Narrowed to the industry, with no unparented fall-through:
              // Saree, Dupatta and Fabric each name Clothing as their parent,
              // and under any other industry the question is not asked.
              options: _pick(narrow(o['product_type'], _attrs['industry'])),
              onChanged: (v) => _setProductType(o, 'productType', v),
            ),
          ),
          if (hasSubTypes)
            _Field(
              child: PickerField(
                // Required for a garment, where the cut is the thing; optional
                // for a saree, where the layout is a description.
                label: isSaree ? 'Product sub type' : 'Product sub type *',
                value: _attrs['garmentType'],
                allowClear: true,
                options: _pick(narrow(o['garment_type'], _attrs['productType'])),
                onChanged: (v) => _set('garmentType', v),
              ),
            ),
        ],

        // Shown, never asked.
        if (uom != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              'Sold by the $uom — set by the product type',
              style: TextStyle(fontSize: 12, color: context.p.textSecondary),
            ),
          ),

        _Field(
          child: PickerField(
            label: 'Production method',
            value: _attrs['productionMethod'],
            allowClear: true,
            options: _pick(o['production_method']),
            onChanged: (v) => _set('productionMethod', v),
          ),
        ),
        _Field(
          child: PickerField(
            label: 'Audience',
            value: _attrs['audienceType'],
            allowClear: true,
            options: _pick(o['audience_type']),
            onChanged: (v) => _set('audienceType', v),
          ),
        ),
        _Field(
          error: _errors['fibreType'],
          child: PickerField(
            label: 'Fibre type *',
            value: _attrs['fibreType'],
            options: _pick(o['fibre_type']),
            onChanged: (v) => setState(() {
              _attrs['fibreType'] = v;
              // Textile Material is narrowed by the fibre, so the old answer
              // may no longer be on the list.
              _attrs['textileMaterial'] = null;
              _errors = {..._errors}..remove('fibreType');
            }),
          ),
        ),
        _Field(
          child: PickerField(
            label: 'Weave structure',
            value: _attrs['weaveStructure'],
            allowClear: true,
            options: _pick(o['weave_structure']),
            onChanged: (v) => _set('weaveStructure', v),
          ),
        ),
        _Field(
          child: PickerField(
            label: 'Textile material',
            value: _attrs['textileMaterial'],
            allowClear: true,
            hint: _attrs['fibreType'] == null
                ? 'Offered once a fibre is chosen'
                : 'Select',
            // The one field that falls through: Silk names its twenty-three
            // weaves, Cotton three, and every other fibre gets the ten that
            // name no fibre at all.
            options: _pick(narrow(
              o['textile_material'],
              _attrs['fibreType'],
              fallbackToUnparented: true,
            )),
            onChanged: (v) => _set('textileMaterial', v),
          ),
        ),

        if (isGarment)
          _Note(
            'The Garments sheet defines eleven more columns — Size, Sleeve '
            'Length and the rest — but every one arrived empty in the '
            'workbook. Give them values on Master Lists and they appear here.',
          ),

        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'Product name',
            border: const OutlineInputBorder(),
            hintText: 'Builds itself from your choices',
            helperText: _nameIsCustom
                ? 'Edited by hand — it will stop following attribute changes'
                : 'Composed from the taxonomy. Type to override.',
            helperMaxLines: 2,
          ),
          onChanged: (v) => setState(() => _nameIsCustom = v.trim().isNotEmpty),
        ),
        const SizedBox(height: 12),
        Text(
          'The design code is built from product type, region and fibre when '
          'you save.',
          style: TextStyle(fontSize: 12, color: context.p.textMuted),
        ),
      ],
    );
  }

  /// Choosing a product type also answers how the thing is measured.
  void _setProductType(CoreOptions o, String key, String? v) {
    final list = key == 'productType' ? 'product_type' : 'home_product_type';
    final chosen = _optionOf(o, list, v);

    setState(() {
      _attrs[key] = v;
      // A sub type belongs to the type above it.
      if (key == 'productType') _attrs['garmentType'] = null;
      if (chosen?.soldById != null) _attrs['uom'] = chosen!.soldById;
      _errors = {..._errors}
        ..remove('productType')
        ..remove('homeProductType');
    });
  }

  // ── Craft & Design ────────────────────────────────────────────────────────

  Widget _craft(CoreOptions o, String? craft) {
    return _Tab(
      children: [
        // Colour leads: on a hand-painted saree it is the first thing anyone
        // says about the piece, and it is what makes one colourway different
        // from the next under the same design.
        _Field(
          error: _errors['colour'],
          child: PickerField(
            label: 'Primary colour *',
            value: _colourId,
            options: _pick(o['colour']),
            onChanged: (v) => setState(() {
              _colourId = v;
              _errors = {..._errors}..remove('colour');
            }),
          ),
        ),
        _Field(
          child: PickerField(
            // A contrast pallu, a border that does not match. A description,
            // not part of the identity — two records cannot differ by it alone.
            label: 'Secondary colour',
            value: _secondaryColourId,
            allowClear: true,
            hint: 'None',
            options: _pick(o['colour']),
            onChanged: (v) => setState(() => _secondaryColourId = v),
          ),
        ),
        _Field(
          error: _errors['craftTechnique'],
          child: PickerField(
            label: 'Craft technique *',
            value: _attrs['craftTechnique'],
            options: _pick(o['craft_technique']),
            onChanged: (v) => _set('craftTechnique', v),
          ),
        ),
        if (craft == 'Kalamkari')
          _Field(
            child: PickerField(
              label: 'Craft sub type',
              value: _attrs['craftSubType'],
              allowClear: true,
              options: _pick(o['craft_sub_type']),
              onChanged: (v) => _set('craftSubType', v),
            ),
          ),
        _Field(
          child: PickerField(
            label: 'Motif category',
            value: _attrs['motifCategory'],
            allowClear: true,
            options: _pick(o['motif_category']),
            onChanged: (v) => setState(() {
              _attrs['motifCategory'] = v;
              _attrs['motif'] = null;
            }),
          ),
        ),
        _Field(
          child: PickerField(
            label: 'Motif',
            value: _attrs['motif'],
            allowClear: true,
            hint: _attrs['motifCategory'] == null
                ? 'Pick a category first'
                : 'Select',
            options: _pick(narrow(o['motif'], _attrs['motifCategory'])),
            onChanged: (v) => _set('motif', v),
          ),
        ),
      ],
    );
  }

  // ── Additional product details ────────────────────────────────────────────

  Widget _details(CoreOptions o, bool isSaree, bool withBlouse) {
    return _Tab(
      children: [
        if (isSaree) ...[
          // Everything here describes the cloth you unfold — the field, the
          // pallu, the border that runs down it. Nothing invents vocabulary:
          // a motif on the blouse is a motif. The question is placement.
          const _Heading('Saree & pallu'),
          _Field(
            child: PickerField(
              label: 'Saree style',
              value: _attrs['sareeStyle'],
              allowClear: true,
              options: _pick(o['saree_style']),
              onChanged: (v) => _set('sareeStyle', v),
            ),
          ),
          _Field(
            child: PickerField(
              label: 'Saree body motif',
              value: _attrs['sareeBodyMotif'],
              allowClear: true,
              options: _pick(o['motif']),
              onChanged: (v) => _set('sareeBodyMotif', v),
            ),
          ),
          _Field(
            child: PickerField(
              label: 'Pallu motif',
              value: _attrs['palluMotif'],
              allowClear: true,
              options: _pick(o['motif']),
              onChanged: (v) => _set('palluMotif', v),
            ),
          ),

          const _Heading('Border'),
          _Field(
            child: PickerField(
              label: 'Border style',
              value: _attrs['borderStyle'],
              allowClear: true,
              options: _pick(o['border_style']),
              onChanged: (v) => _set('borderStyle', v),
            ),
          ),
          _Field(
            child: PickerField(
              label: 'Border height',
              value: _attrs['borderHeight'],
              allowClear: true,
              options: _pick(o['border_height']),
              onChanged: (v) => _set('borderHeight', v),
            ),
          ),
          _Field(
            child: PickerField(
              label: 'Border motif',
              value: _attrs['borderMotif'],
              allowClear: true,
              options: _pick(o['motif']),
              onChanged: (v) => _set('borderMotif', v),
            ),
          ),

          // There at all only if the sub type says a blouse comes with it.
          if (withBlouse) ...[
            const _Heading('Blouse'),
            _Field(
              child: PickerField(
                label: 'Blouse status',
                value: _attrs['blouseStatus'],
                allowClear: true,
                options: _pick(o['blouse_status']),
                onChanged: (v) => _set('blouseStatus', v),
              ),
            ),
            _Field(
              child: PickerField(
                label: 'Blouse style',
                value: _attrs['blouseStyle'],
                allowClear: true,
                options: _pick(o['blouse_style']),
                onChanged: (v) => _set('blouseStyle', v),
              ),
            ),
            _Field(
              child: PickerField(
                label: 'Blouse material',
                value: _attrs['blouseMaterial'],
                allowClear: true,
                options: _pick(o['blouse_material']),
                onChanged: (v) => _set('blouseMaterial', v),
              ),
            ),
            _Field(
              child: PickerField(
                label: 'Blouse border',
                value: _attrs['blouseBorder'],
                allowClear: true,
                options: _pick(o['border_style']),
                onChanged: (v) => _set('blouseBorder', v),
              ),
            ),
            _Field(
              child: PickerField(
                label: 'Blouse motif',
                value: _attrs['blouseMotif'],
                allowClear: true,
                options: _pick(o['motif']),
                onChanged: (v) => _set('blouseMotif', v),
              ),
            ),
          ],
        ],

        // Outside the saree sections: the adjectives describe the whole piece,
        // they are what the product name is built from, and a dupatta has them.
        const _Heading('Description'),
        MultiPickerField(
          label: 'Descriptor',
          options: o['descriptor'] ?? const [],
          values: _descriptors,
          onChanged: (v) => setState(() => _descriptors = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notes,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  // ── Prices ────────────────────────────────────────────────────────────────

  Widget _pricesTab(String? uom) {
    final per = uom == null ? '' : ' per $uom';

    return _Tab(
      children: [
        for (final p in priceKinds)
          _Field(
            error: _errors[p.key],
            child: TextField(
              controller: _prices[p.key],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                // "per Metre" rather than a generic "per qty": fabric at
                // ₹1,000 means something quite different from a saree at
                // ₹1,000.
                labelText:
                    '${p.label}${p.key == 'retail' ? ' *' : ''}$per',
                prefixText: '₹ ',
                helperText: p.note,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }

  // ── Images ────────────────────────────────────────────────────────────────

  Widget _images(CoreOptions o, bool home) {
    // Which photographs a product needs depends on what it is: a saree is
    // judged on Body, Pallu, Border and Blouse, and a bedsheet is not. A slot
    // naming a product type is offered only under it; one naming none is
    // offered on everything.
    final type = home ? _attrs['homeProductType'] : _attrs['productType'];

    final slots = [
      for (final s in o['image_slot'] ?? const <CoreOption>[])
        if (s.parentId == null || s.parentId == type) s,
    ];

    return _Tab(
      children: [
        Text(
          'Which photographs this product should have. Ticking a slot records '
          'that one is wanted — the photograph itself is taken later.',
          style: TextStyle(fontSize: 13, color: context.p.textSecondary),
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          _Note('No image slots are defined for this product type yet.')
        else
          for (final s in slots)
            CheckboxListTile(
              value: _imageSlots.contains(s.id),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(s.label),
              onChanged: (on) => setState(() {
                if (on == true) {
                  _imageSlots = [..._imageSlots, s.id];
                } else {
                  _imageSlots =
                      [for (final id in _imageSlots) if (id != s.id) id];
                }
              }),
            ),
        const SizedBox(height: 16),
        _Note(
          'The camera opens on the next screen, once the record exists — a '
          'photograph has to belong to something. Slots left unphotographed '
          'stay on the shot list.',
        ),
      ],
    );
  }

  // ── Stock ─────────────────────────────────────────────────────────────────

  Widget _stock(CoreOptions o, List<CoreLocation> places, String? uom) {
    final internal = [for (final l in places) if (l.isInternal) l];

    return _Tab(
      children: [
        const _Heading('Opening stock'),
        Text(
          'What is in the building now. Recorded as arriving from Production, '
          'so the count can be explained a year from now.',
          style: TextStyle(fontSize: 12, color: context.p.textSecondary),
        ),
        const SizedBox(height: 12),
        _Field(
          child: PickerField(
            label: 'Where',
            value: _location,
            allowClear: true,
            options: [for (final l in internal) PickerOption(l.id, l.name)],
            onChanged: (v) => setState(() => _location = v),
          ),
        ),
        _Field(
          error: _errors['quantity'],
          child: TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: uom == null ? 'How many' : 'How many ($uom)',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        _Note(
          'Moving stock that already exists is a transfer, which is a '
          'different act and gets its own screen.',
        ),
      ],
    );
  }
}

// ── Chrome ──────────────────────────────────────────────────────────────────

class _Tab extends StatelessWidget {
  const _Tab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: children,
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.p.text,
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface3,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: p.textSecondary, height: 1.4),
      ),
    );
  }
}

class _Signed extends StatelessWidget {
  const _Signed({required this.actor});

  final CoreActor actor;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: p.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${actor.name} · ${actor.role}',
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.child, this.error});

  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child,
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  error!,
                  style: TextStyle(fontSize: 12, color: context.p.danger),
                ),
              ),
          ],
        ),
      );
}

/// Save, and what is still missing.
///
/// Pinned rather than at the bottom of a tab: the questions are spread over
/// six of them, and a Create button living on the last one would mean the
/// answer to "am I done" is on a screen you have to go and find.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.busy,
    required this.errors,
    required this.onSave,
  });

  final bool busy;
  final Map<String, String> errors;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: p.surface2,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  // Named, because the field itself may be on another tab.
                  errors.values.join(' · '),
                  style: TextStyle(fontSize: 12, color: p.danger),
                ),
              ),
            FilledButton(
              onPressed: busy ? null : onSave,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.p.surface1,
      appBar: AppBar(title: const Text('New record')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This screen uses the stock system, which signs in separately.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.p.textSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CoreSignInScreen(),
                  ),
                ),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
