import 'package:dio/dio.dart';

/// Shared Dio instance pointing at the production backend. Auth token
/// is attached per-request by the caller (or by an interceptor later).
class ApiClient {
  ApiClient._();

  static const String baseUrl = 'https://rad.mysvcs.net';

  static final Dio dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    // Accept all 2xx/4xx — let the caller branch on response.data['success'].
    validateStatus: (s) => s != null && s < 500,
  ));
}
