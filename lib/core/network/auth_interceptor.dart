import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import '../services/storage_service.dart';
import '../constants/api_constants.dart';

class AuthInterceptor extends Interceptor {
  final StorageService _storage;
  final Dio _dio;

  AuthInterceptor(this._storage, this._dio);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
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
      final adminId = await _storage.getAdminId();
      if (adminId == null) {
        return handler.next(err);
      }

      dev.log('Attempting token refresh for adminId: $adminId', name: 'HTTP');

      final refreshDio = Dio(BaseOptions(
        baseUrl: ApiConstants.backendUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await refreshDio.post(
        ApiConstants.refreshToken,
        data: {'adminId': adminId},
      );

      if (response.data['success'] == true) {
        final newToken = response.data['token'] as String;
        final expiresAt = response.data['expiresAt'] as String;

        await _storage.saveToken(newToken);
        await _storage.saveTokenExpiry(expiresAt);

        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newToken';
        retryOptions.headers['x-auth-token'] = newToken;

        final retryResponse = await _dio.fetch(retryOptions);
        return handler.resolve(retryResponse);
      }
    } catch (e) {
      dev.log('Token refresh failed: $e', name: 'HTTP');
    }

    await _storage.clearAll();
    handler.next(err);
  }
}
