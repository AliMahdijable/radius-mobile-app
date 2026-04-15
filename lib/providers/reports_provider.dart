import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../core/services/encryption_service.dart';

class ReportsState {
  final bool loading;
  final String? error;

  // Financial
  final Map<String, dynamic> kpis;
  final List<Map<String, dynamic>> perAdmin;
  final List<Map<String, dynamic>> recentLogs;

  // Daily activations
  final List<Map<String, dynamic>> dailyRecords;
  final Map<String, int> dailyCounts;

  // Activations history
  final List<Map<String, dynamic>> activations;

  // Sessions
  final List<Map<String, dynamic>> sessions;
  final int sessionsTotal;
  final int sessionsPage;

  // Account statement
  final List<Map<String, dynamic>> transactions;
  final Map<String, dynamic>? subscriberInfo;
  final Map<String, dynamic> statementSummary;

  const ReportsState({
    this.loading = false,
    this.error,
    this.kpis = const {},
    this.perAdmin = const [],
    this.recentLogs = const [],
    this.dailyRecords = const [],
    this.dailyCounts = const {},
    this.activations = const [],
    this.sessions = const [],
    this.sessionsTotal = 0,
    this.sessionsPage = 1,
    this.transactions = const [],
    this.subscriberInfo,
    this.statementSummary = const {},
  });

  ReportsState copyWith({
    bool? loading,
    String? error,
    Map<String, dynamic>? kpis,
    List<Map<String, dynamic>>? perAdmin,
    List<Map<String, dynamic>>? recentLogs,
    List<Map<String, dynamic>>? dailyRecords,
    Map<String, int>? dailyCounts,
    List<Map<String, dynamic>>? activations,
    List<Map<String, dynamic>>? sessions,
    int? sessionsTotal,
    int? sessionsPage,
    List<Map<String, dynamic>>? transactions,
    Map<String, dynamic>? subscriberInfo,
    Map<String, dynamic>? statementSummary,
  }) {
    return ReportsState(
      loading: loading ?? this.loading,
      error: error,
      kpis: kpis ?? this.kpis,
      perAdmin: perAdmin ?? this.perAdmin,
      recentLogs: recentLogs ?? this.recentLogs,
      dailyRecords: dailyRecords ?? this.dailyRecords,
      dailyCounts: dailyCounts ?? this.dailyCounts,
      activations: activations ?? this.activations,
      sessions: sessions ?? this.sessions,
      sessionsTotal: sessionsTotal ?? this.sessionsTotal,
      sessionsPage: sessionsPage ?? this.sessionsPage,
      transactions: transactions ?? this.transactions,
      subscriberInfo: subscriberInfo ?? this.subscriberInfo,
      statementSummary: statementSummary ?? this.statementSummary,
    );
  }
}

class ReportsNotifier extends StateNotifier<ReportsState> {
  final Dio _dio;
  final Dio _sas4Dio;
  final StorageService _storage;

  ReportsNotifier(this._dio, this._sas4Dio, this._storage)
      : super(const ReportsState());

  Future<String?> _getAdminId() => _storage.getAdminId();

  // ── Financial Report ──────────────────────────────────────────────
  Future<void> fetchFinancialReport(String dateFrom, String dateTo) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _getAdminId();
      final params = <String, dynamic>{
        'date_from': '$dateFrom 00:00:00',
        'date_to': '$dateTo 23:59:59',
        'limit_logs': '500',
      };
      if (adminId != null) params['user_ids'] = adminId;

      final res = await _dio.get(
        ApiConstants.financeReport,
        queryParameters: params,
      );

