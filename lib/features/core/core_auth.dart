import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/storage.dart';
import '../../models/core.dart';

/// Signing in to slk-core.
///
/// A second, independent session alongside the tantu one in
/// `features/auth/auth_controller.dart`. Kept apart on purpose: the two are
/// different systems with different accounts, and while the migration has
/// screens on both, being signed out of one must not sign you out of the other.
///
/// The shapes differ too. tantu asks for a staff id, a PIN and a store;
/// slk-core asks for a code and a PIN, and has no notion of a store — where
/// stock sits is a location on a movement, not a property of who is holding
/// the phone.

/// This session's token, independent of whether storage kept it.
///
/// Secure storage is where a token *persists*; it is not where the session
/// lives. Treating the two as the same thing meant a keystore that refused a
/// write left the app unable to authenticate a session the server had already
/// granted.
String? _liveToken;

/// Storage first — it survives a restart — then whatever this run holds.
Future<String?> _coreToken() async {
  try {
    final stored = await SecureStore.instance.readCoreToken();
    if (stored != null) return stored;
  } catch (_) {
    // Unreadable storage is not an absent session.
  }

  return _liveToken;
}

/// The client pointed at slk-core. Its own base URL, its own token.
final coreApiProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: CoreConfig.apiRoot,
    readToken: _coreToken,
    onUnauthorized: () {
      try {
        ref.read(coreAuthProvider.notifier).signOut();
      } catch (_) {}
    },
  );
});

enum CoreAuthStatus { unknown, signedOut, signedIn }

/// Whether a restore that began earlier is still entitled to write its result.
///
/// Only while nothing has happened since it started. `unknown` is the state
/// the notifier is built in and left in until either the restore finishes or
/// somebody signs in; anything else means somebody did, and what they did is
/// newer than the picture of storage this restore is holding.
///
/// A named rule rather than an inline `if`, because deleting it looks harmless
/// and is not: without it a slow read of a cold Android keystore overwrites a
/// live session with "signed out", and the person who just signed in
/// successfully is looking at the sign-in screen again.
bool restoreMayApply(CoreAuthStatus current) =>
    current == CoreAuthStatus.unknown;

class CoreAuthState {
  const CoreAuthState({required this.status, this.actor});

  final CoreAuthStatus status;
  final CoreActor? actor;

  bool get isSignedIn => status == CoreAuthStatus.signedIn && actor != null;
}

class CoreAuth extends Notifier<CoreAuthState> {
  ApiClient get _api => ref.read(coreApiProvider);

  @override
  CoreAuthState build() {
    _restore();
    return const CoreAuthState(status: CoreAuthStatus.unknown);
  }

  /// Trust the cached actor for an instant start, then confirm with the server.
  ///
  /// A token lasts thirty days and can be revoked from the office in between,
  /// so "signed in three weeks ago" is not an answer. `/auth/me` turns it into
  /// one, and a 401 on the way past signs this session out through the client's
  /// own unauthorized hook.
  Future<void> _restore() async {
    String? token;
    String? cached;

    try {
      token = await SecureStore.instance.readCoreToken();
      cached = await SecureStore.instance.readCoreSession();
    } catch (_) {
      // Storage that cannot be read is not a session that does not exist, but
      // there is nothing to restore either way. Fall through to signed out —
      // and, crucially, only if nobody has signed in meanwhile.
    }

    /*
      Everything below is conditional on the state still being `unknown`.

      This runs from build(), and reading the Android keystore the first time
      after an install takes seconds. In that window the sign-in screen is
      already up and somebody can sign in and succeed — and this, arriving
      late with a picture of storage from before they did, would overwrite
      their live session with "signed out".

      A stale answer must never beat a fresh one. `unknown` means nothing has
      happened since this started; anything else means something has, and what
      happened is newer than what this found.
    */
    if (!restoreMayApply(state.status)) return;

    if (token == null || cached == null) {
      state = const CoreAuthState(status: CoreAuthStatus.signedOut);
      return;
    }

    CoreActor restored;

    try {
      restored = CoreActor.decode(cached);
    } catch (_) {
      // A cached session we cannot read is worse than none — it would keep
      // the app "signed in" as nobody.
      state = const CoreAuthState(status: CoreAuthStatus.signedOut);
      return;
    }

    state = CoreAuthState(status: CoreAuthStatus.signedIn, actor: restored);

    try {
      final me = await _api.get('/auth/me');
      final actor = CoreActor.fromJson((me as Map).cast<String, dynamic>());

      // Guarded again: the confirmation round trip is another window, and a
      // sign-out or a fresh sign-in during it is likewise newer than this.
      if (!state.isSignedIn || state.actor?.id != restored.id) return;

      try {
        await SecureStore.instance.writeCoreSession(actor.encode());
      } catch (_) {
        // Refreshing the cache is a convenience, not the session.
      }

      state = CoreAuthState(status: CoreAuthStatus.signedIn, actor: actor);
    } on ApiException catch (e) {
      if (e.isUnauthorized) await signOut();
      // Anything else — no signal, server down — leaves the cached actor in
      // place. Being offline is not being signed out, and a warehouse has
      // patchy signal.
    }
  }

