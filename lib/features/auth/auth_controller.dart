import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage.dart';
import '../../models/session.dart';

/// Auth status the router redirects on.
enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({required this.status, this.session});
  final AuthStatus status;
  final Session? session;

  bool get isSignedIn => status == AuthStatus.signedIn && session != null;

  AuthState copyWith({AuthStatus? status, Session? session, bool clearSession = false}) =>
      AuthState(
        status: status ?? this.status,
        session: clearSession ? null : (session ?? this.session),
      );
}

class AuthController extends Notifier<AuthState> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  AuthState build() {
    // Kick off session restore; state starts "unknown" so the router shows a
    // splash until we know whether a token exists.
    _restore();
    return const AuthState(status: AuthStatus.unknown);
  }

  Future<void> _restore() async {
    final token = await SecureStore.instance.readToken();
    final cached = await SecureStore.instance.readSession();
    if (token == null || cached == null) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }
    // Trust the cached session for an instant start; verify in the background.
    state = AuthState(status: AuthStatus.signedIn, session: Session.decode(cached));
    try {
      final me = await _api.get('/auth/me');
      final session = Session.fromJson((me as Map).cast<String, dynamic>());
      await SecureStore.instance.writeSession(session.encode());
      state = AuthState(status: AuthStatus.signedIn, session: session);
    } on ApiException catch (e) {
      if (e.isUnauthorized) await signOut();
    }
  }

  /// Fetch the staff + store pickers for the login screen.
  Future<Map<String, dynamic>> loginOptions() async {
    final data = await _api.get('/auth/staff');
    return (data as Map).cast<String, dynamic>();
  }

  Future<void> signIn({required String staffId, required String pin, String? storeId}) async {
    final data = await _api.post('/auth/login', body: {
      'staffId': staffId,
      'pin': pin,
      'storeId': ?storeId,
    });
    final map = (data as Map).cast<String, dynamic>();
    final token = map['token'] as String;
    final staff = (map['staff'] as Map).cast<String, dynamic>();
    final store = (map['store'] as Map).cast<String, dynamic>();

    final session = Session(
      staffId: staff['id'] as String,
      name: staff['name'] as String,
      role: staff['role'] as String,
      storeId: store['id'] as String,
      storeName: store['name'] as String,
      storeCode: (store['code'] ?? 'R1') as String,
    );

    await SecureStore.instance.writeToken(token);
    await SecureStore.instance.writeSession(session.encode());
    state = AuthState(status: AuthStatus.signedIn, session: session);
  }

  Future<void> signOut() async {
    await SecureStore.instance.clear();
    state = const AuthState(status: AuthStatus.signedOut);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
