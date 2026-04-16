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

  Future<void> loadSchedules() async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response =
          await _dio.get('${ApiConstants.waSchedules}/$_adminId');

      List<dynamic> data;
      if (response.data is List) {
        data = response.data;
      } else if (response.data['schedules'] is List) {
        data = response.data['schedules'];
      } else {
        data = [];
      }

      final list = data.map((e) => ScheduleModel.fromJson(e)).toList();
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
      final body = _asJsonMap(response.data);
      if (body == null) {
        return 'استجابة غير متوقعة من الخادم';
      }
      if (body['success'] == true) {
        await loadSchedules();
        return null;
      }
      return body['message']?.toString() ?? 'فشل في حفظ الجدولة';
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final map = _asJsonMap(data);
      if (map != null && map['message'] != null) {
        return map['message'].toString();
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
