import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the codes of an in-progress scan on the phone, written as each one
/// is scanned, so the app being killed — a hundred and sixty labels into a
/// receive, the camera running the whole time — costs nothing but the tap
/// that reopens the screen.
///
/// One list per screen ([key]), same wrapper shape as [ProductDraftStore]:
/// plain SharedPreferences, since a list of label codes is convenience, not
/// a credential. The screen that owns a key writes the whole list on every
/// change and clears it once the batch has been sent or received.
class ScanDraftStore {
  ScanDraftStore._();
  static final ScanDraftStore instance = ScanDraftStore._();

  static const _prefix = 'scan_draft.';

  Future<List<String>> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      // A draft from a shape this build no longer writes is worth losing
      // silently, not worth crashing the scanner over.
      return const [];
    }
  }

  Future<void> save(String key, Iterable<String> codes) async {
    final prefs = await SharedPreferences.getInstance();
    final list = codes.toList();
    if (list.isEmpty) {
      await prefs.remove('$_prefix$key');
    } else {
      await prefs.setString('$_prefix$key', jsonEncode(list));
    }
  }

  Future<void> clear(String key) => save(key, const []);
}
