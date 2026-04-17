import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../core/services/encryption_service.dart';

class ManagerOption {
  final String id;
  final String name;
  const ManagerOption({required this.id, required this.name});
}

class ReportsState {
  final bool loading;
  final String? error;

  // Managers
  final List<ManagerOption> managers;

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
    this.managers = const [],
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
    List<ManagerOption>? managers,
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
      managers: managers ?? this.managers,
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

  // ── Managers Tree ─────────────────────────────────────────────────
  Future<void> fetchManagers() async {
    if (state.managers.isNotEmpty) return;
    try {
      final res = await _sas4Dio.get(ApiConstants.sas4ManagerTree);
      final data = res.data;
      final flat = <ManagerOption>[];
      void flatten(dynamic node) {
        if (node is Map) {
          final id = (node['id'] ?? node['idx'] ?? '').toString();
          final name = (node['username'] ?? node['name'] ?? '').toString();
          if (id.isNotEmpty && name.isNotEmpty) {
            flat.add(ManagerOption(id: id, name: name));
          }
          if (node['children'] is List) {
            for (final c in node['children']) {
              flatten(c);
            }
          }
        } else if (node is List) {
          for (final c in node) {
            flatten(c);
          }
        }
      }
      if (data is Map && data['data'] != null) {
        flatten(data['data']);
      } else {
        flatten(data);
      }
      state = state.copyWith(managers: flat);
    } catch (e) {
      dev.log('fetchManagers error: $e', name: 'REPORTS');
    }
  }

  // ── Financial Report ──────────────────────────────────────────────
  Future<void> fetchFinancialReport(String dateFrom, String dateTo, {
    String? managerId,
    List<String>? actionTypes,
    String? userManager,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _getAdminId();
      final params = <String, dynamic>{
        'date_from': '$dateFrom 00:00:00',
        'date_to': '$dateTo 23:59:59',
        'limit_logs': '500',
      };
      if (managerId != null && managerId != 'all') {
        params['user_ids'] = managerId;
      } else if (adminId != null) {
        final allIds = [adminId, ...state.managers.map((m) => m.id)];
        params['user_ids'] = allIds.toSet().join(',');
      }
      if (actionTypes != null && actionTypes.isNotEmpty) {
        params['action_types'] = actionTypes.join(',');
      }
      if (userManager != null && userManager.isNotEmpty) {
        params['user_manager'] = userManager;
      }

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
  Future<void> fetchDailyActivations({String? managerId}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _getAdminId();
      final params = <String, dynamic>{};
      if (managerId != null && managerId != 'all') {
        params['admin_id'] = managerId;
      } else if (adminId != null) {
        params['admin_id'] = adminId;
      }

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
  Future<void> fetchActivationsReport(String dateFrom, String dateTo, {
    String? managerId,
  }) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final adminId = await _getAdminId();
      final params = <String, dynamic>{
        'date_from': '$dateFrom 00:00:00',
        'date_to': '$dateTo 23:59:59',
        'limit': '1000',
      };
      if (managerId != null && managerId != 'all') {
        params['user_ids'] = managerId;
      } else if (adminId != null) {
        final allIds = [adminId, ...state.managers.map((m) => m.id)];
        params['user_ids'] = allIds.toSet().join(',');
      }

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
    String username = '',
    String ipAddress = '',
    String mac = '',
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
        'framedipaddress': ipAddress,
        'username': username,
        'mac': mac,
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

      final parsed = _parseSessionsResponse(resData, page);
      state = state.copyWith(
        loading: false,
        sessions: parsed['sessions'] as List<Map<String, dynamic>>,
        sessionsTotal: parsed['total'] as int,
        sessionsPage: page,
      );
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

  Map<String, dynamic> _parseSessionsResponse(dynamic data, int page) {
    List rawRows = const [];
    var total = 0;

    if (data is Map && data['data'] is List) {
      rawRows = data['data'] as List;
      total = _toInt(data['total'] ?? data['recordsTotal']);
    } else if (data is Map && data['sessions'] is List) {
      rawRows = data['sessions'] as List;
      total = _toInt(data['total'] ?? data['totalCount']);
    } else if (data is Map && data['list'] is List) {
      rawRows = data['list'] as List;
      total = _toInt(data['total'] ?? data['totalCount']);
    } else if (data is List) {
      rawRows = data;
      total = data.length;
    }

    final sessions = <Map<String, dynamic>>[];
    for (var i = 0; i < rawRows.length; i++) {
      final row = rawRows[i];
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      map['id'] ??=
          map['radacctid'] ?? map['acctsessionid'] ?? '$page-$i';
      sessions.add(map);
    }

    return {
      'sessions': sessions,
      'total': total > 0 ? total : sessions.length,
    };
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
