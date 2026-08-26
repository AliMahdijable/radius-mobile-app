import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Manager (sub-admin) model. Mirrors v1 mobile-app/lib/models/
/// manager_model.dart so the same fields, fallbacks and computed
/// properties are available end-to-end. The v2 rebuild
/// (2026-06-11, user request: "ابدأ من الصفر") brings the model in
/// line with v1's parsing chain — especially the debt fields, which
/// SAS4 reports under inconsistent column names.
class Manager {
  const Manager({
    required this.id,
    required this.username,
    this.firstname = '',
    this.lastname = '',
    this.balance = 0,
    this.usersCount = 0,
    this.aclName,
    this.aclId,
    this.isActive = true,
    this.email = '',
    this.mobile = '',
    this.company = '',
    this.city = '',
    this.address = '',
    this.notes = '',
    this.parentId,
    this.parentUsername,
    this.totalDebt = 0,
    this.debtForMe = 0,
    this.rewardPoints = 0,
  });

  final int id;
  final String username;
  final String firstname;
  final String lastname;

  /// SAS4 balance — positive = credit on the admin's side,
  /// negative = the admin owes us. Used together with `totalDebt`
  /// to render the debt chip.
  final double balance;

  final int usersCount;
  final String? aclName;
  final int? aclId;
  final bool isActive;
  final String email;
  final String mobile;
  final String company;
  final String city;
  final String address;
  final String notes;
  final int? parentId;
  final String? parentUsername;

  /// The authoritative SAS4 debt — incremented by loan deposits and
  /// decremented by /manager/payDebt. Read with the v1 fallback chain
  /// (total_debt → debt → total) because the column name varies by
  /// endpoint (/index/manager vs /manager/{id}).
  final double totalDebt;

  /// Debt this sub-manager owes *to me specifically* (in multi-parent
  /// trees). Used as a parameter to /manager/payDebt.
  final double debtForMe;

  final int rewardPoints;

  String get fullName => '$firstname $lastname'.trim();
  double get credit => balance > 0 ? balance : 0;
  double get debt =>
      totalDebt > 0 ? totalDebt : (balance < 0 ? balance.abs() : 0);

  /// Returns null if the row is missing a usable id/username so the
  /// caller can filter parse failures out rather than crash.
  static Manager? fromJson(Map<String, dynamic> j) {
    final id = _toInt(j['id'] ?? j['idx']);
    final username = (j['username'] ?? '').toString();
    if (id == 0 || username.isEmpty) return null;
    final aclDetails = j['acl_group_details'];
    final stats = j['stats'];
    return Manager(
      id: id,
      username: username,
      firstname: (j['firstname'] ?? '').toString(),
      lastname: (j['lastname'] ?? '').toString(),
      balance: _toDouble(j['balance']),
      usersCount: _toInt(j['users_count']),
      aclName: aclDetails is Map
          ? aclDetails['name']?.toString()
          : j['acl_name']?.toString(),
      aclId: j['acl_id'] != null
          ? _toInt(j['acl_id'])
          : (aclDetails is Map && aclDetails['id'] != null
              ? _toInt(aclDetails['id'])
              : null),
      isActive: _toBool(j['is_active'] ?? j['enabled'] ?? true),
      email: (j['email'] ?? '').toString(),
      mobile: (j['mobile'] ?? j['phone'] ?? '').toString(),
      company: (j['company'] ?? '').toString(),
      city: (j['city'] ?? '').toString(),
      address: (j['address'] ?? '').toString(),
      notes: (j['notes'] ?? '').toString(),
      parentId: j['parent_id'] != null ? _toInt(j['parent_id']) : null,
      parentUsername: j['parent_username']?.toString(),
      // v1 manager_model:70 — SAS4 uses `total_debt` for the
      // authoritative debt column; `debt` and `total` are fallbacks
      // for older endpoints (/manager/{id}/debt returns `total`).
      // SAS4 reports debt as a negative magnitude; mirror v1's
      // .abs() so all callers can treat it as a positive size.
      totalDebt: _toDouble(j['total_debt'] ?? j['debt'] ?? j['total'] ?? 0).abs(),
      debtForMe: _toDouble(j['debt_for_me']).abs(),
      // v1 manager_model:74 — reward_points lives in many places
      // depending on the endpoint. Mirror the full fallback list.
      rewardPoints: _toInt(
        j['reward_points'] ??
            j['points'] ??
            j['reward_points_balance'] ??
            j['points_balance'] ??
            j['rewardPoints'] ??
            j['points_count'] ??
            j['bonus_points'] ??
            (stats is Map
                ? stats['reward_points'] ??
                    stats['points'] ??
                    stats['points_count'] ??
                    stats['reward_points_balance']
                : null) ??
            0,
      ),
    );
  }