  Future<void> signIn({
    required String code,
    required String pin,
    String? device,
  }) async {
    final data = await _api.post('/auth/login', body: {
      'code': code,
      'pin': pin,
      if (device != null && device.isNotEmpty) 'device': device,
    });

    final map = (data as Map).cast<String, dynamic>();
    final actor = CoreActor.fromJson((map['actor'] as Map).cast<String, dynamic>());

    /*
      The session is live from the moment the server says so.

      Persisting it can fail — the Android keystore is not always ready on a
      first run — and if it does, the old code threw *after* the server had
      already minted a token. The person was left on the sign-in screen with a
      token existing that they could not use, and the only clue a snackbar
      that faded in four seconds. Signing in again just minted another.

      So the write is allowed to fail. What it costs is having to sign in
      again next launch, which is a nuisance; what it used to cost was not
      being able to sign in at all.
    */
    // Held whether or not the write works, so this session survives storage
    // that is unavailable *now* and becomes readable later.
    _liveToken = map['token'] as String;

    try {
      await SecureStore.instance.writeCoreToken(_liveToken!);
      await SecureStore.instance.writeCoreSession(actor.encode());
    } catch (_) {
      // Nothing to do. The session works for as long as the app is open.
    }

    state = CoreAuthState(status: CoreAuthStatus.signedIn, actor: actor);
  }

  /// Tell the server first, then forget locally.
  ///
  /// The server call revokes this handset's token so a copied one is dead
  /// rather than merely gone from this phone — but it is allowed to fail.
  /// Signing out with no signal must still sign you out.
  Future<void> signOut() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}

    // Cleared before storage, so a failure to clear storage cannot leave the
    // session usable in memory after someone has signed out.
    _liveToken = null;

    try {
      await SecureStore.instance.clearCore();
    } catch (_) {}

    state = const CoreAuthState(status: CoreAuthStatus.signedOut);
  }
}

final coreAuthProvider =
    NotifierProvider<CoreAuth, CoreAuthState>(CoreAuth.new);

/// The vocabulary and the locations, fetched once and held.
///
/// Every dropdown on the entry form comes from these. Fetched whole on first
/// use rather than a list at a time — thirty round trips on a mobile network
/// to fill one form is the difference between a usable screen and one nobody
/// waits for.
final coreOptionsProvider = FutureProvider<CoreOptions>((ref) async {
  final data = await ref.read(coreApiProvider).get('/options');
  return parseCoreOptions((data as Map).cast<String, dynamic>());
});

final coreLocationsProvider = FutureProvider<List<CoreLocation>>((ref) async {
  final data = await ref.read(coreApiProvider).get('/locations');
  return [
    for (final row in (data as List))
      CoreLocation.fromJson((row as Map).cast<String, dynamic>()),
  ];
});
