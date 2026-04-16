import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../models/print_template_model.dart';

class PrintTemplatesState {
  final List<PrintTemplateModel> templates;
  final bool loading;
  final String? error;

  const PrintTemplatesState({
    this.templates = const [],
    this.loading = false,
    this.error,
  });

  PrintTemplatesState copyWith({
    List<PrintTemplateModel>? templates,
    bool? loading,
    String? error,
  }) {
    return PrintTemplatesState(
      templates: templates ?? this.templates,
      loading: loading ?? this.loading,
      error: error,
    );
  }

  PrintTemplateModel? get activeTemplate {
    try {
      return templates.firstWhere((t) => t.isActive);
    } catch (_) {
      return null;
    }
  }
}

class PrintTemplatesNotifier extends StateNotifier<PrintTemplatesState> {
  final Dio _dio;
  final StorageService _storage;

  PrintTemplatesNotifier(this._dio, this._storage)
      : super(const PrintTemplatesState());

  Future<void> loadTemplates() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _storage.getAdminId();
      if (adminId == null) {
        state = state.copyWith(loading: false, error: 'معرف المدير غير متوفر');
        return;
      }
      final res = await _dio.get('${ApiConstants.printTemplates}/$adminId');
      final data = res.data;
      if (data['success'] == true && data['templates'] is List) {
        final list = (data['templates'] as List)
            .map((e) => PrintTemplateModel.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(templates: list, loading: false);
      } else {
        state = state.copyWith(loading: false, templates: []);
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: 'فشل في جلب القوالب');
    }
  }

  Future<bool> createTemplate(PrintTemplateModel template) async {
    try {
      final adminId = await _storage.getAdminId();
      final res = await _dio.post(
        ApiConstants.printTemplateCreate,
        data: {
          'adminId': adminId,
          'templateType': template.templateType,
          'templateName': template.templateName,
          'content': template.content,
          'templateData': template.templateData,
          'isActive': template.isActive,
        },
      );
      if (res.data['success'] == true) {
        await loadTemplates();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateTemplate(int id, PrintTemplateModel template) async {
    try {
      final res = await _dio.put(
        '${ApiConstants.printTemplateUpdate}/$id',
        data: {
          'templateName': template.templateName,
          'content': template.content,
          'templateData': template.templateData,
          'isActive': template.isActive,
        },
      );
      if (res.data['success'] == true) {
        await loadTemplates();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteTemplate(int id) async {
    try {
      final res = await _dio.delete(
        '${ApiConstants.printTemplateDelete}/$id',
      );
      if (res.data['success'] == true) {
        await loadTemplates();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleActive(int id) async {
    try {
      final res = await _dio.patch(
        '${ApiConstants.printTemplateToggle}/$id',
      );
      if (res.data['success'] == true) {
        await loadTemplates();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

final printTemplatesProvider =
    StateNotifierProvider<PrintTemplatesNotifier, PrintTemplatesState>((ref) {
  return PrintTemplatesNotifier(
    ref.read(backendDioProvider),
    ref.read(storageServiceProvider),
  );
});
