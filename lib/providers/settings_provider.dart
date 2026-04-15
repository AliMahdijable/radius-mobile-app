import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../models/whatsapp_status_model.dart';
import '../core/services/storage_service.dart';

class SettingsState {
  final FeaturesModel features;
  final bool isLoading;
  final String? error;

  const SettingsState({
    this.features = const FeaturesModel(),
    this.isLoading = false,
    this.error,
  });

  SettingsState copyWith({
    FeaturesModel? features,
    bool? isLoading,
    String? error,
  }) {
    return SettingsState(
      features: features ?? this.features,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final Dio _dio;
  final StorageService _storage;

  SettingsNotifier(this._dio, this._storage)
      : super(const SettingsState());

  Future<void> loadFeatures() async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final response =
          await _dio.get('${ApiConstants.waGetFeatures}/$_adminId');
      if (response.data is Map) {
        final features = response.data['features'] ?? response.data;
        state = state.copyWith(
          features: FeaturesModel.fromJson(
            Map<String, dynamic>.from(features),
          ),
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'فشل تحميل الإعدادات');
    }
  }

  Future<bool> saveFeatures(FeaturesModel features) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      final response = await _dio.post(ApiConstants.waSaveFeatures, data: {
        'adminId': _adminId,
        'features': features.toJson(),
      });
      if (response.data['success'] == true) {
        state = state.copyWith(features: features);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void updateFeature(String key, bool value) {
    final f = state.features;
    FeaturesModel updated;
    switch (key) {
      case 'sendOnActivation':
        updated = f.copyWith(sendOnActivation: value);
        break;
      case 'expiryReminder':
        updated = f.copyWith(expiryReminder: value);
        break;
      case 'debtReminder':
        updated = f.copyWith(debtReminder: value);
        break;
      case 'serviceEndNotification':
        updated = f.copyWith(serviceEndNotification: value);
        break;
      case 'welcomeMessage':
        updated = f.copyWith(welcomeMessage: value);
        break;
      case 'sendOnExtension':
        updated = f.copyWith(sendOnExtension: value);
        break;
      default:
        return;
    }
    state = state.copyWith(features: updated);
    saveFeatures(updated);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(
    ref.read(backendDioProvider),
    ref.read(storageServiceProvider),
  );
});
