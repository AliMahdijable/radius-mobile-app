import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../models/template_model.dart';
import '../core/services/storage_service.dart';

class TemplatesState {
  final List<TemplateModel> templates;
  final bool isLoading;
  final String? error;

  const TemplatesState({
    this.templates = const [],
    this.isLoading = false,
    this.error,
  });

  TemplatesState copyWith({
    List<TemplateModel>? templates,
    bool? isLoading,
    String? error,
  }) {
    return TemplatesState(
      templates: templates ?? this.templates,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TemplatesNotifier extends StateNotifier<TemplatesState> {
  final Dio _dio;
  final StorageService _storage;

  TemplatesNotifier(this._dio, this._storage)
      : super(const TemplatesState());

  Future<void> loadTemplates() async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response =
          await _dio.get('${ApiConstants.waTemplates}/$_adminId');
      if (response.data is List) {
        final list = (response.data as List)
            .map((e) => TemplateModel.fromJson(e))
            .toList();
        state = state.copyWith(templates: list, isLoading: false);
      } else if (response.data['templates'] is List) {
        final list = (response.data['templates'] as List)
            .map((e) => TemplateModel.fromJson(e))
            .toList();
        state = state.copyWith(templates: list, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'فشل تحميل القوالب');
    }
  }

  Future<bool> saveTemplate(TemplateModel template) async {
    try {
      final response = await _dio.post(
        ApiConstants.waSaveTemplate,
        data: template.toJson(),
      );
      if (response.data['success'] == true) {
        await loadTemplates();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteTemplate(String templateType) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      await _dio.delete(
        '${ApiConstants.waTemplate}/$_adminId/$templateType',
      );
      await loadTemplates();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleTemplate(String templateType, bool isActive) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      await _dio.patch(
        ApiConstants.waTemplateToggle,
        data: {
          'adminId': _adminId,
          'templateType': templateType,
          'isActive': isActive,
        },
      );
      await loadTemplates();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final templatesProvider =
    StateNotifierProvider<TemplatesNotifier, TemplatesState>((ref) {
  return TemplatesNotifier(
    ref.read(backendDioProvider),
    ref.read(storageServiceProvider),
  );
});
