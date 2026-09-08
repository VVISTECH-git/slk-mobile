import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/picker_field.dart';
import 'multi_picker_field.dart';
import 'record_fields.dart';

/// Which tab a `fieldErrors` key lives on — Basic, Craft, Details, Prices,
/// Images, Stock, in that order (0-5), the tab order both the create and
/// edit screens share. A key with no error to show today still gets a slot
/// here so a future one doesn't silently show on no tab at all.
///
/// This is what makes a listed error in [RecordSaveBar] more than a label:
/// tapping one can jump to where the field actually lives.
const Map<String, int> fieldErrorTabIndex = {
  'industry': 0,
  'productType': 0,
  'homeProductType': 0,
  'garmentType': 0,
  'fibreType': 0,
  'colour': 1,
  'craftTechnique': 1,
  'cost': 3,
  'making': 3,
  'wholesale': 3,
  'retail': 3,
  'mrp': 3,
  // Named for what the server's own validation actually keys this error
  // under (see slk-core's records/actions.ts) — not the field's own local
  // name, which is what let this key silently never match anything.
  'openingStock': 5,
  // The edit screen's own stock correction — a different field from create's
  // opening count, and the server keys a failure on it under this name, not
  // 'openingStock'.
  'quantity': 5,
};

/// Which `fieldErrors` entry to jump to first — the one that reads earliest
/// on the tabs, Basic before Craft before Prices, not whichever the server
/// happened to list first in its response. A key with no known tab sorts
/// last rather than crashing the comparison.
///
/// Null for an empty map — there is nothing to jump to.
String? firstErrorKey(Map<String, String> errors) {
  if (errors.isEmpty) return null;

  // Tie-broken by the server's own order rather than left to List.sort's
  // unspecified stability — two errors on the same tab should not swap
  // places between one submit and the next for no reason a person can see.
  final keys = errors.keys.toList();
  var best = keys.first;
  var bestTab = fieldErrorTabIndex[best] ?? 99;

  for (final key in keys.skip(1)) {
    final tab = fieldErrorTabIndex[key] ?? 99;
    if (tab < bestTab) {
      best = key;
      bestTab = tab;
    }
  }

  return best;
}

/// Every slot Images would offer for a saree — Body, Pallu, Border and
/// Blouse in the live vocabulary — wanted by default rather than boxes
/// somebody has to remember to tick.
///
/// Matches [buildImagesTab]'s own "which slots does this product type see"
/// rule exactly (`parentId == null || parentId == productTypeId`), not just
/// slots parented to Saree specifically: today's four are all unparented —
/// universal values nothing has scoped to a type — so a stricter
/// exact-parent match would default nothing at all, while still ticking
/// every slot Saree is actually shown stays correct if a value is ever
/// parented to it later.
///
/// Pulled out so both the moment somebody actively picks Saree
/// ([RecordFormFields.setProductType]) and the moment a brand-new record
/// simply opens already defaulted to it ([NewRecordScreen]'s own defaults
/// application, which never calls setProductType at all) apply the exact
/// same set.
List<String> sareeDefaultImageSlots(CoreOptions o, String productTypeId) => [
      for (final s in o['image_slot'] ?? const <CoreOption>[])
        if (s.parentId == null || s.parentId == productTypeId) s.id,
    ];