  Manager copyWith({
    int? id,
    String? username,
    String? firstname,
    String? lastname,
    double? balance,
    int? usersCount,
    String? aclName,
    int? aclId,
    bool? isActive,
    String? email,
    String? mobile,
    String? company,
    String? city,
    String? address,
    String? notes,
    int? parentId,
    String? parentUsername,
    double? totalDebt,
    double? debtForMe,
    int? rewardPoints,
  }) =>
      Manager(
        id: id ?? this.id,
        username: username ?? this.username,
        firstname: firstname ?? this.firstname,
        lastname: lastname ?? this.lastname,
        balance: balance ?? this.balance,
        usersCount: usersCount ?? this.usersCount,
        aclName: aclName ?? this.aclName,
        aclId: aclId ?? this.aclId,
        isActive: isActive ?? this.isActive,
        email: email ?? this.email,
        mobile: mobile ?? this.mobile,
        company: company ?? this.company,
        city: city ?? this.city,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        parentId: parentId ?? this.parentId,
        parentUsername: parentUsername ?? this.parentUsername,
        totalDebt: totalDebt ?? this.totalDebt,
        debtForMe: debtForMe ?? this.debtForMe,
        rewardPoints: rewardPoints ?? this.rewardPoints,
      );
}

class AclGroup {
  const AclGroup({required this.id, required this.name});
  final int id;
  final String name;

  static AclGroup? fromJson(Map<String, dynamic> j) {
    final id = _toInt(j['id']);
    final name = (j['name'] ?? '').toString();
    if (id == 0 || name.isEmpty) return null;
    return AclGroup(id: id, name: name);
  }
}

/// Returned by GET /manager/debt/{id}. The endpoint's payload calls
/// the total debt column `total`, not `total_debt` — so Manager.fromJson
/// can't be used here directly.
class ManagerDebtInfo {
  const ManagerDebtInfo({
    required this.balance,
    required this.totalDebt,
    required this.debtForMe,
  });
  final double balance;
  final double totalDebt;
  final double debtForMe;

  factory ManagerDebtInfo.fromJson(Map<String, dynamic> j) {
    final data =
        j['data'] is Map<String, dynamic> ? j['data'] as Map<String, dynamic> : j;
    // مطلب 2026-06-11: SAS4 يرجّع الدين كرقم سالب (debt = -1.6M
    // معناها مدين بـ1.6M). v1 يأخذ `.abs()` في _enrichManagers
    // فنبقي على نفس الاتفاقية: الدين هنا دائماً magnitude موجب،
    // والإشارة تأتي من سياق الحقل (balance قد يكون سالب).
    return ManagerDebtInfo(
      balance: _toDouble(data['balance']),
      totalDebt: _toDouble(data['total']).abs(),
      debtForMe: _toDouble(data['debt_for_me']).abs(),
    );
  }
}

/// Stripped-down row used by parent-picker / lite list endpoints.
typedef ManagerLite = ({int id, String username, String displayName});

