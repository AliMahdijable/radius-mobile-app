import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import '../services/storage_service.dart';
import '../services/session_refresh_service.dart';
import '../services/session_events.dart';

class AuthInterceptor extends Interceptor {
  final StorageService _storage;
  final Dio _dio;
  static bool _sessionExpiredHandled = false;

  AuthInterceptor(this._storage, this._dio);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!options.path.contains('/api/auth/')) {
      await SessionRefreshService.ensureValidSession(_storage);
    }

    final token = await _storage.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
      options.headers['x-auth-token'] = token;
      dev.log(
        'REQUEST: ${options.method} ${options.uri} [Token: ${token.substring(0, 20)}...]',
        name: 'HTTP',
      );
    } else {
      dev.log(
        'REQUEST: ${options.method} ${options.uri} [NO TOKEN!]',
        name: 'HTTP',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _sessionExpiredHandled = false;
    dev.log(
      'RESPONSE: ${response.statusCode} ${response.requestOptions.uri}',
      name: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    dev.log(
      'ERROR: ${err.response?.statusCode} ${err.requestOptions.uri} - ${err.message}',
      name: 'HTTP',
    );

    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    final path = err.requestOptions.path;
    if (path.contains('/api/auth/')) {
      return handler.next(err);
    }

    try {
      final refreshResult = await SessionRefreshService.ensureValidSession(
        _storage,
        forceRefresh: true,
      );

      if (refreshResult != null) {
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer ${refreshResult.token}';
        retryOptions.headers['x-auth-token'] = refreshResult.token;

        final retryResponse = await _dio.fetch(retryOptions);
        return handler.resolve(retryResponse);
      }
    } catch (e) {
      dev.log('Token refresh failed: $e', name: 'HTTP');
    }

    await _storage.clearAll();
    if (!_sessionExpiredHandled) {
      _sessionExpiredHandled = true;
      SessionEvents.emitExpired(
        reason: 'انتهت الجلسة أو تعذر تحديثها. يرجى تسجيل الدخول مرة أخرى.',
      );
    }
    handler.next(err);
  }
}
