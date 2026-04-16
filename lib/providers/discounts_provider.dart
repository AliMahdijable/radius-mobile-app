import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../models/discount_model.dart';

class DiscountsState {
  final List<DiscountModel> discounts;
  final bool isLoading;
  final String? error;

  const DiscountsState({
    this.discounts = const [],
    this.isLoading = false,
    this.error,
  });

  DiscountsState copyWith({
    List<DiscountModel>? discounts,
    bool? isLoading,
    String? error,
  }) {
    return DiscountsState(
      discounts: discounts ?? this.discounts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class DiscountsNotifier extends StateNotifier<DiscountsState> {
  final Dio _dio;
  final StorageService _storage;

  DiscountsNotifier(this._dio, this._storage) : super(const DiscountsState());

  Future<void> loadDiscounts() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get(
        ApiConstants.discounts,
        queryParameters: {'adminId': adminId},
        options: Options(headers: {
          'x-admin-id': adminId,
        }),
      );

      if (response.data is Map && response.data['success'] == true) {
        final rawList = response.data['data'] as List? ?? [];
        final discounts = rawList
            .map((e) => DiscountModel.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(discounts: discounts, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, error: 'فشل تحميل الخصومات');
      }
    } catch (e) {
      dev.log('loadDiscounts error: $e', name: 'DISCOUNTS');
      state = state.copyWith(isLoading: false, error: 'خطأ في تحميل الخصومات');
    }
  }

  Future<bool> addDiscount({
    required String subscriberUsername,
    required int subscriberId,
    required double discountAmount,
    String? packageName,
    double? packagePrice,
  }) async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return false;

    try {
      final response = await _dio.post(
        ApiConstants.discounts,
        data: {
          'adminId': adminId,
          'subscriber_username': subscriberUsername,
          'subscriber_id': subscriberId,
          'discount_amount': discountAmount,
          'package_name': packageName,
          'package_price': packagePrice,
        },
      );

      final success = response.data is Map && response.data['success'] == true;
      if (success) await loadDiscounts();
      return success;
    } catch (e) {
      dev.log('addDiscount error: $e', name: 'DISCOUNTS');
      return false;
    }
  }

  Future<bool> updateDiscount(int id, double discountAmount) async {
    try {
      final response = await _dio.put(
        '${ApiConstants.discounts}/$id',
        data: {'discount_amount': discountAmount},
      );

      final success = response.data is Map && response.data['success'] == true;
      if (success) await loadDiscounts();
      return success;
    } catch (e) {
      dev.log('updateDiscount error: $e', name: 'DISCOUNTS');
      return false;
    }
  }

  Future<bool> deleteDiscount(int id) async {
    try {
      final response = await _dio.delete('${ApiConstants.discounts}/$id');
      final success = response.data is Map && response.data['success'] == true;
      if (success) await loadDiscounts();
      return success;
    } catch (e) {
      dev.log('deleteDiscount error: $e', name: 'DISCOUNTS');
      return false;
    }
  }

  Future<void> deleteAll() async {
    final ids = state.discounts.map((d) => d.id).toList();
    for (final id in ids) {
      await deleteDiscount(id);
    }
  }
}

final discountsProvider =
    StateNotifierProvider<DiscountsNotifier, DiscountsState>((ref) {
  return DiscountsNotifier(
    ref.read(backendDioProvider),
    ref.read(storageServiceProvider),
  );
});
