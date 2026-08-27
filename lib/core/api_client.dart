import 'package:dio/dio.dart';

import 'config.dart';
import 'storage.dart';

/// A failed API call — carries a human-readable message (from the API's
/// { ok:false, error } envelope where possible) and the HTTP status.
class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Wraps Dio: injects the bearer token, unwraps the { ok, data } envelope, and
/// turns failures into [ApiException]. A single instance is shared app-wide.
class ApiClient {
  ApiClient({void Function()? onUnauthorized}) : _onUnauthorized = onUnauthorized {
    _dio = Dio(
      BaseOptions(
        baseUrl: Config.apiRoot,
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
          final token = await SecureStore.instance.readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;
  final void Function()? _onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body, Duration? receiveTimeout}) => _send(
        () => _dio.post(
          path,
          data: body,
          options: receiveTimeout != null ? Options(receiveTimeout: receiveTimeout) : null,
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

    throw ApiException(_errorFrom(data, 'Request failed ($status).'), status: status);
  }

  String _errorFrom(dynamic data, String fallback) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return fallback;
  }
}
