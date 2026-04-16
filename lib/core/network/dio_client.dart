import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../services/storage_service.dart';
import 'auth_interceptor.dart';

final backendDioProvider = Provider<Dio>((ref) {
  final storage = ref.read(storageServiceProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.backendUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  dio.interceptors.add(AuthInterceptor(storage, dio));

  return dio;
});

final sas4DioProvider = Provider<Dio>((ref) {
  final storage = ref.read(storageServiceProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.sas4ApiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/json',
    },
  ));

  dio.interceptors.add(AuthInterceptor(storage, dio));

  return dio;
});