/// Result tuple shared by every mutating call so the UI can show a
/// success snack or the Arabic error from SAS4 / our backend.
typedef ApiResult = ({bool ok, String? message});
typedef ApiResultWithId = ({bool ok, String? message, int? id});

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

bool _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().toLowerCase().trim();
  return s == '1' || s == 'true';
}

class ManagersApi {
  ManagersApi._();

  // ===========================================================
  // READ
  // ===========================================================

  /// GET /api/v2/managers/:id/password — كلمة سرّ المدير الفرعي.
  /// مصدرها whatsapp_sessions.admin_password_encrypted (تُخزَّن حين
  /// المدير يسجّل دخول في النظام). Backend يفكّ التشفير AES.
  ///
  /// - null: تعذّر (لم يسجّل دخول / خطأ صلاحيّة / شبكة). الـUI يعرض
  ///   رسالة السيرفر لو موجودة.
  static Future<({String? password, String? message})>
      fetchPassword(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/managers/$id/password',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (password: null, message: body['message']?.toString());
      }
      final data = body['data'] as Map?;
      final p = data?['password']?.toString();
      return (password: p, message: null);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['message']?.toString()
          : null;
      return (password: null, message: msg ?? 'تعذّر جلب كلمة السر');
    } catch (_) {
      return (password: null, message: 'تعذّر جلب كلمة السر');
    }
  }

  /// GET /api/v2/managers/full — list with stats. The backend wraps
  /// SAS4's /index/manager and enriches each row with balance/debt/
  /// reward_points columns. The columns list is set on the server
  /// (see server.js /api/v2/managers/full handler).
  static Future<({List<Manager> rows, int total})> listFull({
    int page = 1,
    int count = 100,
    String search = '',
    String sortBy = 'username',
    String direction = 'asc',
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/managers/full',
        queryParameters: {
          'page': page,
          'count': count,
          'sortBy': sortBy,
          'direction': direction,
          if (search.isNotEmpty) 'search': search,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return (rows: const <Manager>[], total: 0);
      final list = body['data'];
      if (list is! List) return (rows: const <Manager>[], total: 0);
      final rows = list
          .whereType<Map>()
          .map((m) => Manager.fromJson(Map<String, dynamic>.from(m)))
          .whereType<Manager>()
          .toList();
      final rawTotal = body['total'];
      final total = rawTotal is int
          ? rawTotal
          : int.tryParse(rawTotal?.toString() ?? '') ?? rows.length;
      return (rows: rows, total: total);
    } on DioException catch (e) {
      _log('v2/managers/full (GET)', e);
      return (rows: const <Manager>[], total: 0);
    } catch (e) {
      _log('v2/managers/full (GET)', e);
      return (rows: const <Manager>[], total: 0);
    }
  }

  /// GET /api/v2/managers/:id — full details for one manager (fresh
  /// from SAS4). Used by the edit form on open so we don't ship stale
  /// list-derived values to the inputs.
  static Future<Manager?> details(int id) async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/managers/$id');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return Manager.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      _log('v2/managers/:id (GET)', e);
      return null;
    } catch (e) {
      _log('v2/managers/:id (GET)', e);
      return null;
    }
  }

  /// GET /api/v2/managers/:id/debt — `/manager/debt/{id}` proxied.
  /// v1 calls this just before opening the pay-debt sheet so the
  /// numbers reflect the authoritative SAS4 figures (instead of the
  /// list-cached `totalDebt` which may be a few seconds stale).
  static Future<ManagerDebtInfo?> debtInfo(int id) async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/managers/$id/debt');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return ManagerDebtInfo.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      _log('v2/managers/:id/debt (GET)', e);
      return null;
    } catch (e) {
      _log('v2/managers/:id/debt (GET)', e);
      return null;
    }
  }

  /// GET /api/v2/acl-list — used by the add/edit sheet's
  /// "مجموعة الصلاحيات" dropdown.
  static Future<List<AclGroup>> aclGroups() async {
    try {
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/acl-list');
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => AclGroup.fromJson(Map<String, dynamic>.from(m)))
          .whereType<AclGroup>()
          .toList();
    } on DioException catch (e) {
      _log('v2/acl-list (GET)', e);
      return const [];
    } catch (e) {
      _log('v2/acl-list (GET)', e);
      return const [];
    }
  }

  /// GET /api/v2/managers — lightweight (id + username + display name)
  /// for parent pickers across the app. Returns null when the
  /// current admin doesn't have permission to view managers.
  static Future<List<ManagerLite>?> lite() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/managers');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final list = (body['data'] as List?) ?? const [];
      final out = <ManagerLite>[];
      for (final row in list) {
        if (row is! Map) continue;
        final id = _toInt(row['id']);
        if (id == 0) continue;
        final username = (row['username'] ?? '').toString();
        if (username.isEmpty) continue;
        out.add((id: id, username: username, displayName: username));
      }
      out.sort((a, b) => a.username.compareTo(b.username));
      return out;
    } on DioException catch (e) {
      _log('v2/managers lite (GET)', e);
      return null;
    } catch (e) {
      _log('v2/managers lite (GET)', e);
      return null;
    }
  }

  // ===========================================================
  // CRUD
  // ===========================================================

  /// POST /api/v2/managers — create. Returns the new id when SAS4
  /// reports success, or an Arabic message describing the rejection.
  static Future<ApiResultWithId> create({
    required String username,
    required String password,
    required int aclGroupId,
    String? firstname,
    String? lastname,
    String? mobile,
    String? email,
    String? company,
    int? parentId,
    bool enabled = true,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/managers',
        data: {
          'username': username,
          'password': password,
          'acl_group_id': aclGroupId,
          if (firstname != null && firstname.isNotEmpty) 'firstname': firstname,
          if (lastname != null && lastname.isNotEmpty) 'lastname': lastname,
          if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
          if (email != null && email.isNotEmpty) 'email': email,
          if (company != null && company.isNotEmpty) 'company': company,
          if (parentId != null) 'parent_id': parentId,
          'enabled': enabled ? 1 : 0,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      final rawId = body['id'] ?? body['data']?['id'];
      final id = _toInt(rawId);
      return (
        ok: ok,
        message: body['message']?.toString(),
        id: id == 0 ? null : id,
      );
    } on DioException catch (e) {
      _log('v2/managers (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الإنشاء', id: null);
    } catch (e) {
      _log('v2/managers (POST)', e);
      return (ok: false, message: 'تعذّر الإنشاء', id: null);
    }
  }

  /// PUT /api/v2/managers/:id — update a subset of fields.
  static Future<ApiResult> update({
    required int id,
    String? username,
    String? password,
    String? firstname,
    String? lastname,
    String? mobile,
    String? email,
    String? company,
    int? aclGroupId,
    int? parentId,
    bool? enabled,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/managers/$id',
        data: {
          if (username != null) 'username': username,
          if (password != null && password.isNotEmpty) 'password': password,
          if (firstname != null) 'firstname': firstname,
          if (lastname != null) 'lastname': lastname,
          if (mobile != null) 'mobile': mobile,
          if (email != null) 'email': email,
          if (company != null) 'company': company,
          if (aclGroupId != null) 'acl_group_id': aclGroupId,
          if (parentId != null) 'parent_id': parentId,
          if (enabled != null) 'enabled': enabled ? 1 : 0,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التعديل');
    } catch (e) {
      _log('v2/managers (PUT)', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// DELETE /api/v2/managers/:id — backend now checks SAS4's body
  /// status before reporting success, so a silent SAS4 rejection
  /// surfaces as ok:false here (fixed 2026-06-11).
  static Future<ApiResult> delete(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/v2/managers/$id',
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers (DELETE)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحذف');
    } catch (e) {
      _log('v2/managers (DELETE)', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  // ===========================================================
  // BALANCE OPS
  // ===========================================================

  /// POST /api/v2/managers/:id/deposit — تعبئة رصيد.
  /// `isLoan=true` flags it as a loan (debt added on the sub-manager
  /// side, balance still incremented). Mirrors v1
  /// managers_provider.dart:502 (addBalance).
  static Future<ApiResult> deposit({
    required int id,
    required num amount,
    String? note,
    bool isLoan = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/managers/$id/deposit',
        data: {
          'amount': amount,
          if (note != null && note.isNotEmpty) 'comment': note,
          'isLoan': isLoan,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers/$id/deposit', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشلت العملية');
    } catch (e) {
      _log('v2/managers/$id/deposit', e);
      return (ok: false, message: 'فشلت العملية');
    }
  }

  /// POST /api/v2/managers/:id/withdraw — سحب رصيد.
  static Future<ApiResult> withdraw({
    required int id,
    required num amount,
    String? note,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/managers/$id/withdraw',
        data: {
          'amount': amount,
          if (note != null && note.isNotEmpty) 'comment': note,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers/$id/withdraw', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشلت العملية');
    } catch (e) {
      _log('v2/managers/$id/withdraw', e);
      return (ok: false, message: 'فشلت العملية');
    }
  }

  /// POST /api/v2/managers/:id/sas-pay-debt — تسديد دين الـSAS4.
  /// Mirrors v1 managers_provider.dart:620 (payDebt).
  static Future<ApiResult> sasPayDebt({
    required int id,
    required num amount,
    String? note,
    num? debtForMe,
    num? totalDebt,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/managers/$id/sas-pay-debt',
        data: {
          'amount': amount,
          if (note != null && note.isNotEmpty) 'comment': note,
          if (debtForMe != null) 'debtForMe': debtForMe,
          if (totalDebt != null) 'totalDebt': totalDebt,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers/$id/sas-pay-debt', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشل تسديد الدين');
    } catch (e) {
      _log('v2/managers/$id/sas-pay-debt', e);
      return (ok: false, message: 'فشل تسديد الدين');
    }
  }

  /// POST /api/v2/managers/:id/add-points — إضافة نقاط مكافأة.
  /// Mirrors v1 managers_provider.dart:680 (addPoints).
  static Future<ApiResult> addPoints({
    required int id,
    required num points,
    String? note,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/managers/$id/add-points',
        data: {
          'points': points,
          if (note != null && note.isNotEmpty) 'comment': note,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers/$id/add-points', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشل إضافة النقاط');
    } catch (e) {
      _log('v2/managers/$id/add-points', e);
      return (ok: false, message: 'فشل إضافة النقاط');
    }
  }

  // ===========================================================
  // FCM PUSH NOTIFICATION
  // ===========================================================

  /// POST /api/fcm/send-manager-balance-update — fires the in-app
  /// push + notifications inbox row. Mirrors v1
  /// managers_provider.dart:760. `actionKind` drives the title:
  /// 'cash_deposit' / 'loan_deposit' / 'debt_payment' / 'info' /
  /// 'withdraw' / 'add_points'.
  static Future<ApiResult> sendBalanceUpdatePush({
    required Manager manager,
    required num amount,
    required bool isLoan,
    required num previousCredit,
    required num previousDebt,
    required num currentCredit,
    required num currentDebt,
    required String actionKind,
    String? notes,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/fcm/send-manager-balance-update',
        data: {
          'targetAdminId': manager.id.toString(),
          'amount': amount,
          'isLoan': isLoan,
          'previousCredit': previousCredit,
          'previousDebt': previousDebt,
          'currentCredit': currentCredit,
          'currentDebt': currentDebt,
          'actionKind': actionKind,
          'notes': (notes ?? '').trim(),
          'managerUsername': manager.username,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('fcm/send-manager-balance-update', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر إرسال الإشعار');
    } catch (e) {
      _log('fcm/send-manager-balance-update', e);
      return (ok: false, message: 'تعذّر إرسال الإشعار');
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