      if (res.data?['success'] == true && res.data?['data'] != null) {
        final data = res.data['data'];
        state = state.copyWith(
          loading: false,
          kpis: Map<String, dynamic>.from(data['kpis'] ?? {}),
          perAdmin: (data['perAdmin'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          recentLogs: (data['recentLogs'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      } else {
        state = state.copyWith(loading: false, error: 'فشل جلب التقارير المالية');
      }
    } catch (e) {
      dev.log('fetchFinancialReport error: $e', name: 'REPORTS');
      state = state.copyWith(loading: false, error: 'خطأ في جلب التقارير');
    }
  }

  // ── Daily Activations ─────────────────────────────────────────────
  Future<void> fetchDailyActivations() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _getAdminId();
      final params = <String, dynamic>{};
      if (adminId != null) params['admin_id'] = adminId;

      final res = await _dio.get(
        ApiConstants.dailyActivations,
        queryParameters: params,
      );

      if (res.data?['success'] == true) {
        final data = res.data['data'] as List? ?? [];
        final counts = res.data['counts'] as Map? ?? {};
        state = state.copyWith(
          loading: false,
          dailyRecords:
              data.map((e) => Map<String, dynamic>.from(e)).toList(),
          dailyCounts: {
            'total': _toInt(counts['total']) > 0
                ? _toInt(counts['total'])
                : data.length,
            'activate': _toInt(counts['activate']),
            'extend': _toInt(counts['extend']),
          },
        );
      } else {
        state = state.copyWith(loading: false, error: 'فشل جلب تفعيلات اليوم');
      }
    } catch (e) {
      dev.log('fetchDailyActivations error: $e', name: 'REPORTS');
      state = state.copyWith(loading: false, error: 'خطأ في جلب البيانات');
    }
  }

  // ── Activations Report ────────────────────────────────────────────
  Future<void> fetchActivationsReport(String dateFrom, String dateTo) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _getAdminId();
      final params = <String, dynamic>{
        'date_from': '$dateFrom 00:00:00',
        'date_to': '$dateTo 23:59:59',
        'limit': '1000',
      };
      if (adminId != null) params['user_ids'] = adminId;

      final res = await _dio.get(
        ApiConstants.activities,
        queryParameters: params,
      );

      if (res.data?['data'] is List) {
        final list = (res.data['data'] as List)
            .where((log) {
              final action = (log['action'] ?? '').toString();
              if (action.contains('verify-token')) return false;
              final type =
                  (log['action_type'] ?? '').toString().toUpperCase().trim();
              final desc =
                  (log['action_description'] ?? '').toString().toLowerCase();
              return type == 'SUBSCRIBER_ACTIVATE' ||
                  type == 'SUBSCRIBER_EXTEND' ||
                  (type == 'SUBSCRIBER_ADD' && desc.contains('تفعيل'));
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        state = state.copyWith(loading: false, activations: list);
      } else {
        state = state.copyWith(loading: false, activations: []);
      }
    } catch (e) {
      dev.log('fetchActivationsReport error: $e', name: 'REPORTS');
      state = state.copyWith(loading: false, error: 'خطأ في جلب التفعيلات');
    }
  }

  // ── Sessions (SAS4 encrypted) ─────────────────────────────────────
  Future<void> fetchSessions({
    int page = 1,
    int count = 50,
    String search = '',
    String sortBy = 'acctstarttime',
    String direction = 'desc',
    String? fromDate,
    String? toDate,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final payload = {
        'page': page,
        'count': count,
        'sortBy': sortBy,
        'direction': direction,
        'search': search,
        'columns': [
          'username',
          'acctstarttime',
          'acctstoptime',
          'framedipaddress',
          'nasipaddress',
          'callingstationid',
          'acctinputoctets',
          'acctoutputoctets',
          'calledstationid',
          'nasportid',
          'acctterminatecause',
        ],
        'framedipaddress': '',
        'username': search,
        'mac': '',
        'start_date': fromDate ?? '',
        'end_date': toDate ?? '',
      };

      final encrypted = EncryptionService.encrypt(payload);

      final res = await _sas4Dio.post(
        ApiConstants.sas4UserSessions,
        data: 'payload=$encrypted',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
      );

      dynamic resData = res.data;
      if (resData is String) {
        resData = EncryptionService.decrypt(resData);
      }

      if (resData is Map) {
        final rows = resData['data'] as List? ?? [];
        final total = _toInt(resData['total'] ?? resData['recordsTotal']);
        state = state.copyWith(
          loading: false,
          sessions:
              rows.map((e) => Map<String, dynamic>.from(e)).toList(),
          sessionsTotal: total,
          sessionsPage: page,
        );
      } else {
        state = state.copyWith(loading: false, sessions: [], sessionsTotal: 0);
      }
    } catch (e) {
      dev.log('fetchSessions error: $e', name: 'REPORTS');
      state = state.copyWith(loading: false, error: 'خطأ في جلب الجلسات');
    }
  }

  // ── Account Statement ─────────────────────────────────────────────
  Future<void> fetchAccountStatement({
    required String username,
    required String userId,
    required String dateFrom,
    required String dateTo,
    List<String>? actionTypes,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final params = <String, dynamic>{
        'username': username,
        'user_id': userId,
        'date_from': '$dateFrom 00:00:00',
        'date_to': '$dateTo 23:59:59',
      };
      if (actionTypes != null && actionTypes.isNotEmpty) {
        params['action_types'] = actionTypes.join(',');
      }

      final res = await _dio.get(
        ApiConstants.accountStatement,
        queryParameters: params,
      );

      if (res.data?['success'] == true && res.data?['data'] != null) {
        final data = res.data['data'];
        state = state.copyWith(
          loading: false,
          transactions: (data['transactions'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          subscriberInfo: data['subscriber'] != null
              ? Map<String, dynamic>.from(data['subscriber'])
              : null,
          statementSummary: Map<String, dynamic>.from(data['summary'] ?? {}),
        );
      } else {
        state = state.copyWith(loading: false, error: 'فشل جلب كشف الحساب');
      }
    } catch (e) {
      dev.log('fetchAccountStatement error: $e', name: 'REPORTS');
      state = state.copyWith(loading: false, error: 'خطأ في جلب كشف الحساب');
    }
  }

  // ── Search Subscribers (for account statement) ────────────────────
  Future<List<Map<String, dynamic>>> searchSubscribers(String query) async {
    if (query.length < 2) return [];
    try {
      final res = await _dio.get(
        ApiConstants.subscribersSearch,
        queryParameters: {'search': query, 'count': 20},
      );
      if (res.data?['data'] is List) {
        return (res.data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      dev.log('searchSubscribers error: $e', name: 'REPORTS');
    }
    return [];
  }

  void clearStatement() {
    state = state.copyWith(
      transactions: [],
      subscriberInfo: null,
      statementSummary: {},
    );
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

final reportsProvider =
    StateNotifierProvider<ReportsNotifier, ReportsState>((ref) {
  return ReportsNotifier(
    ref.read(backendDioProvider),
    ref.read(sas4DioProvider),
    ref.read(storageServiceProvider),
  );
});
