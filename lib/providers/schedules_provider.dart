import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../models/schedule_model.dart';
import '../core/services/storage_service.dart';

class SchedulesState {
  final List<ScheduleModel> schedules;
  final bool isLoading;
  final String? error;

  const SchedulesState({
    this.schedules = const [],
    this.isLoading = false,
    this.error,
  });

  SchedulesState copyWith({
    List<ScheduleModel>? schedules,
    bool? isLoading,
    String? error,
  }) {
    return SchedulesState(
      schedules: schedules ?? this.schedules,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SchedulesNotifier extends StateNotifier<SchedulesState> {
  final Dio _dio;
  final StorageService _storage;

  SchedulesNotifier(this._dio, this._storage)
      : super(const SchedulesState());

  dynamic _decodeResponseData(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  Future<void> loadSchedules() async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response =
          await _dio.get('${ApiConstants.waSchedules}/$_adminId');

      final decoded = _decodeResponseData(response.data);
      List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map && decoded['schedules'] is List) {
        data = decoded['schedules'] as List<dynamic>;
      } else {
        data = [];
      }

      final list = <ScheduleModel>[];
      for (final e in data) {
        if (e is! Map) continue;
        try {
          list.add(ScheduleModel.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // تخطّي صف تالف بدل إسقاط كامل القائمة
        }
      }
      state = state.copyWith(schedules: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'فشل تحميل الجداول');
    }
  }

  /// Returns `null` on success, or an Arabic error message on failure.
  Map<String, dynamic>? _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<String?> saveSchedule(ScheduleModel schedule) async {
    try {
      final response = await _dio.post(
        ApiConstants.waSaveSchedule,
        data: schedule.toSaveJson(),
      );
      final body = _asJsonMap(_decodeResponseData(response.data));
      if (body == null) {
        return 'استجابة غير متوقعة من الخادم';
      }
      final ok = body['success'] == true ||
          body['success'] == 1 ||
          body['success'] == '1' ||
          body['success'] == 'true';
      if (ok) {
        // الحفظ نجح حتى لو إعادة التحميل فشلت (لا نعرض «فشل حفظ» بسبب fromJson/شبكة).
        try {
          await loadSchedules();
        } catch (_) {}
        return null;
      }
      return body['message']?.toString() ??
          body['error']?.toString() ??
          'فشل في حفظ الجدولة';
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final map = _asJsonMap(data);
      if (map != null) {
        if (map['message'] != null) return map['message'].toString();
        if (map['error'] != null) return map['error'].toString();
      }
      if (data is String && data.isNotEmpty) {
        return data.length > 200 ? '${data.substring(0, 200)}…' : data;
      }
      if (code != null) {
        return '${e.message ?? 'فشل الاتصال بالخادم'} (رمز $code)';
      }
      return e.message ?? 'فشل في حفظ الجدولة';
    } catch (_) {
      return 'فشل في حفظ الجدولة';
    }
  }

  Future<bool> toggleSchedule(String scheduleType, bool isEnabled) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      await _dio.patch(
        ApiConstants.waScheduleToggle,
        data: {
          'adminId': _adminId,
          'scheduleType': scheduleType,
          'isEnabled': isEnabled,
        },
      );
      await loadSchedules();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSchedule(String scheduleType) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      await _dio.delete(
        '${ApiConstants.waSchedule}/$_adminId/$scheduleType',
      );
      await loadSchedules();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> triggerSchedule(String scheduleType) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      await _dio.post(
        ApiConstants.waTriggerSchedule,
        data: {
          'adminId': _adminId,
          'scheduleType': scheduleType,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final schedulesProvider =
    StateNotifierProvider<SchedulesNotifier, SchedulesState>((ref) {
  return SchedulesNotifier(
    ref.read(backendDioProvider),
    ref.read(storageServiceProvider),
  );
});
