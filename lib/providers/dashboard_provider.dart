import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/encryption_service.dart';

class DashboardState {
  final int totalSubscribers;
  final int activeSubscribers;
  final int expiredSubscribers;
  final int nearExpiryCount;
  final int expiredTodayCount;
  final int debtors;
  final double totalDebt;
  final int onlineCount;
  final int offlineCount;
  final int todayActivations;
  final int todayExtensions;
  final String managerBalance;
  final String managerPoints;
  final List<Map<String, dynamic>> recentActivities;
  final List<Map<String, dynamic>> nearExpiryList;
  final List<Map<String, dynamic>> expiredTodayList;
  final bool isLoading;
  final String? error;

  const DashboardState({
    this.totalSubscribers = 0,
    this.activeSubscribers = 0,
    this.expiredSubscribers = 0,
    this.nearExpiryCount = 0,
    this.expiredTodayCount = 0,
    this.debtors = 0,
    this.totalDebt = 0,
    this.onlineCount = 0,
    this.offlineCount = 0,
    this.todayActivations = 0,
    this.todayExtensions = 0,
    this.managerBalance = '',
    this.managerPoints = '',
    this.recentActivities = const [],
    this.nearExpiryList = const [],
    this.expiredTodayList = const [],
    this.isLoading = false,
    this.error,
  });

  int get totalAlerts => nearExpiryCount + expiredTodayCount;