/// Every question the web editor asks, built once and shared by the screen
/// that creates a record and the one that edits it.
///
/// The two screens differ in what happens around the fields — a new record
/// asks for opening stock and mints codes on save; an existing one shows a
/// ledger and writes a partial update — but the fields themselves, and the
/// rules that narrow one from another, are the same fourteen years of the
/// vocabulary either way. Written twice, the two copies would answer "what
/// narrows Motif" differently within a month.
mixin RecordFormFields<T extends StatefulWidget> on State<T> {
  /// Attribute key → chosen lookup value id.
  final Map<String, String?> attrs = {};

  List<String> descriptors = [];
  List<String> imageSlots = [];

  String? colourId;
  String? secondaryColourId;

  final Map<String, TextEditingController> prices = {
    for (final p in priceKinds) p.key: TextEditingController(),
  };
  final TextEditingController notesField = TextEditingController();
  final TextEditingController nameField = TextEditingController();

  /// One per price field, so a tapped error in [RecordSaveBar] can land the
  /// cursor on the actual field rather than just the right tab.
  final Map<String, FocusNode> priceFocusNodes = {
    for (final p in priceKinds) p.key: FocusNode(),
  };

  bool nameIsCustom = false;
  Map<String, String> fieldErrors = const {};

  /// Called after every change made through this mixin's own field handlers.
  /// A no-op by default; [NewRecordScreen] overrides it to debounce a save of
  /// the draft so far. The edit screen leaves it alone — resuming a
  /// half-finished *edit* would mean silently reverting someone else's more
  /// recent change with a stale local copy, which a new record has no way to
  /// even mean.
  void onFieldChanged() {}

  void disposeFormFields() {
    for (final c in prices.values) {
      c.dispose();
    }
    for (final f in priceFocusNodes.values) {
      f.dispose();
    }
    notesField.dispose();
    nameField.dispose();
  }

  // ── Reading the vocabulary ────────────────────────────────────────────────

  String? labelOf(CoreOptions options, String list, String? id) {
    if (id == null) return null;
    for (final o in options[list] ?? const <CoreOption>[]) {
      if (o.id == id) return o.label;
    }
    return null;
  }

  CoreOption? optionOf(CoreOptions options, String list, String? id) {
    if (id == null) return null;
    for (final o in options[list] ?? const <CoreOption>[]) {
      if (o.id == id) return o;
    }
    return null;
  }

  List<PickerOption> pickOptions(List<CoreOption>? values) => [
        for (final o in values ?? const <CoreOption>[])
          PickerOption(o.id, o.label, color: o.swatch),
      ];

  void setAttr(String key, String? value) => setState(() {
        attrs[key] = value;
        fieldErrors = {...fieldErrors}..remove(key);
        onFieldChanged();
      });

  /// Choosing a product type also answers how the thing is measured.
  void setProductType(CoreOptions o, String key, String? v) {
    final list = key == 'productType' ? 'product_type' : 'home_product_type';
    final chosen = optionOf(o, list, v);

    setState(() {
      attrs[key] = v;
      // A sub type belongs to the type above it.
      if (key == 'productType') attrs['garmentType'] = null;
      if (chosen?.soldById != null) attrs['uom'] = chosen!.soldById;
      fieldErrors = {...fieldErrors}
        ..remove('productType')
        ..remove('homeProductType');

      // A saree is judged on Body, Pallu, Border and Blouse — wanted by
      // default rather than four boxes somebody has to remember to tick.
      //
      // Only when nothing is chosen yet: this mixin is shared with the edit
      // screen, where Product Type is re-confirmed (not just changed) every
      // time somebody opens the picker and taps Done — even without picking
      // anything new. Applying the default unconditionally there would wipe
      // an already-photographed slot outside these four, or silently restore
      // one somebody had deliberately unticked.
      if (key == 'productType' && chosen?.label == 'Saree' && imageSlots.isEmpty && v != null) {
        imageSlots = sareeDefaultImageSlots(o, v);
      }
      onFieldChanged();
    });
  }

  /// Only the keys this form actually asks, and only under the industry that
  /// owns them.
  ///
  /// The API refuses a record carrying both a Saree and a Bedsheets product
  /// type — rightly, since nobody could explain it later — so the other
  /// industry's answers are dropped rather than sent and rejected.
  Map<String, String?> attributesForSubmit(CoreOptions options) {
    final home = isHomeIndustry(labelOf(options, 'industry', attrs['industry']));

    final result = <String, String?>{};
    for (final key in attributeLists.keys) {
      if (home && (key == 'productType' || key == 'garmentType')) continue;
      if (!home && (key == 'homeProductType' || key == 'homeWeavingCategory')) {
        continue;
      }
      if (attrs.containsKey(key)) result[key] = attrs[key];
    }
    return result;
  }

  // ── Basic ─────────────────────────────────────────────────────────────────

  Widget buildBasicTab({
    required CoreOptions o,
    required bool home,
    required bool hasSubTypes,
    required bool isSaree,
    required bool isGarment,
    required String? uom,
    List<Widget> header = const [],
    List<Widget> footer = const [],
  }) {
    return RecordTabBody(
      children: [
        ...header,

        RecordFieldWrap(
          error: fieldErrors['industry'],
          child: PickerField(
            label: 'Industry *',
            value: attrs['industry'],
            options: pickOptions(o['industry']),
            onChanged: (v) => setState(() {
              attrs['industry'] = v;
              // The old product type belongs to the old industry's list.
              attrs['productType'] = null;
              attrs['homeProductType'] = null;
              attrs['garmentType'] = null;
              fieldErrors = {...fieldErrors}..remove('industry');
              onFieldChanged();
            }),
          ),
        ),

        // Two different lists behind one question. A bedsheet is not a kind of
        // saree, and offering Saree, Dupatta and Fabric to somebody filing a
        // bedsheet is offering them nothing they can use.
        if (home) ...[
          RecordFieldWrap(
            error: fieldErrors['homeProductType'],
            child: PickerField(
              label: 'Product type *',
              value: attrs['homeProductType'],
              options: pickOptions(o['home_product_type']),
              onChanged: (v) => setProductType(o, 'homeProductType', v),
            ),
          ),
          RecordFieldWrap(
            child: PickerField(
              label: 'Weaving category',
              value: attrs['homeWeavingCategory'],
              allowClear: true,
              options: pickOptions(o['home_weaving_category']),
              onChanged: (v) => setAttr('homeWeavingCategory', v),
            ),
          ),
        ] else ...[
          RecordFieldWrap(
            error: fieldErrors['productType'],
            child: PickerField(
              label: 'Product type *',
              value: attrs['productType'],
              hint: attrs['industry'] == null
                  ? 'Choose an industry first'
                  : 'Select',
              // Narrowed to the industry, with no unparented fall-through:
              // Saree, Dupatta and Fabric each name Clothing as their parent,
              // and under any other industry the question is not asked.
              options: pickOptions(narrow(o['product_type'], attrs['industry'])),
              onChanged: (v) => setProductType(o, 'productType', v),
            ),
          ),
          if (hasSubTypes)
            RecordFieldWrap(
              child: PickerField(
                // Required for a garment, where the cut is the thing; optional
                // for a saree, where the layout is a description.
                label: isSaree ? 'Product sub type' : 'Product sub type *',
                value: attrs['garmentType'],
                allowClear: true,
                options:
                    pickOptions(narrow(o['garment_type'], attrs['productType'])),
                onChanged: (v) => setAttr('garmentType', v),
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

        RecordFieldWrap(
          child: PickerField(
            label: 'Production method',
            value: attrs['productionMethod'],
            allowClear: true,
            options: pickOptions(o['production_method']),
            onChanged: (v) => setAttr('productionMethod', v),
          ),
        ),
        RecordFieldWrap(
          child: PickerField(
            label: 'Audience',
            value: attrs['audienceType'],
            allowClear: true,
            options: pickOptions(o['audience_type']),
            onChanged: (v) => setAttr('audienceType', v),
          ),
        ),
        RecordFieldWrap(
          error: fieldErrors['fibreType'],
          child: PickerField(
            label: 'Fibre type *',
            value: attrs['fibreType'],
            options: pickOptions(o['fibre_type']),
            onChanged: (v) => setState(() {
              attrs['fibreType'] = v;
              // Textile Material is narrowed by the fibre, so the old answer
              // may no longer be on the list.
              attrs['textileMaterial'] = null;
              fieldErrors = {...fieldErrors}..remove('fibreType');
              onFieldChanged();
            }),
          ),
        ),
        RecordFieldWrap(
          child: PickerField(
            label: 'Weave structure',
            value: attrs['weaveStructure'],
            allowClear: true,
            options: pickOptions(o['weave_structure']),
            onChanged: (v) => setAttr('weaveStructure', v),
          ),
        ),
        RecordFieldWrap(
          child: PickerField(
            label: 'Textile material',
            value: attrs['textileMaterial'],
            allowClear: true,
            hint: attrs['fibreType'] == null
                ? 'Offered once a fibre is chosen'
                : 'Select',
            // The one field that falls through: Silk names its twenty-three
            // weaves, Cotton three, and every other fibre gets the ten that
            // name no fibre at all.
            options: pickOptions(narrow(
              o['textile_material'],
              attrs['fibreType'],
              fallbackToUnparented: true,
            )),
            onChanged: (v) => setAttr('textileMaterial', v),
          ),
        ),

        if (isGarment)
          RecordNote(
            'The Garments sheet defines eleven more columns — Size, Sleeve '
            'Length and the rest — but every one arrived empty in the '
            'workbook. Give them values on Master Lists and they appear here.',
          ),

        const SizedBox(height: 8),
        TextField(
          controller: nameField,
          decoration: InputDecoration(
            labelText: 'Product name',
            border: const OutlineInputBorder(),
            // What Create will actually save — not a slogan. Only a generic
            // placeholder while there is nothing yet to compose from.
            hintText: () {
              final preview = composeDesignNamePreview(
                options: o,
                descriptorIds: descriptors,
                attrs: attrs,
                home: home,
              );
              return preview.isEmpty ? 'Builds itself from your choices' : preview;
            }(),
            helperText: nameIsCustom
                ? 'Edited by hand — it will stop following attribute changes'
                : 'Composed from the taxonomy. Type to override.',
            helperMaxLines: 2,
          ),
          onChanged: (v) => setState(() {
            nameIsCustom = v.trim().isNotEmpty;
            onFieldChanged();
          }),
        ),

        ...footer,
      ],
    );
  }

  // ── Craft & Design ────────────────────────────────────────────────────────

  Widget buildCraftTab(CoreOptions o, String? craft) {
    return RecordTabBody(
      children: [
        // Colour leads: on a hand-painted saree it is the first thing anyone
        // says about the piece, and it is what makes one colourway different
        // from the next under the same design.
        RecordFieldWrap(
          error: fieldErrors['colour'],
          child: PickerField(
            label: 'Primary colour *',
            value: colourId,
            options: pickOptions(o['colour']),
            onChanged: (v) => setState(() {
              colourId = v;
              fieldErrors = {...fieldErrors}..remove('colour');
              onFieldChanged();
            }),
          ),
        ),
        RecordFieldWrap(
          child: PickerField(
            // A contrast pallu, a border that does not match. A description,
            // not part of the identity — two records cannot differ by it alone.
            label: 'Secondary colour',
            value: secondaryColourId,
            allowClear: true,
            hint: 'None',
            options: pickOptions(o['colour']),
            onChanged: (v) => setState(() {
              secondaryColourId = v;
              onFieldChanged();
            }),
          ),
        ),
        RecordFieldWrap(
          error: fieldErrors['craftTechnique'],
          child: PickerField(
            label: 'Craft technique *',
            value: attrs['craftTechnique'],
            options: pickOptions(o['craft_technique']),
            onChanged: (v) => setAttr('craftTechnique', v),
          ),
        ),
        if (craft == 'Kalamkari')
          RecordFieldWrap(
            child: PickerField(
              label: 'Craft sub type',
              value: attrs['craftSubType'],
              allowClear: true,
              options: pickOptions(o['craft_sub_type']),
              onChanged: (v) => setAttr('craftSubType', v),
            ),
          ),
        RecordFieldWrap(
          child: PickerField(
            label: 'Motif category',
            value: attrs['motifCategory'],
            allowClear: true,
            options: pickOptions(o['motif_category']),
            onChanged: (v) => setState(() {
              attrs['motifCategory'] = v;
              attrs['motif'] = null;
              onFieldChanged();
            }),
          ),
        ),
        RecordFieldWrap(
          child: PickerField(
            label: 'Motif',
            value: attrs['motif'],
            allowClear: true,
            hint: attrs['motifCategory'] == null
                ? 'Pick a category first'
                : 'Select',
            options: pickOptions(narrow(o['motif'], attrs['motifCategory'])),
            onChanged: (v) => setAttr('motif', v),
          ),
        ),
      ],
    );
  }

  // ── Additional product details ────────────────────────────────────────────

  Widget buildDetailsTab(CoreOptions o, bool isSaree, bool withBlouse) {
    return RecordTabBody(
      children: [
        if (isSaree) ...[
          // Everything here describes the cloth you unfold — the field, the
          // pallu, the border that runs down it. Nothing invents vocabulary:
          // a motif on the blouse is a motif. The question is placement.
          const RecordSectionHeading('Saree & pallu'),
          RecordFieldWrap(
            child: PickerField(
              label: 'Saree style',
              value: attrs['sareeStyle'],
              allowClear: true,
              options: pickOptions(o['saree_style']),
              onChanged: (v) => setAttr('sareeStyle', v),
            ),
          ),
          RecordFieldWrap(
            child: PickerField(
              label: 'Saree body motif',
              value: attrs['sareeBodyMotif'],
              allowClear: true,
              options: pickOptions(o['motif']),
              onChanged: (v) => setAttr('sareeBodyMotif', v),
            ),
          ),
          RecordFieldWrap(
            child: PickerField(
              label: 'Pallu motif',
              value: attrs['palluMotif'],
              allowClear: true,
              options: pickOptions(o['motif']),
              onChanged: (v) => setAttr('palluMotif', v),
            ),
          ),

          const RecordSectionHeading('Border'),
          RecordFieldWrap(
            child: PickerField(
              label: 'Border style',
              value: attrs['borderStyle'],
              allowClear: true,
              options: pickOptions(o['border_style']),
              onChanged: (v) => setAttr('borderStyle', v),
            ),
          ),
          RecordFieldWrap(
            child: PickerField(
              label: 'Border height',
              value: attrs['borderHeight'],
              allowClear: true,
              options: pickOptions(o['border_height']),
              onChanged: (v) => setAttr('borderHeight', v),
            ),
          ),
          RecordFieldWrap(
            child: PickerField(
              label: 'Border motif',
              value: attrs['borderMotif'],
              allowClear: true,
              options: pickOptions(o['motif']),
              onChanged: (v) => setAttr('borderMotif', v),
            ),
          ),

          // There at all only if the sub type says a blouse comes with it.
          if (withBlouse) ...[
            const RecordSectionHeading('Blouse'),
            RecordFieldWrap(
              child: PickerField(
                label: 'Blouse status',
                value: attrs['blouseStatus'],
                allowClear: true,
                options: pickOptions(o['blouse_status']),
                onChanged: (v) => setAttr('blouseStatus', v),
              ),
            ),
            RecordFieldWrap(
              child: PickerField(
                label: 'Blouse style',
                value: attrs['blouseStyle'],
                allowClear: true,
                options: pickOptions(o['blouse_style']),
                onChanged: (v) => setAttr('blouseStyle', v),
              ),
            ),
            RecordFieldWrap(
              child: PickerField(
                label: 'Blouse material',
                value: attrs['blouseMaterial'],
                allowClear: true,
                options: pickOptions(o['blouse_material']),
                onChanged: (v) => setAttr('blouseMaterial', v),
              ),
            ),
            RecordFieldWrap(
              child: PickerField(
                label: 'Blouse border',
                value: attrs['blouseBorder'],
                allowClear: true,
                options: pickOptions(o['border_style']),
                onChanged: (v) => setAttr('blouseBorder', v),
              ),
            ),
            RecordFieldWrap(
              child: PickerField(
                label: 'Blouse motif',
                value: attrs['blouseMotif'],
                allowClear: true,
                options: pickOptions(o['motif']),
                onChanged: (v) => setAttr('blouseMotif', v),
              ),
            ),
          ],
        ],

        // Outside the saree sections: the adjectives describe the whole piece,
        // they are what the product name is built from, and a dupatta has them.
        const RecordSectionHeading('Description'),
        MultiPickerField(
          label: 'Descriptor',
          options: o['descriptor'] ?? const [],
          values: descriptors,
          onChanged: (v) => setState(() {
            descriptors = v;
            onFieldChanged();
          }),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: notesField,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onFieldChanged(),
        ),
      ],
    );
  }

  // ── Prices ────────────────────────────────────────────────────────────────

  Widget buildPricesTab(String? uom) {
    final per = uom == null ? '' : ' per $uom';

    return RecordTabBody(
      children: [
        for (final p in priceKinds)
          RecordFieldWrap(
            error: fieldErrors[p.key],
            child: TextField(
              controller: prices[p.key],
              focusNode: priceFocusNodes[p.key],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              // A price rejected by the last submit stayed marked red even
              // after it was corrected — nothing ever told fieldErrors the
              // field had changed. Every picker field already clears its own
              // entry the same way; this was the one kind of field that didn't.
              onChanged: (_) => setState(() {
                fieldErrors = {...fieldErrors}..remove(p.key);
                onFieldChanged();
              }),
              decoration: InputDecoration(
                // "per Metre" rather than a generic "per qty": fabric at
                // ₹1,000 means something quite different from a saree at
                // ₹1,000.
                labelText: '${p.label}${p.key == 'retail' ? ' *' : ''}$per',
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

  Widget buildImagesTab(
    CoreOptions o,
    bool home, {
    String? note,
    /// Slot id → a photograph already taken for it, waiting to be sent once
    /// there is a record to send it to. Only [NewRecordScreen] passes this —
    /// the edit screen has a record already and sends straight away, on its
    /// own separate Photographs screen.
    Map<String, File>? capturedPhotos,
    void Function(CoreOption slot)? onCapture,
    void Function(CoreOption slot)? onRemoveCapture,
  }) {
    // Which photographs a product needs depends on what it is: a saree is
    // judged on Body, Pallu, Border and Blouse, and a bedsheet is not. A slot
    // naming a product type is offered only under it; one naming none is
    // offered on everything.
    final type = home ? attrs['homeProductType'] : attrs['productType'];

    final slots = [
      for (final s in o['image_slot'] ?? const <CoreOption>[])
        if (s.parentId == null || s.parentId == type) s,
    ];

    return RecordTabBody(
      children: [
        Text(
          onCapture == null
              ? 'Which photographs this product should have. Ticking a slot '
                  'records that one is wanted — the photograph itself is '
                  'taken later.'
              : 'Which photographs this product should have — and, for any '
                  "you're holding it for right now, the photograph itself.",
          style: TextStyle(fontSize: 13, color: context.p.textSecondary),
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          RecordNote('No image slots are defined for this product type yet.')
        else
          for (final s in slots) ...[
            CheckboxListTile(
              value: imageSlots.contains(s.id),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(s.label),
              onChanged: (on) => setState(() {
                if (on == true) {
                  imageSlots = [...imageSlots, s.id];
                } else {
                  imageSlots =
                      [for (final id in imageSlots) if (id != s.id) id];
                  onRemoveCapture?.call(s);
                }
                onFieldChanged();
              }),
            ),
            if (onCapture != null && imageSlots.contains(s.id))
              Padding(
                padding: const EdgeInsets.only(left: 56, right: 16, bottom: 10),
                child: _CaptureRow(
                  file: capturedPhotos?[s.id],
                  label: s.label,
                  onCapture: () => onCapture(s),
                  onRemove: () => onRemoveCapture?.call(s),
                ),
              ),
          ],
        const SizedBox(height: 16),
        RecordNote(
          note ??
              (onCapture == null
                  ? 'The camera opens on the next screen, once the record '
                      'exists — a photograph has to belong to something. '
                      'Slots left unphotographed stay on the shot list.'
                  : 'A slot ticked but not photographed here still saves — '
                      'it just stays on the shot list, same as ever.'),
        ),
      ],
    );
  }
}

// ── Chrome shared by both screens ────────────────────────────────────────────

class RecordTabBody extends StatelessWidget {
  const RecordTabBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        // A numeric keypad has no return key to dismiss itself with — a drag
        // on the tab body is the one gesture every tab already offers, so it
        // doubles as "put the keyboard away".
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      );
}

class RecordSectionHeading extends StatelessWidget {
  const RecordSectionHeading(this.text, {super.key});

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

class RecordNote extends StatelessWidget {
  const RecordNote(this.text, {super.key});

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

/// A thumbnail and a Retake, or a plain "Take photo now" button — whichever
/// this slot currently has. Purely local: nothing here talks to the network,
/// only the record it belongs to does that, once it exists.
class _CaptureRow extends StatelessWidget {
  const _CaptureRow({
    required this.file,
    required this.label,
    required this.onCapture,
    required this.onRemove,
  });

  final File? file;
  final String label;
  final VoidCallback onCapture;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    if (file == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onCapture,
          icon: const Icon(Icons.add_a_photo_outlined, size: 16),
          label: const Text('Take photo now'),
        ),
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file!, width: 44, height: 44, fit: BoxFit.cover),
        ),
        const SizedBox(width: 10),
        Text('$label photographed',
            style: TextStyle(fontSize: 12.5, color: p.success)),
        const Spacer(),
        TextButton(onPressed: onCapture, child: const Text('Retake')),
        IconButton(
          tooltip: 'Remove this photo',
          icon: Icon(Icons.close, size: 18, color: p.textMuted),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

class SignedInActor extends StatelessWidget {
  const SignedInActor({super.key, required this.actor});

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

class RecordFieldWrap extends StatelessWidget {
  const RecordFieldWrap({super.key, required this.child, this.error});

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

/// How many `fieldErrors` land on each tab, for a badge — tab index →
/// count. A key with nowhere in [fieldErrorTabIndex] is silently dropped
/// rather than crashing a build over a key nobody has mapped yet.
Map<int, int> tabErrorCounts(Map<String, String> fieldErrors) {
  final counts = <int, int>{};
  for (final key in fieldErrors.keys) {
    final tab = fieldErrorTabIndex[key];
    if (tab != null) counts[tab] = (counts[tab] ?? 0) + 1;
  }
  return counts;
}

/// A plain [Tab], or the same label with a small count badge when [count]
/// is above zero — used to mark which tab an error actually lives on.
Tab tabWithErrorBadge(String label, int count) {
  if (count == 0) return Tab(text: label);

  return Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Save (or Create), and what is still missing.
///
/// Pinned rather than at the bottom of a tab: the questions are spread over
/// six of them, and a button living on the last one would mean the answer to
/// "am I done" is on a screen you have to go and find.
///
/// The error list used to just be printed — three lines of red nobody could
/// act on, naming a field without saying where it was. Collapsed to a count
/// by default, and every listed error is now a way to get there: tapping one
/// switches to its tab and, for the fields that have one, focuses it too.
class RecordSaveBar extends StatefulWidget {
  const RecordSaveBar({
    super.key,
    required this.busy,
    required this.errors,
    required this.label,
    required this.onSave,
    this.focusNodes = const {},
    this.sequential = false,
  });

  final bool busy;
  final Map<String, String> errors;
  final String label;
  final VoidCallback onSave;

  /// fieldErrors key → that field's own FocusNode, for the fields that have
  /// one (price and quantity TextFields today). A picker-based field (colour,
  /// craft technique, product type…) has nothing to literally focus — for
  /// those, switching tabs is as far as a tap can take you.
  final Map<String, FocusNode> focusNodes;

  /// Filing a record is answering thirty questions in order; correcting one
  /// is answering one. `false` (the edit screen's own default) keeps a
  /// persistent [label] reachable from any tab — right for a fix that might
  /// be one price on one tab. `true` (the create screen) instead reads
  /// "Next" on every tab but the last, so the button itself asks for the
  /// whole record before it asks to file it — and [label] is saved for the
  /// one tab where filing is actually what happens.
  ///
  /// Tabs stay tappable either way — this changes what the pinned button
  /// does, not whether somebody can jump to Prices directly to fix a typo.
  final bool sequential;

  @override
  State<RecordSaveBar> createState() => _RecordSaveBarState();
}

class _RecordSaveBarState extends State<RecordSaveBar> {
  bool _expanded = false;
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only sequential mode cares which tab is showing — the edit screen's
    // persistent bar has nothing to do with it and skips the lookup.
    if (!widget.sequential) return;

    final controller = DefaultTabController.of(context);
    if (controller == _tabController) return;

    _tabController?.removeListener(_onTabChanged);
    _tabController = controller..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    super.dispose();
  }

  // The swipe animation between tabs fires this many times per gesture;
  // rebuilding on each is cheap; a bar which was still reading "Next" for a
  // frame after the swipe already reached Stock was the visible alternative.
  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  bool get _onLastTab =>
      _tabController == null || _tabController!.index == _tabController!.length - 1;

  @override
  void didUpdateWidget(RecordSaveBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    /*
      A submit that just came back rejected — not a field somebody is still
      part-way through fixing.

      Only the empty→non-empty transition jumps anywhere. Re-jumping on every
      keystroke while errors are already showing would fight whichever tab
      the person is actually correcting right now, undoing the very thing
      they are doing. Tapping Create used to only reprint the same three
      lines of red; this is what actually gets someone to the field.
    */
    if (oldWidget.errors.isEmpty && widget.errors.isNotEmpty) {
      final key = firstErrorKey(widget.errors);
      if (key == null) return;

      setState(() => _expanded = true);
      // The tab controller and the target field's own widget may both still
      // be mid-rebuild from the setState that populated these errors —
      // asking next frame is what makes both reliably exist by the time this
      // runs, the same reason _jumpTo itself defers the focus request.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpTo(key);
      });
    }
  }

  void _jumpTo(String key) {
    final tab = fieldErrorTabIndex[key];
    if (tab != null) {
      DefaultTabController.of(context).animateTo(tab);
    }
    final focus = widget.focusNodes[key];
    if (focus != null) {
      // The target tab may still be animating into place; asking for focus
      // next frame rather than this one is what makes that reliable.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focus.canRequestFocus) focus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final errors = widget.errors;

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
            if (errors.isNotEmpty) ...[
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: p.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${errors.length} field${errors.length == 1 ? '' : 's'} '
                          'need attention',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.danger,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: p.danger,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in errors.entries)
                        InkWell(
                          onTap: () => _jumpTo(entry.key),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Icon(Icons.chevron_right,
                                    size: 16, color: p.danger),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style: TextStyle(
                                        fontSize: 12, color: p.danger),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            () {
              // Only the last tab actually files anything — every other tab
              // hands the button to whatever moves the person on, which is
              // exactly what "Next" is.
              final onLastTab = !widget.sequential || _onLastTab;

              return FilledButton(
                onPressed: widget.busy
                    ? null
                    : (onLastTab
                        ? widget.onSave
                        : () => _tabController
                            ?.animateTo(_tabController!.index + 1)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: widget.busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : onLastTab
                        ? Text(widget.label)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Next'),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
              );
            }(),
          ],
        ),
      ),
    );
  }
}
