import 'package:flutter/foundation.dart';

/// App-wide configuration.
///
/// The API base URL is chosen so a DEBUG build can never accidentally talk to
/// production, while release builds (App Store) always do:
///
///   • release / profile  → production Vercel deployment
///   • debug              → the host machine's local tantu dev server
///                          (which runs against the DEV database)
///
/// Any build can override explicitly — e.g. point a debug build at staging, or
/// (deliberately) at prod:
///
///   flutter run --dart-define=API_BASE_URL=https://tantu-store.vercel.app
///
/// Note: 10.0.2.2 is the Android emulator's alias for the host's localhost.
/// For the iOS simulator use http://127.0.0.1:3000, and for a physical device
/// use your machine's LAN IP — both via --dart-define=API_BASE_URL=...
class Config {
  /// Explicit override; wins for any build when non-empty.
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Production API — App Store / release builds.
  static const String _prod = 'https://tantu-store.vercel.app';

  /// Dev API — debug builds hit the local tantu server (→ dev database).
  static const String _dev = 'http://10.0.2.2:3000';

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    // Only DEBUG points at dev; release AND profile stay on prod so a
    // Codemagic/App Store build is always production.
    return kDebugMode ? _dev : _prod;
  }

  /// All mobile endpoints live under /api/v1.
  static String get apiRoot => '$apiBaseUrl/api/v1';
}

/// Where slk-core lives.
///
/// A second backend, alongside [Config] rather than replacing it.
///
/// slk-core is the ops platform that owns stock — design → colourway → batch →
/// piece → movement, with stock derived from an append-only ledger. tantu's
/// model (categories → products → variants → pieces) is a different shape, so
/// the twelve screens built against it cannot simply be re-pointed; they are
/// migrated one at a time. Until that finishes both backends are live, and a
/// screen says which one it talks to by which client it asks for.
///
/// Same rules as [Config]: an explicit override wins, debug can never
/// accidentally reach production, and 10.0.2.2 is the Android emulator's alias
/// for the host's localhost. 3100 is the port slk-core's dev server uses.
class CoreConfig {
  static const String _override = String.fromEnvironment('CORE_API_BASE_URL');

  static const String _prod = 'https://slk-core.vercel.app';
  static const String _dev = 'http://10.0.2.2:3100';

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    return kDebugMode ? _dev : _prod;
  }

  static String get apiRoot => '$baseUrl/api/v1';
}
