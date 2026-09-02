import 'dart:math';

import 'package:dio/dio.dart';

import 'config.dart';
import 'storage.dart';

/// A name for one save, so a retry of it cannot become a second record.
///
/// The phone cannot tell "the request never arrived" from "the answer was
/// lost" — both surface as a connection error — and on a warehouse floor the
/// second is common and the person will always press the button again. Naming
/// the attempt lets the server recognise the repeat and answer with what the
/// first one made.
///
/// Generate ONCE per save and reuse it for every retry of that same save; a
/// fresh key per tap is exactly the bug this exists to prevent. Mint a new one
/// only after a success, for the next record.
///
/// 32 hex characters from the OS. Not a UUID, because nothing here needs the
/// structure and the app carries no uuid package to make one.
String idempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// A failed API call — carries a human-readable message (from the API's
/// { ok:false, error } envelope where possible) and the HTTP status.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.errors = const {}});
  final String message;
  final int? status;

  /// Field key → what is wrong with it, where the API sent a form's failure
  /// (a 422). Empty for everything else, so a caller that does not care can
  /// keep showing [message] and one that does can point at the field.
  final Map<String, String> errors;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Wraps Dio: injects the bearer token, unwraps the { ok, data } envelope, and
/// turns failures into [ApiException].
///
/// One instance per backend. [baseUrl] and [readToken] default to tantu's, so
/// every existing call site is unchanged; slk-core gets its own instance with
/// its own root and its own token, because the two issue different tokens and
/// sending one to the other is a 401 that looks like a bug.
///
/// Both backends answer in the same envelope — that is not a coincidence,
/// slk-core's API was written to match what this client already expected.
class ApiClient {
  ApiClient({
    void Function()? onUnauthorized,
    String? baseUrl,
    Future<String?> Function()? readToken,
  })  : _onUnauthorized = onUnauthorized,
        _readToken = readToken ?? SecureStore.instance.readToken {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? Config.apiRoot,
        // Fail in a reasonable window so a slow/unreachable server surfaces a
        // retry rather than an endless spinner. (Backend should be always-on;
        // this is the safety net.)
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 25),
        // Don't throw on non-2xx — we inspect the envelope ourselves.
        validateStatus: (_) => true,
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;
  final void Function()? _onUnauthorized;
  final Future<String?> Function() _readToken;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(
    String path, {
    Object? body,
    Duration? receiveTimeout,
    /// Extra headers — an Idempotency-Key, mostly. See [idempotencyKey].
    Map<String, String>? headers,
  }) =>
      _send(
        () => _dio.post(
          path,
          data: body,
          options: receiveTimeout != null || headers != null
              ? Options(receiveTimeout: receiveTimeout, headers: headers)
              : null,
        ),
      );

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch(path, data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => _dio.put(path, data: body));

  Future<dynamic> delete(String path) => _send(() => _dio.delete(path));

  Future<dynamic> _send(Future<Response> Function() call) async {
    late final Response res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiException(
        e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout
            ? 'The server took too long to respond. Please try again.'
            : 'Cannot reach the server. Check your connection.',
      );
    }

    final status = res.statusCode ?? 0;
    final data = res.data;

    if (status == 401) {
      _onUnauthorized?.call();
      throw ApiException(_errorFrom(data, 'Session expired — please sign in again.'), status: 401);
    }

    if (data is Map && data['ok'] == true) {
      return data['data'];
    }

    throw ApiException(
      _errorFrom(data, 'Request failed ($status).'),
      status: status,
      errors: _fieldErrorsFrom(data),
    );
  }

  String _errorFrom(dynamic data, String fallback) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return fallback;
  }

  /// The `errors` map slk-core sends alongside `error` on a 422. Anything that
  /// is not a string pair is dropped rather than crashing the screen that was
  /// about to show it.
  Map<String, String> _fieldErrorsFrom(dynamic data) {
    if (data is! Map || data['errors'] is! Map) return const {};

    final out = <String, String>{};
    (data['errors'] as Map).forEach((key, value) {
      if (key is String && value is String) out[key] = value;
    });

    return out;
  }
}
