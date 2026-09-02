import '../../models/core.dart';

/// Which lookup list each attribute draws from.
///
/// The keys are the API's, exactly — `toRecordDraft` refuses an attribute it
/// does not recognise, so a typo here is a 400 rather than a field that
/// quietly does nothing. Mirrors ATTRIBUTES in apps/web/src/lib/attributes.ts.
const Map<String, String> attributeLists = {
  'industry': 'industry',
  'productType': 'product_type',
  'homeProductType': 'home_product_type',
  'homeWeavingCategory': 'home_weaving_category',
  'garmentType': 'garment_type',
  'uom': 'uom',
  'productionMethod': 'production_method',
  'audienceType': 'audience_type',
  'fibreType': 'fibre_type',
  'weaveStructure': 'weave_structure',
  'textileMaterial': 'textile_material',
  'craftTechnique': 'craft_technique',
  'craftSubType': 'craft_sub_type',
  'motifCategory': 'motif_category',
  'motif': 'motif',
  'sareeStyle': 'saree_style',
  'sareeBodyMotif': 'motif',
  'palluMotif': 'motif',
  'borderStyle': 'border_style',
  'borderHeight': 'border_height',
  'borderMotif': 'motif',
  'blouseStatus': 'blouse_status',
  'blouseStyle': 'blouse_style',
  'blouseMaterial': 'blouse_material',
  'blouseBorder': 'border_style',
  'blouseMotif': 'motif',
};

/// Whether this industry is the home one, whatever it is called today.
///
/// Both spellings, because the live vocabulary was renamed from
/// "Home & Lifestyle" to "Home" and matching one string left the whole home
/// branch of the web form unreachable until somebody noticed.
bool isHomeIndustry(String? label) =>
    label != null && (label == 'Home' || label == 'Home & Lifestyle');

/// Narrow a list to the value chosen above it.
///
/// The rule that matters, and the one easy to get wrong: with nothing chosen
/// above, the answer is **nothing** — not "the values that belong to nobody".
/// An unparented value is one that applies to *every* parent, not one that
/// applies before a parent is picked. Offering them early is how Bedsheets
/// ends up on the list under Clothing.
///
/// [fallbackToUnparented] is for the one field that genuinely needs it:
/// Textile Material names its weaves under Silk and Cotton, and every other
/// fibre falls through to the ten that name no fibre at all.
List<CoreOption> narrow(
  List<CoreOption>? values,
  String? parent, {
  bool fallbackToUnparented = false,
}) {
  final all = values ?? const <CoreOption>[];
  if (parent == null) return const [];

  final own = [for (final o in all) if (o.parentId == parent) o];

  if (fallbackToUnparented && own.isEmpty) {
    return [for (final o in all) if (o.parentId == null) o];
  }

  return own;
}

/// The attribute values a new record starts with.
///
/// Two passes, because a default can belong to another default: Saree is the
/// default Product Type and belongs to Clothing, which is the default
/// Industry, so it applies. Mul Mul is the default Textile Material and
/// belongs to Cotton, which may never be chosen, so it does not — it is
/// applied when the fibre is answered.
///
/// Colour is deliberately never defaulted. A record silently created in
/// somebody else's idea of a default colour is worse than one that makes you
/// choose.
Map<String, String?> defaultAttributes(CoreOptions options) {
  final defaults = <String, String?>{};
  final applied = <String>{};

  CoreOption? defaultOf(String list) {
    for (final o in options[list] ?? const <CoreOption>[]) {
      if (o.isDefault) return o;
    }
    return null;
  }

  for (final entry in attributeLists.entries) {
    final chosen = defaultOf(entry.value);
    if (chosen == null || chosen.parentId != null) continue;
    defaults[entry.key] = chosen.id;
    applied.add(chosen.id);
  }

  for (final entry in attributeLists.entries) {
    final chosen = defaultOf(entry.value);
    if (chosen == null || chosen.parentId == null) continue;
    if (!applied.contains(chosen.parentId)) continue;
    defaults[entry.key] = chosen.id;
    applied.add(chosen.id);
  }

  // Unit of measure follows from the product type rather than being asked.
  // Set here as well as on every change, or a record created without touching
  // Product Type would be priced "per" nothing.
  final typeId = defaults['productType'] ?? defaults['homeProductType'];
  for (final o in [
    ...?options['product_type'],
    ...?options['home_product_type'],
  ]) {
    if (o.id == typeId && o.soldById != null) defaults['uom'] = o.soldById;
  }

  return defaults;
}

/// The five prices a colourway carries, in the order the web editor shows them.
const List<({String key, String label, String note})> priceKinds = [
  (key: 'cost', label: 'Cost', note: 'What it cost to buy or make'),
  (key: 'making', label: 'Making price', note: 'Labour and finishing on top of cost'),
  (key: 'wholesale', label: 'Wholesale price', note: 'Trade or bulk buyers'),
  (key: 'retail', label: 'Retail price', note: 'The counter price — used for stock value'),
  (key: 'mrp', label: 'MRP', note: 'Printed on the tag'),
];
