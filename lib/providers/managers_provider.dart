import 'dart:developer' as dev;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/encryption_service.dart';
import '../core/services/storage_service.dart';
import '../models/manager_model.dart';

class ManagersState {
  final bool loading;
  final List<ManagerModel> managers;
  final int currentPage;
  final int rowsPerPage;
  final int totalCount;
  final String search;
  final String sortBy;
  final String direction;
  final String? error;

  const ManagersState({
    this.loading = false,
    this.managers = const [],
    this.currentPage = 1,
    this.rowsPerPage = 10,
    this.totalCount = 0,
    this.search = '',
    this.sortBy = 'username',
    this.direction = 'asc',
    this.error,
  });

  ManagersState copyWith({
    bool? loading,
    List<ManagerModel>? managers,
    int? currentPage,
    int? rowsPerPage,
    int? totalCount,
    String? search,
    String? sortBy,
    String? direction,
    String? error,
    bool clearError = false,
  }) {
    return ManagersState(
      loading: loading ?? this.loading,
      managers: managers ?? this.managers,
      currentPage: currentPage ?? this.currentPage,
      rowsPerPage: rowsPerPage ?? this.rowsPerPage,
      totalCount: totalCount ?? this.totalCount,
      search: search ?? this.search,
      sortBy: sortBy ?? this.sortBy,
      direction: direction ?? this.direction,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ManagersNotifier extends StateNotifier<ManagersState> {
  final Dio _sas4Dio;
  final Dio _backendDio;
  final StorageService _storage;

  ManagersNotifier(this._sas4Dio, this._backendDio, this._storage)
      : super(const ManagersState());

  Future<void> loadManagers({
    int? page,
    int? rowsPerPage,
    String? search,
    String? sortBy,
    String? direction,
  }) async {
    final nextPage = page ?? state.currentPage;
    final nextRowsPerPage = rowsPerPage ?? state.rowsPerPage;
    final nextSearch = search ?? state.search;
    final nextSortBy = sortBy ?? state.sortBy;
    final nextDirection = direction ?? state.direction;

    state = state.copyWith(
      loading: true,
      currentPage: nextPage,
      rowsPerPage: nextRowsPerPage,
      search: nextSearch,
      sortBy: nextSortBy,
      direction: nextDirection,
      clearError: true,
    );

    try {
      final payload = EncryptionService.encrypt({
        'page': nextPage,
        'count': nextRowsPerPage,
        'sortBy': nextSortBy,
        'direction': nextDirection,
        'search': nextSearch,
        'columns': [
          'username',
          'firstname',
          'lastname',
          'balance',
          'balance',
          'name',
          'username',
          'users_count',
          'acl_group_details',
        ],
      });

      final response = await _sas4Dio.post(
        ApiConstants.sas4Managers,
        data: {'payload': payload},
      );

      final body = response.data;
      final data = body is Map ? body['data'] : null;
      final items = data is List
          ? data
              .whereType<Map>()
              .map((e) => ManagerModel.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <ManagerModel>[];
      final enrichedItems = await _enrichManagers(items);

      final totalCount = body is Map
          ? _toInt(body['totalCount'] ?? body['total'] ?? enrichedItems.length)
          : enrichedItems.length;

      state = state.copyWith(
        loading: false,
        managers: enrichedItems,
        totalCount: totalCount,
      );
    } catch (e) {
      dev.log('loadManagers error: $e', name: 'MANAGERS');
      state = state.copyWith(
        loading: false,
        managers: const [],
        totalCount: 0,
        error: 'فشل جلب المدراء',
      );
    }
  }

  Future<List<ManagerAclGroup>> fetchAclGroups() async {
    try {
      final response = await _sas4Dio.get('/index/acl');
      final data = response.data is Map ? response.data['data'] : null;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => ManagerAclGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      dev.log('fetchAclGroups error: $e', name: 'MANAGERS');
      return const [];
    }
  }

  Future<List<ManagerModel>> fetchParentManagers() async {
    try {
      final response = await _sas4Dio.get(ApiConstants.sas4ManagerTree);
      final data = response.data is Map ? (response.data['data'] ?? response.data) : response.data;
      final nodes = data is List ? data : [data];
      final flattened = <ManagerModel>[];
      _flattenManagerTree(nodes, flattened);
      return flattened;
    } catch (e) {
      dev.log('fetchParentManagers error: $e', name: 'MANAGERS');
      return const [];
    }
  }

  Future<ManagerModel?> fetchManagerDetails(int managerId) async {
    try {
      final response = await _sas4Dio.get('/manager/$managerId');
      final data = response.data is Map ? response.data['data'] : null;
      if (data is! Map) return null;
      return ManagerModel.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      dev.log('fetchManagerDetails error: $e', name: 'MANAGERS');
      return null;
    }
  }

  Future<ManagerDebtInfo?> fetchDebtInfo(int managerId) async {
    try {
      final response = await _sas4Dio.get('/manager/debt/$managerId');
      return ManagerDebtInfo.fromJson(Map<String, dynamic>.from(response.data));
    } catch (e) {
      dev.log('fetchDebtInfo error: $e', name: 'MANAGERS');
      return null;
    }
  }

  Future<List<ManagerModel>> _enrichManagers(List<ManagerModel> managers) async {
    if (managers.isEmpty) return managers;

    final enriched = await Future.wait(
      managers.map((manager) async {
        final results = await Future.wait<dynamic>([
          fetchDebtInfo(manager.id),
          fetchManagerDetails(manager.id),
        ]);
        final debtInfo = results[0] as ManagerDebtInfo?;
        final details = results[1] as ManagerModel?;

        return manager.copyWith(
          totalDebt: debtInfo?.totalDebt.abs() ?? manager.totalDebt,
          debtForMe: debtInfo?.debtForMe.abs() ?? manager.debtForMe,
          rewardPoints: details?.rewardPoints ?? manager.rewardPoints,
          mobile: details?.mobile.isNotEmpty == true
              ? details!.mobile
              : manager.mobile,
          company: details?.company.isNotEmpty == true
              ? details!.company
              : manager.company,
        );
      }),
    );

    return enriched;
  }

  Future<bool> createManager({
    required String username,
    required String password,
    required int aclGroupId,
    int? parentId,
    required String firstname,
    required String lastname,
    String? company,
    String? email,
    String? phone,
    String? city,
    String? address,
    String? notes,
    bool enabled = true,
  }) async {
    try {
      final payload = EncryptionService.encrypt({
        'username': username.trim(),
        'password': password,
        'confirm_password': password,
        'acl_group_id': aclGroupId,
        'parent_id': parentId,
        'enabled': enabled ? 1 : 0,
        'firstname': firstname.trim(),
        'lastname': lastname.trim(),
        'company': _nullable(company),
        'email': _nullable(email),
        'phone': _nullable(phone),
        'city': _nullable(city),
        'address': _nullable(address),
        'notes': _nullable(notes),
        'subscriber_prefix': null,
        'subscriber_suffix': null,
        'max_users': 0,
        'group_id': null,
        'site_id': null,
        'debt_limit': '0.000',
        'discount_rate': '0.00',
        'mikrotik_addresslist': null,
        'allowed_ppp_services': null,
        'allowed_nases': [],
        'requires_2fa': 0,
        'ignore_captcha': 0,
        'admin_notes': null,
        'force_change_password': 0,
        'limit_delete': 0,
        'limit_delete_count': 0,
        'limit_rename': 0,
        'limit_rename_count': 0,
        'limit_profile_change': 0,
        'limit_profile_change_count': 0,
        'limit_mac_change': 0,
        'limit_mac_change_count': 0,
      });

      final response = await _sas4Dio.post(
        '/manager',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final ok = response.data is Map
          ? response.data['status'] == 200 || response.statusCode == 200
          : response.statusCode == 200;

      if (ok) {
        await _logManagerActivity(
          activityType: 'managers',
          actionType: 'MANAGER_ADD',
          action: 'manager_add',
          description:
              'تم إضافة مدير جديد: $username - الاسم: ${firstname.trim()} ${lastname.trim()}',
          targetId: response.data is Map
              ? _toInt(response.data['id'] ?? response.data['data']?['id'])
              : 0,
          targetName: username,
          metadata: {
            'manager_action': 'create_manager',
            'firstname': firstname.trim(),
            'lastname': lastname.trim(),
            'acl_group_id': aclGroupId,
            'parent_id': parentId,
            'enabled': enabled,
          },
        );
      }

      return ok;
    } catch (e) {
      dev.log('createManager error: $e', name: 'MANAGERS');
      return false;
    }
  }

  Future<bool> updateManager({
    required int managerId,
    required ManagerModel original,
    required String username,
    required String firstname,
    required String lastname,
    required int aclId,
    required bool isActive,
    String? password,
    String? email,
    String? mobile,
    String? company,
    int? parentId,
  }) async {
    try {
      final mainPayload = EncryptionService.encrypt({
        'enabled': isActive ? 1 : 0,
        'password': (password != null && password.trim().isNotEmpty)
            ? password.trim()
            : null,
        'confirm_password': (password != null && password.trim().isNotEmpty)
            ? password.trim()
            : null,
        'acl_group_id': aclId,
        'parent_id': parentId,
        'firstname': firstname.trim(),
        'lastname': lastname.trim(),
        'company': _nullable(company),
        'email': _nullable(email),
        'phone': _nullable(mobile),
        'city': null,
        'address': null,
        'notes': null,
        'subscriber_prefix': null,
        'subscriber_suffix': null,
        'max_users': 0,
        'group_id': null,
        'site_id': null,
        'debt_limit': '0.000',
        'discount_rate': '0.00',
        'mikrotik_addresslist': null,
        'allowed_ppp_services': null,
        'allowed_nases': [],
        'requires_2fa': 0,
        'ignore_captcha': 0,
        'admin_notes': null,
        'force_change_password': 0,
        'limit_delete': 0,
        'limit_delete_count': 0,
        'limit_rename': 0,
        'limit_rename_count': 0,
        'limit_profile_change': 0,
        'limit_profile_change_count': 0,
        'limit_mac_change': 0,
        'limit_mac_change_count': 0,
      });

      await _sas4Dio.put(
        '/manager/$managerId',
        data: {'payload': mainPayload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final trimmedUsername = username.trim();
      if (trimmedUsername.isNotEmpty && trimmedUsername != original.username) {
        final usernamePayload = EncryptionService.encrypt({
          'username': trimmedUsername,
        });
        await _sas4Dio.put(
          '/manager/$managerId',
          data: {'payload': usernamePayload},
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );
      }

      await _logManagerActivity(
        activityType: 'managers',
        actionType: 'MANAGER_EDIT',
        action: 'manager_edit',
        description: 'تم تعديل بيانات المدير: ${original.username}',
        targetId: managerId,
        targetName: trimmedUsername.isNotEmpty ? trimmedUsername : original.username,
        metadata: {
          'manager_action': 'edit_manager',
          'manager_id': managerId,
          'firstname': firstname.trim(),
          'lastname': lastname.trim(),
          'username': trimmedUsername.isNotEmpty ? trimmedUsername : original.username,
          'acl_group_id': aclId,
          'enabled': isActive,
          'has_password_change': password != null && password.trim().isNotEmpty,
        },
      );

      return true;
    } catch (e) {
      dev.log('updateManager error: $e', name: 'MANAGERS');
      return false;
    }
  }

  Future<bool> addBalance({
    required ManagerModel manager,
    required double amount,
    String? notes,
    bool isLoan = false,
  }) async {
    try {
      final payload = EncryptionService.encrypt({
        'manager_id': manager.id,
        'my_balance': 0,
        'manager_username': manager.username,
        'amount': amount,
        'comment': notes ?? '',
        'transaction_id': _transactionId(),
        'is_loan': isLoan,
        'balance': manager.balance,
      });

      await _sas4Dio.post(
        '/manager/deposit',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      await _logManagerActivity(
        activityType: 'managers',
        actionType: 'BALANCE_ADD',
        action: 'manager_balance_add',
        description:
            'تم إضافة ${amount.toStringAsFixed(0)} IQD للمدير: ${manager.username}${notes != null && notes.trim().isNotEmpty ? ' - ${notes.trim()}' : ''}',
        targetId: manager.id,
        targetName: manager.username,
        metadata: {
          'manager_action': isLoan ? 'loan_deposit' : 'cash_deposit',
          'amount': amount,
          'payment_type': isLoan ? 'loan' : 'cash',
          'previous_balance': manager.balance,
          'new_balance': manager.balance + amount,
          'previous_debt': manager.totalDebt,
          'new_debt': isLoan ? manager.totalDebt + amount : manager.totalDebt,
          'notes': notes?.trim(),
        },
      );
      return true;
    } catch (e) {
      dev.log('addBalance error: $e', name: 'MANAGERS');
      return false;
    }
  }

  Future<bool> withdrawBalance({
    required ManagerModel manager,
    required double amount,
    String? notes,
  }) async {
    try {
      final payload = EncryptionService.encrypt({
        'manager_id': manager.id,
        'my_balance': 0,
        'manager_username': manager.username,
        'amount': amount,
        'comment': notes ?? '',
        'transaction_id': _transactionId(),
        'is_loan': false,
        'balance': manager.balance,
      });

      await _sas4Dio.post(
        '/manager/withdraw',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      await _logManagerActivity(
        activityType: 'managers',
        actionType: 'BALANCE_DEDUCT',
        action: 'manager_balance_deduct',
        description:
            'تم سحب ${amount.toStringAsFixed(0)} IQD من المدير: ${manager.username}${notes != null && notes.trim().isNotEmpty ? ' - ${notes.trim()}' : ''}',
        targetId: manager.id,
        targetName: manager.username,
        metadata: {
          'manager_action': 'withdraw_balance',
          'amount': amount,
          'previous_balance': manager.balance,
          'new_balance': manager.balance - amount,
          'notes': notes?.trim(),
        },
      );
      return true;
    } catch (e) {
      dev.log('withdrawBalance error: $e', name: 'MANAGERS');
      return false;
    }
  }

  Future<bool> payDebt({
    required ManagerModel manager,
    required double amount,
    required double debtForMe,
    required double totalDebt,
    String? notes,
  }) async {
    try {
      final payload = EncryptionService.encrypt({
        'manager_id': manager.id,
        'manager_username': manager.username,
        'amount': amount,
        'comment': notes ?? '',
        'transaction_id': null,
        'is_loan': false,
        'debt_for_me': debtForMe,
        'debt': totalDebt,
      });

      await _sas4Dio.post(
        '/manager/payDebt',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      await _logManagerActivity(
        activityType: 'managers',
        actionType: 'DEBT_PAY',
        action: 'manager_debt_pay',
        description:
            'تم تسديد ${amount.toStringAsFixed(0)} IQD من دين المدير: ${manager.username}${notes != null && notes.trim().isNotEmpty ? ' - ${notes.trim()}' : ''}',
        targetId: manager.id,
        targetName: manager.username,
        metadata: {
          'manager_action': 'pay_debt',
          'amount': amount,
          'previous_balance': totalDebt,
          'new_balance': totalDebt - amount,
          'debt_for_me': debtForMe,
          'notes': notes?.trim(),
        },
      );
      return true;
    } catch (e) {
      dev.log('payDebt error: $e', name: 'MANAGERS');
      return false;
    }
  }

  Future<(bool success, String? message)> addPoints({
    required ManagerModel manager,
    required int points,
    String? notes,
  }) async {
    try {
      final payload = EncryptionService.encrypt({
        'manager_id': manager.id,
        'amount': points,
      });
      final formBody = Uri(queryParameters: {'payload': payload}).query;
      final token = await _storage.getToken();

      final response = await _sas4Dio.post(
        ApiConstants.sas4ManagerAddRewardPoints,
        data: formBody,
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            if (token != null) 'X-Auth-Token': token,
            if (token != null) 'x-auth-token': token,
            'Accept': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final body = response.data;
      final success = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300 &&
          (body is! Map ||
              body['status'] == null ||
              body['status'] == 200 ||
              body['success'] == true ||
              body['ok'] == true);

      if (!success) {
        final debugMessage =
            'addPoints rejected: status=${response.statusCode} data=$body';
        final message = _extractResponseMessage(body) ??
            'تعذر إضافة النقاط (HTTP ${response.statusCode ?? 'unknown'})';
        dev.log(debugMessage, name: 'MANAGERS');
        print('MANAGERS: $debugMessage');
        return (false, message);
      }

      await _logManagerActivity(
        activityType: 'managers',
        actionType: 'MANAGER_EDIT',
        action: 'manager_add_points',
        description:
            'تم إضافة $points نقطة للمدير: ${manager.username}${notes != null && notes.trim().isNotEmpty ? ' - ${notes.trim()}' : ''}',
        targetId: manager.id,
        targetName: manager.username,
        metadata: {
          'manager_action': 'add_points',
          'points': points,
          'notes': notes?.trim(),
        },
      );
      return (true, _extractResponseMessage(body));
    } catch (e) {
      if (e is DioException) {
        final debugMessage =
            'addPoints error: status=${e.response?.statusCode} type=${e.type.name} data=${e.response?.data}';
        final message = _extractResponseMessage(e.response?.data) ??
            e.message ??
            'تعذر إضافة النقاط (${e.type.name}${e.response?.statusCode != null ? ' / HTTP ${e.response?.statusCode}' : ''})';
        dev.log(debugMessage, name: 'MANAGERS');
        print('MANAGERS: $debugMessage');
        return (false, message);
      } else {
        dev.log('addPoints error: $e', name: 'MANAGERS');
        print('MANAGERS: addPoints error: $e');
        return (false, 'تعذر إضافة النقاط');
      }
    }
  }

  Future<(bool success, String? message)> sendManagerBalanceUpdateNotification({
    required ManagerModel manager,
    required double amount,
    required bool isLoan,
    required double previousCredit,
    required double previousDebt,
    String? notes,
  }) async {
    try {
      final response = await _backendDio.post(
        ApiConstants.fcmSendManagerBalanceUpdate,
        data: {
          'targetAdminId': manager.id.toString(),
          'amount': amount,
          'isLoan': isLoan,
          'previousCredit': previousCredit,
          'previousDebt': previousDebt,
          'notes': notes?.trim() ?? '',
          'managerUsername': manager.username,
        },
      );

      final body = response.data;
      final success = body is Map ? body['success'] == true : false;
      final message = _extractResponseMessage(body) ??
          (success ? 'تم إرسال الإشعار بنجاح' : 'تعذر إرسال الإشعار');

      return (success, message);
    } catch (e) {
      dev.log(
        'sendManagerBalanceUpdateNotification error: $e',
        name: 'MANAGERS',
      );
      if (e is DioException) {
        return (
          false,
          _extractResponseMessage(e.response?.data) ??
              e.message ??
              'تعذر إرسال إشعار التطبيق',
        );
      }
      return (false, 'تعذر إرسال إشعار التطبيق');
    }
  }

  Future<(bool success, String? message)> deleteManager(
      ManagerModel manager) async {
    try {
      final response = await _sas4Dio.delete('/manager/${manager.id}');
      final body = response.data;
      final success = body is Map
          ? body['status'] == 200 || response.statusCode == 200
          : response.statusCode == 200;
      final message = body is Map ? body['message']?.toString() : null;

      if (success) {
        await _logManagerActivity(
          activityType: 'managers',
          actionType: 'MANAGER_DELETE',
          action: 'manager_delete',
          description:
              'تم حذف المدير: ${manager.username} - ${manager.fullName}',
          targetId: manager.id,
          targetName: manager.username,
          metadata: {
            'manager_action': 'delete_manager',
            'manager_id': manager.id,
            'fullname': manager.fullName,
          },
        );
      }

      return (success, message);
    } catch (e) {
      dev.log('deleteManager error: $e', name: 'MANAGERS');
      if (e is DioException) {
        final message = e.response?.data is Map
            ? e.response?.data['message']?.toString()
            : null;
        return (false, message ?? 'تعذر حذف المدير');
      }
      return (false, 'تعذر حذف المدير');
    }
  }

  Future<void> _logManagerActivity({
    required String activityType,
    required String actionType,
    required String action,
    required String description,
    required int targetId,
    required String targetName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _backendDio.post(
        '/api/activities/log',
        data: {
          'activity_type': activityType,
          'action_type': actionType,
          'action': action,
          'description': description,
          'target_type': 'manager',
          'target_id': targetId > 0 ? targetId.toString() : null,
          'target_name': targetName,
          'metadata': metadata,
          'status': 'success',
          'adminId': await _storage.getAdminId(),
          'adminUsername': await _storage.getAdminUsername(),
        },
      );
    } catch (e) {
      dev.log('log manager activity error: $e', name: 'MANAGERS');
    }
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _transactionId() {
    final random = Random();
    return '${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  static String? _extractResponseMessage(dynamic body) {
    if (body is Map) {
      final direct = body['message'] ?? body['error'] ?? body['msg'];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString().trim();
      }
      final data = body['data'];
      if (data is Map) {
        final nested = data['message'] ?? data['error'] ?? data['msg'];
        if (nested != null && nested.toString().trim().isNotEmpty) {
          return nested.toString().trim();
        }
      }
    }
    return null;
  }

  static void _flattenManagerTree(
    List<dynamic> nodes,
    List<ManagerModel> output,
  ) {
    for (final node in nodes) {
      if (node is! Map) continue;
      output.add(ManagerModel.fromJson(Map<String, dynamic>.from(node)));
      final children = node['children'];
      if (children is List && children.isNotEmpty) {
        _flattenManagerTree(children, output);
      }
    }
  }
}

final managersProvider =
    StateNotifierProvider<ManagersNotifier, ManagersState>((ref) {
  return ManagersNotifier(
    ref.read(sas4DioProvider),
    ref.read(backendDioProvider),
    ref.read(storageServiceProvider),
  );
});
