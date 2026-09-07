import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Autosaves an in-progress new-record form so leaving the screen (a call,
/// the app backgrounded, a crash) doesn't mean re-answering thirty questions.
///
/// Mirrors [SecureStore]'s wrapper shape but sits on plain SharedPreferences —
/// a draft is convenience, not a credential, and doesn't need the keychain.
class ProductDraftStore {
  ProductDraftStore._();
  static final ProductDraftStore instance = ProductDraftStore._();

  static const _key = 'product_draft';

  Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      // A draft from a shape this build no longer writes is worth losing
      // silently, not worth crashing the form over.
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
