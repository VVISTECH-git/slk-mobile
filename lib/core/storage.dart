import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over platform secure storage for the auth token + cached session.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kToken = 'slk_token';
  static const _kSession = 'slk_session';

  // slk-core issues its own token, under its own key.
  //
  // Separate rather than shared: the two backends are different systems with
  // different accounts, and signing out of one must not sign you out of the
  // other while the migration has screens on both.
  static const _kCoreToken = 'slk_core_token';
  static const _kCoreSession = 'slk_core_session';

  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<void> writeToken(String token) => _storage.write(key: _kToken, value: token);

  Future<String?> readSession() => _storage.read(key: _kSession);
  Future<void> writeSession(String json) => _storage.write(key: _kSession, value: json);

  Future<String?> readCoreToken() => _storage.read(key: _kCoreToken);
  Future<void> writeCoreToken(String token) =>
      _storage.write(key: _kCoreToken, value: token);

  Future<String?> readCoreSession() => _storage.read(key: _kCoreSession);
  Future<void> writeCoreSession(String json) =>
      _storage.write(key: _kCoreSession, value: json);

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kSession);
  }

  Future<void> clearCore() async {
    await _storage.delete(key: _kCoreToken);
    await _storage.delete(key: _kCoreSession);
  }
}
