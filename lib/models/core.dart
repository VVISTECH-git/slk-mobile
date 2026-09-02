import 'dart:convert';

import 'package:flutter/material.dart';

/// The shapes slk-core's Inventory API speaks in.
///
/// Deliberately a subset. slk-core's record carries thirty-four taxonomy
/// attributes; this app reads the handful the floor answers and passes the
/// rest through untouched. Modelling all of them here would mean editing this
/// file every time the vocabulary grows a question.

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
  /// No client-side gate on creating a record: every signed-in actor may,
  /// floor included, because whoever is holding the delivery is who enters it.
  /// Editing an existing record still needs office, which this app does not
  /// do yet — when it does, the 403 is what to check, not a rule copied here.
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

  Color? get swatch {
    final value = hex;
    if (value == null) return null;

    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;

    final parsed = int.tryParse(cleaned, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

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
