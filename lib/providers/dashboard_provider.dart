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
  final int expiredOverdueCount;
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
  final List<Map<String, dynamic>> expiredOverdueList;
  final bool isLoading;
  final bool hasLoaded;
  final bool offlineLoaded;
  final String? error;

  const DashboardState({
    this.totalSubscribers = 0,
    this.activeSubscribers = 0,
    this.expiredSubscribers = 0,
    this.nearExpiryCount = 0,
    this.expiredTodayCount = 0,
    this.expiredOverdueCount = 0,
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
    this.expiredOverdueList = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.offlineLoaded = false,
    this.error,
  });

  int get totalAlerts => nearExpiryCount + expiredTodayCount;

  DashboardState copyWith({
    int? totalSubscribers,
    int? activeSubscribers,
    int? expiredSubscribers,
    int? nearExpiryCount,
    int? expiredTodayCount,
    int? expiredOverdueCount,
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
    List<Map<String, dynamic>>? expiredOverdueList,
    bool? isLoading,
    bool? hasLoaded,
    bool? offlineLoaded,
    String? error,
  }) {
    return DashboardState(
      totalSubscribers: totalSubscribers ?? this.totalSubscribers,
      activeSubscribers: activeSubscribers ?? this.activeSubscribers,
      expiredSubscribers: expiredSubscribers ?? this.expiredSubscribers,
      nearExpiryCount: nearExpiryCount ?? this.nearExpiryCount,
      expiredTodayCount: expiredTodayCount ?? this.expiredTodayCount,
      expiredOverdueCount: expiredOverdueCount ?? this.expiredOverdueCount,
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
      expiredOverdueList: expiredOverdueList ?? this.expiredOverdueList,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      offlineLoaded: offlineLoaded ?? this.offlineLoaded,
      error: error,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Dio _sas4Dio;
  final Dio _backendDio;

  DashboardNotifier(this._sas4Dio, this._backendDio)
      : super(const DashboardState());

  void updateOfflineCount(int count) {
    state = state.copyWith(offlineCount: count, offlineLoaded: true);
  }

  Future<void> refreshCountsOnly() async {
    try {
      final results = await Future.wait([
        _sas4Dio.get(ApiConstants.sas4WdUsersCount).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdActiveCount).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdExpiredCount).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdOnline).catchError((_) => null),
      ]);
      final total = _parseWidgetIntOrNull(results[0]) ?? state.totalSubscribers;
      final active =
          _parseWidgetIntOrNull(results[1]) ?? state.activeSubscribers;
      final expired =
          _parseWidgetIntOrNull(results[2]) ?? state.expiredSubscribers;
      final online = _parseWidgetIntOrNull(results[3]) ?? state.onlineCount;

      if (total == state.totalSubscribers &&
          active == state.activeSubscribers &&
          expired == state.expiredSubscribers &&
          online == state.onlineCount) {
        return;
      }

      state = state.copyWith(
        totalSubscribers: total,
        activeSubscribers: active,
        expiredSubscribers: expired,
        onlineCount: online,
      );
    } catch (_) {}
  }

  static int? _remainingDaysInt(dynamic days) {
    if (days == null) return null;
    if (days is int) return days;
    if (days is double) return days.round();
    return int.tryParse(days.toString().trim());
  }

  static DateTime? _parseExpDate(String? expiration) {
    if (expiration == null || expiration.isEmpty) return null;
    final s = expiration.trim();
    if (s.contains('T') || s.contains('+')) return DateTime.tryParse(s);
    return DateTime.tryParse('${s.replaceAll(' ', 'T')}+03:00');
  }

  static bool _isExpiredTodayExact(String? expiration) {
    final expDate = _parseExpDate(expiration);
    if (expDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final expDay = DateTime(expDate.year, expDate.month, expDate.day);
    return expDay == today && expDate.isBefore(now);
  }

  static bool _isNearExpiryExact(String? expiration) {
    final expDate = _parseExpDate(expiration);
    if (expDate == null) return false;
    final now = DateTime.now();
    if (expDate.isBefore(now)) return false;
    final diff = expDate.difference(now);
    return diff.inDays <= 3;
  }

  int? _parseWidgetIntOrNull(dynamic responseOrData) {
    final data = responseOrData is Response ? responseOrData.data : responseOrData;
    if (data == null) return null;
    if (data is Map && data.containsKey('data')) {
      return int.tryParse(data['data'].toString());
    }
    if (data is int) return data;
    if (data is double) return data.toInt();
    return int.tryParse(data.toString());
  }

  String? _parseWidgetStrOrNull(dynamic responseOrData) {
    final data = responseOrData is Response ? responseOrData.data : responseOrData;
    if (data == null) return null;
    if (data is Map && data.containsKey('data')) {
      final value = data['data']?.toString();
      return value == null || value.isEmpty ? null : value;
    }
    final value = data.toString();
    return value.isEmpty ? null : value;
  }

  Future<void> loadDashboard({
    required String adminId,
    required String token,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // تشغيل كل الطلبات بالتوازي لتسريع التحميل
      final offlinePayload = EncryptionService.encrypt({
        'page': 1, 'count': 1, 'sortBy': 'username', 'direction': 'asc',
        'search': '', 'status': 1, 'connection': 0, 'profile_id': -1,
        'parent_id': -1, 'sub_users': 1, 'mac': '', 'columns': ['idx'],
      });
      final expiredPayload = EncryptionService.encrypt({
        'page': 1, 'count': 1, 'sortBy': 'username', 'direction': 'asc',
        'search': '', 'status': 2, 'connection': -1, 'profile_id': -1,
        'parent_id': -1, 'group_id': -1, 'site_id': -1, 'sub_users': 1,
        'mac': '', 'columns': ['idx'],
      });

      final allResults = await Future.wait([
        // [0-5] SAS4 Widgets
        _sas4Dio.get(ApiConstants.sas4WdUsersCount).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdActiveCount).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdExpiredCount).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdOnline).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdBalance).catchError((_) => null),
        _sas4Dio.get(ApiConstants.sas4WdRewardPoints).catchError((_) => null),
        // [6] Backend subscribers
        _backendDio
            .get('${ApiConstants.subscribersWithPhones}?adminId=$adminId')
            .catchError((_) => null),
        // [7] Backend daily activations
        _backendDio
            .get('${ApiConstants.dailyActivations}?admin_id=$adminId')
            .catchError((_) => null),
        // [8-9] SAS4 offline + expired counts
        _sas4Dio
            .post(
              ApiConstants.sas4ListUsers,
              data: {'payload': offlinePayload},
              options: Options(contentType: 'application/x-www-form-urlencoded'),
            )
            .catchError((_) => null),
        _sas4Dio
            .post(
              ApiConstants.sas4ListUsers,
              data: {'payload': expiredPayload},
              options: Options(contentType: 'application/x-www-form-urlencoded'),
            )
            .catchError((_) => null),
      ]);

      final hadAnyResult = allResults.any((result) => result != null);
      if (!hadAnyResult) {
        state = state.copyWith(
          isLoading: false,
          hasLoaded: state.hasLoaded,
          error: 'تعذر تحديث البيانات حالياً',
        );
        return;
      }

      final total = _parseWidgetIntOrNull(allResults[0]) ?? state.totalSubscribers;
      final active =
          _parseWidgetIntOrNull(allResults[1]) ?? state.activeSubscribers;
      final expired =
          _parseWidgetIntOrNull(allResults[2]) ?? state.expiredSubscribers;
      final online = _parseWidgetIntOrNull(allResults[3]) ?? state.onlineCount;
      final balance =
          _parseWidgetStrOrNull(allResults[4]) ?? state.managerBalance;
      final points =
          _parseWidgetStrOrNull(allResults[5]) ?? state.managerPoints;

      dev.log('Widgets: total=$total active=$active expired=$expired online=$online', name: 'DASH');

      // معالجة بيانات المشتركين
      int debtors = state.debtors;
      double totalDebt = state.totalDebt;
      int nearExpiry = state.nearExpiryCount;
      int expiredToday = state.expiredTodayCount;
      int expiredOverdue = state.expiredOverdueCount;
      List<Map<String, dynamic>> nearExpiryList = state.nearExpiryList;
      List<Map<String, dynamic>> expiredTodayList = state.expiredTodayList;
      List<Map<String, dynamic>> expiredOverdueList = state.expiredOverdueList;

      final subsResponse = allResults[6];
      final subsData = subsResponse is Response ? subsResponse.data : null;
      if (subsData is Map && subsData['success'] == true) {
        debtors = 0;
        totalDebt = 0;
        nearExpiry = 0;
        expiredToday = 0;
        expiredOverdue = 0;
        nearExpiryList = [];
        expiredTodayList = [];
        expiredOverdueList = [];
        final data = subsData['data'] as List? ?? [];
        for (final sub in data) {
          final expStr = sub['expiration']?.toString();
          if (_isNearExpiryExact(expStr)) {
            nearExpiry++;
            nearExpiryList.add(Map<String, dynamic>.from(sub));
          }
          if (_isExpiredTodayExact(expStr)) {
            expiredToday++;
            expiredTodayList.add(Map<String, dynamic>.from(sub));
          }
          final daysInt = _remainingDaysInt(sub['remaining_days']);
          final expDate = _parseExpDate(expStr);
          final isOldExpired = expDate != null
              ? expDate.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
              : (daysInt != null && daysInt < 0);
          if (isOldExpired) {
            expiredOverdue++;
            expiredOverdueList.add(Map<String, dynamic>.from(sub));
          }
          final notesRaw = (sub['notes'] ?? sub['comments'])?.toString() ?? '';
          var notesVal = double.tryParse(notesRaw.replaceAll(',', '').trim()) ?? 0;
          if (notesVal == 0 && (sub['hasDebt'] == true || sub['hasDebt'] == 1)) {
            final d = sub['debt'];
            if (d is num && d != 0) notesVal = -d.abs().toDouble();
          }
          if (notesVal < 0) {
            debtors++;
            totalDebt += notesVal.abs();
          }
        }
      }

      // معالجة التفعيلات اليومية
      int todayAct = state.todayActivations, todayExt = state.todayExtensions;
      List<Map<String, dynamic>> activities = state.recentActivities;
      final actResponse = allResults[7];
      final actData = actResponse is Response ? actResponse.data : null;
      if (actData is Map && actData['success'] == true) {
        final counts = actData['counts'] ?? {};
        todayAct = counts['activations'] ?? counts['activate'] ?? 0;
        todayExt = counts['extensions'] ?? counts['extend'] ?? 0;
        final actList = actData['data'] as List? ?? [];
        activities = actList.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      // معالجة عدد المنتهين فقط — الأوفلاين يُحدَّث من المشتركين عبر updateOfflineCount
      int expiredActual = expired;
      dynamic expParsed = allResults[9] is Response ? (allResults[9] as Response).data : null;
      if (expParsed is String) expParsed = EncryptionService.decrypt(expParsed);
      if (expParsed is Map) {
        final tc = expParsed['totalCount'] ?? expParsed['total'] ?? expParsed['count'];
        if (tc != null) expiredActual = tc is int ? tc : (int.tryParse(tc.toString()) ?? expired);
      }

      expiredOverdueList.sort((a, b) {
        final da = _remainingDaysInt(a['remaining_days']) ?? 0;
        final db = _remainingDaysInt(b['remaining_days']) ?? 0;
        return da.compareTo(db);
      });

      state = state.copyWith(
        totalSubscribers: total,
        activeSubscribers: active,
        expiredSubscribers: expiredActual,
        onlineCount: online,
        managerBalance: balance,
        managerPoints: points,
        nearExpiryCount: nearExpiry,
        expiredTodayCount: expiredToday,
        expiredOverdueCount: expiredOverdue,
        debtors: debtors,
        totalDebt: totalDebt,
        todayActivations: todayAct,
        todayExtensions: todayExt,
        recentActivities: activities,
        nearExpiryList: nearExpiryList,
        expiredTodayList: expiredTodayList,
        expiredOverdueList: expiredOverdueList,
        isLoading: false,
        hasLoaded: true,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        hasLoaded: state.hasLoaded,
        error: 'خطأ اتصال: ${e.type.name}',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        hasLoaded: state.hasLoaded,
        error: '$e',
      );
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier(
    ref.read(sas4DioProvider),
    ref.read(backendDioProvider),
  );
});
