import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/picker_field.dart';
import 'multi_picker_field.dart';
import 'record_fields.dart';

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

  bool nameIsCustom = false;
  Map<String, String> fieldErrors = const {};

  void disposeFormFields() {
    for (final c in prices.values) {
      c.dispose();
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
      if (key == 'productType' && chosen?.label == 'Saree' && imageSlots.isEmpty) {
        imageSlots = [
          for (final s in o['image_slot'] ?? const <CoreOption>[])
            if (s.parentId == v) s.id,
        ];
      }
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
            hintText: 'Builds itself from your choices',
            helperText: nameIsCustom
                ? 'Edited by hand — it will stop following attribute changes'
                : 'Composed from the taxonomy. Type to override.',
            helperMaxLines: 2,
          ),
          onChanged: (v) => setState(() => nameIsCustom = v.trim().isNotEmpty),
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
            onChanged: (v) => setState(() => secondaryColourId = v),
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
          onChanged: (v) => setState(() => descriptors = v),
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
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

  Widget buildImagesTab(CoreOptions o, bool home, {String? note}) {
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
          'Which photographs this product should have. Ticking a slot records '
          'that one is wanted — the photograph itself is taken later.',
          style: TextStyle(fontSize: 13, color: context.p.textSecondary),
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          RecordNote('No image slots are defined for this product type yet.')
        else
          for (final s in slots)
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
                }
              }),
            ),
        const SizedBox(height: 16),
        RecordNote(
          note ??
              'The camera opens on the next screen, once the record exists — '
                  'a photograph has to belong to something. Slots left '
                  'unphotographed stay on the shot list.',
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

/// Save (or Create), and what is still missing.
///
/// Pinned rather than at the bottom of a tab: the questions are spread over
/// six of them, and a button living on the last one would mean the answer to
/// "am I done" is on a screen you have to go and find.
class RecordSaveBar extends StatelessWidget {
  const RecordSaveBar({
    super.key,
    required this.busy,
    required this.errors,
    required this.label,
    required this.onSave,
  });

  final bool busy;
  final Map<String, String> errors;
  final String label;
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
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