  DashboardState copyWith({
    int? totalSubscribers,
    int? activeSubscribers,
    int? expiredSubscribers,
    int? nearExpiryCount,
    int? expiredTodayCount,
    int? debtors,
    double? totalDebt,
    int? onlineCount,
    int? offlineCount,
    int? todayActivations,
    int? todayExtensions,
    String? managerBalance,
    String? managerPoints,
    List<Map<String, dynamic>>? recentActivities,
    List<Map<String, dynamic>>? nearExpiryList,
    List<Map<String, dynamic>>? expiredTodayList,
    bool? isLoading,
    String? error,
  }) {
    return DashboardState(
      totalSubscribers: totalSubscribers ?? this.totalSubscribers,
      activeSubscribers: activeSubscribers ?? this.activeSubscribers,
      expiredSubscribers: expiredSubscribers ?? this.expiredSubscribers,
      nearExpiryCount: nearExpiryCount ?? this.nearExpiryCount,
      expiredTodayCount: expiredTodayCount ?? this.expiredTodayCount,
      debtors: debtors ?? this.debtors,
      totalDebt: totalDebt ?? this.totalDebt,
      onlineCount: onlineCount ?? this.onlineCount,
      offlineCount: offlineCount ?? this.offlineCount,
      todayActivations: todayActivations ?? this.todayActivations,
      todayExtensions: todayExtensions ?? this.todayExtensions,
      managerBalance: managerBalance ?? this.managerBalance,
      managerPoints: managerPoints ?? this.managerPoints,
      recentActivities: recentActivities ?? this.recentActivities,
      nearExpiryList: nearExpiryList ?? this.nearExpiryList,
      expiredTodayList: expiredTodayList ?? this.expiredTodayList,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Dio _sas4Dio;

  DashboardNotifier(this._sas4Dio) : super(const DashboardState());

  int _parseWidgetInt(dynamic data) {
    if (data is Map && data.containsKey('data')) {
      return int.tryParse(data['data'].toString()) ?? 0;
    }
    if (data is int) return data;
    return int.tryParse(data.toString()) ?? 0;
  }

  String _parseWidgetStr(dynamic data) {
    if (data is Map && data.containsKey('data')) {
      return data['data'].toString();
    }
    return data?.toString() ?? '0';
  }

  Future<void> loadDashboard({
    required String adminId,
    required String token,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    final backendDio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'x-auth-token': token,
      },
    ));

    try {
      // 1) SAS4 Widgets — 6 simple GET requests in parallel
      final widgetResults = await Future.wait([
        _sas4Dio.get(ApiConstants.sas4WdUsersCount).catchError((_) => Response(
            requestOptions: RequestOptions(), data: {'data': 0})),
        _sas4Dio.get(ApiConstants.sas4WdActiveCount).catchError((_) => Response(
            requestOptions: RequestOptions(), data: {'data': 0})),
        _sas4Dio.get(ApiConstants.sas4WdExpiredCount).catchError((_) => Response(
            requestOptions: RequestOptions(), data: {'data': 0})),
        _sas4Dio.get(ApiConstants.sas4WdOnline).catchError((_) => Response(
            requestOptions: RequestOptions(), data: {'data': 0})),
        _sas4Dio.get(ApiConstants.sas4WdBalance).catchError((_) => Response(
            requestOptions: RequestOptions(), data: {'data': '0'})),
        _sas4Dio.get(ApiConstants.sas4WdRewardPoints).catchError((_) => Response(
            requestOptions: RequestOptions(), data: {'data': '0'})),
      ]);

      final total = _parseWidgetInt(widgetResults[0].data);
      final active = _parseWidgetInt(widgetResults[1].data);
      final expired = _parseWidgetInt(widgetResults[2].data);
      final online = _parseWidgetInt(widgetResults[3].data);
      final balance = _parseWidgetStr(widgetResults[4].data);
      final points = _parseWidgetStr(widgetResults[5].data);

      dev.log(
        'Widgets: total=$total active=$active expired=$expired online=$online balance=$balance points=$points',
        name: 'DASH',
      );

      // 2) Backend: subscribers with phones (for debt + near-expiry alerts)
      int debtors = 0;
      double totalDebt = 0;
      int nearExpiry = 0, expiredToday = 0;
      List<Map<String, dynamic>> nearExpiryList = [];
      List<Map<String, dynamic>> expiredTodayList = [];

      try {
        final subsResponse = await backendDio.get(
          '${ApiConstants.subscribersWithPhones}?adminId=$adminId',
        );

        if (subsResponse.data['success'] == true) {
          final data = subsResponse.data['data'] as List? ?? [];
          for (final sub in data) {
            final days = sub['remaining_days'];
            final daysInt =
                days is int ? days : int.tryParse(days?.toString() ?? '');

            if (daysInt != null && daysInt >= 0 && daysInt <= 3) {
              nearExpiry++;
              nearExpiryList.add(Map<String, dynamic>.from(sub));
            }
            if (daysInt != null && daysInt < 0 && daysInt >= -1) {
              expiredToday++;
              expiredTodayList.add(Map<String, dynamic>.from(sub));
            }

            final notes = sub['notes']?.toString() ?? '0';
            final debtField = sub['debt'];
            final hasDebtFlag = sub['hasDebt'] == true;

            double debtAmount = 0;
            if (debtField is num && debtField != 0) {
              debtAmount = debtField.toDouble().abs();
            } else {
              final notesVal = double.tryParse(notes) ?? 0;
              if (notesVal < 0) debtAmount = notesVal.abs();
            }

            if (debtAmount > 0 || hasDebtFlag) {
              debtors++;
              totalDebt += debtAmount;
            }
          }
        }
      } catch (e) {
        dev.log('Backend subscribers error: $e', name: 'DASH');
      }

      // 3) Daily activations from rad backend
      int todayAct = 0, todayExt = 0;
      List<Map<String, dynamic>> activities = [];
      try {
        final actResponse = await backendDio.get(
          '${ApiConstants.dailyActivations}?admin_id=$adminId',
        );
        if (actResponse.data['success'] == true) {
          final counts = actResponse.data['counts'] ?? {};
          todayAct = counts['activations'] ?? counts['activate'] ?? 0;
          todayExt = counts['extensions'] ?? counts['extend'] ?? 0;
          final actData = actResponse.data['data'] as List? ?? [];
          activities =
              actData.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}

      // Fetch actual offline count via SAS4 encrypted call (same as React Dashboard)
      int offline = active - online;
      try {
        final offlinePayload = EncryptionService.encrypt({
          'page': 1,
          'count': 1,
          'sortBy': 'username',
          'direction': 'asc',
          'search': '',
          'status': 1,
          'connection': 1,
          'profile_id': -1,
          'parent_id': -1,
          'sub_users': 1,
          'mac': '',
          'columns': ['idx'],
        });
        final offlineResp = await _sas4Dio.post(
          ApiConstants.sas4ListUsers,
          data: {'payload': offlinePayload},
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );
        dynamic offlineParsed = offlineResp.data;
        if (offlineParsed is String) {
          offlineParsed = EncryptionService.decrypt(offlineParsed);
        }
        if (offlineParsed is Map) {
          final tc = offlineParsed['totalCount'] ??
              offlineParsed['total'] ??
              offlineParsed['count'];
          if (tc != null) {
            offline = tc is int ? tc : (int.tryParse(tc.toString()) ?? offline);
          }
        }
      } catch (e) {
        dev.log('Offline count fetch error: $e', name: 'DASH');
      }
      if (offline < 0) offline = 0;

      state = state.copyWith(
        totalSubscribers: total,
        activeSubscribers: active,
        expiredSubscribers: expired,
        onlineCount: online,
        offlineCount: offline < 0 ? 0 : offline,
        managerBalance: balance,
        managerPoints: points,
        nearExpiryCount: nearExpiry,
        expiredTodayCount: expiredToday,
        debtors: debtors,
        totalDebt: totalDebt,
        todayActivations: todayAct,
        todayExtensions: todayExt,
        recentActivities: activities,
        nearExpiryList: nearExpiryList,
        expiredTodayList: expiredTodayList,
        isLoading: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'خطأ اتصال: ${e.type.name}',
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '$e');
    } finally {
      backendDio.close();
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier(ref.read(sas4DioProvider));
});
