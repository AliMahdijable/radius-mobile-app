import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Manager (sub-admin) row from /api/v2/managers/full. The /full
/// endpoint returns enriched rows (balance + users_count + acl group)
/// — the lightweight /api/v2/managers is only used by the parent
/// picker on the subscribers sheets.
class Manager {
  const Manager({
    required this.id,
    required this.username,
    this.firstname,
    this.lastname,
    this.mobile,
    this.email,
    this.company,
    this.balance,
    this.debt,
    this.rewardPoints,
    this.usersCount,
    this.parentId,
    this.parentUsername,
    this.aclGroupId,
    this.aclGroupName,
    this.enabled = true,
  });
  final int id;
  final String username;
  final String? firstname;
  final String? lastname;
  final String? mobile;
  final String? email;
  final String? company;
  /// `balance` SAS4 يرجّعه ك"credit" — رصيد إيجابي مالي.
  final num? balance;
  /// `debt` SAS4 = الدين النقدي (لم يتم سداد كلفة الباقات). v1
  /// مطلب: ظهور chip 'دين الساس' لو > 0.
  final num? debt;
  /// نقاط المكافأة — مطلب 2026-06-12 (v1 يعرضها كـchip بنفسجي).
  final num? rewardPoints;
  final int? usersCount;
  final int? parentId;
  final String? parentUsername;
  final int? aclGroupId;
  final String? aclGroupName;
  final bool enabled;

  String get fullName {
    final parts = [firstname, lastname]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList();
    return parts.isEmpty ? username : parts.join(' ');
  }

  static Manager? fromJson(Map<String, dynamic> j) {
    final rawId = j['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return null;
    final username = (j['username'] ?? '').toString();
    if (username.isEmpty) return null;
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    int? toInt(dynamic v) =>
        v is int ? v : (v == null ? null : int.tryParse(v.toString()));
    final aclDetails = j['acl_group_details'];
    String? aclName;
    if (aclDetails is Map) {
      aclName = aclDetails['name']?.toString();
    } else if (aclDetails != null) {
      aclName = aclDetails.toString();
    }
    return Manager(
      id: id,
      username: username,
      firstname: j['firstname']?.toString(),
      lastname: j['lastname']?.toString(),
      mobile: j['mobile']?.toString(),
      email: j['email']?.toString(),
      company: j['company']?.toString(),
      balance: toNum(j['balance']),
      debt: toNum(j['debt']),
      rewardPoints: toNum(j['reward_points'] ?? j['rewardPoints']),
      usersCount: toInt(j['users_count']),
      parentId: toInt(j['parent_id']),
      parentUsername: j['parent_username']?.toString(),
      aclGroupId: toInt(j['acl_group_id']),
      aclGroupName: aclName,
      enabled: (j['enabled'] ?? 1) != 0 && j['enabled'] != false,
    );
  }
}

class AclGroup {
  const AclGroup({required this.id, required this.name});
  final int id;
  final String name;

  static AclGroup? fromJson(Map<String, dynamic> j) {
    final id = j['id'] is int
        ? j['id'] as int
        : int.tryParse(j['id']?.toString() ?? '');
    final name = (j['name'] ?? '').toString();
    if (id == null || name.isEmpty) return null;
    return AclGroup(id: id, name: name);
  }
}

class ManagersApi {
  ManagersApi._();

  /// GET /api/v2/managers/full?page=1&count=100 — list with stats.
  static Future<({List<Manager> rows, int total})> listFull({
    int page = 1,
    int count = 100,
    String search = '',
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/managers/full',
        queryParameters: {
          'page': page,
          'count': count,
          'sortBy': 'username',
          'direction': 'asc',
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

  /// GET /api/v2/acl-list — used by add/edit sheets to populate the
  /// "مجموعة الصلاحيات" picker.
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

  /// GET /api/v2/managers — قائمة خفيفة (id + username + name) للـ
  /// parent picker. يرجّع null لو الـauth ما يسمح بعرض المدراء.
  static Future<List<({int id, String username, String displayName})>?>
      lite() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/managers');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final list = (body['data'] as List?) ?? const [];
      final out = <({int id, String username, String displayName})>[];
      for (final row in list) {
        if (row is! Map) continue;
        final rawId = row['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (id == null) continue;
        final username = (row['username'] ?? '').toString();
        if (username.isEmpty) continue;
        final fname = (row['firstname'] ?? '').toString().trim();
        final lname = (row['lastname'] ?? '').toString().trim();
        final arabic = [fname, lname].where((s) => s.isNotEmpty).join(' ');
        out.add((
          id: id,
          username: username,
          displayName:
              arabic.isNotEmpty ? '$arabic ($username)' : username,
        ));
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

  /// POST /api/v2/managers — create a new sub-manager. Required:
  /// username, password, aclGroupId. Optional: firstname, lastname,
  /// mobile, email, parentId (defaults to current admin), enabled.
  static Future<({bool ok, String? message, int? id})> create({
    required String username,
    required String password,
    required int aclGroupId,
    String? firstname,
    String? lastname,
    String? mobile,
    String? email,
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
          if (parentId != null) 'parent_id': parentId,
          'enabled': enabled ? 1 : 0,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      final rawId = body['id'] ?? body['data']?['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      return (ok: ok, message: body['message']?.toString(), id: id);
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

  /// PUT /api/v2/managers/:id
  static Future<({bool ok, String? message})> update({
    required int id,
    String? username,
    String? password,
    String? firstname,
    String? lastname,
    String? mobile,
    String? email,
    int? aclGroupId,
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
          if (aclGroupId != null) 'acl_group_id': aclGroupId,
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

  /// DELETE /api/v2/managers/:id
  static Future<({bool ok, String? message})> delete(int id) async {
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

  /// POST /api/v2/managers/:id/deposit — شحن رصيد. `isLoan=true`
  /// يحفظ كـدين على المدير الفرعي (إيداع آجل) بدل شحن نقدي عادي.
  static Future<({bool ok, String? message})> deposit({
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

  /// POST /api/v2/managers/:id/withdraw — سحب رصيد
  static Future<({bool ok, String? message})> withdraw({
    required int id,
    required num amount,
    String? note,
  }) async {
    return _balanceOp(
      endpoint: 'withdraw',
      id: id,
      amount: amount,
      note: note,
    );
  }

  /// POST /api/v2/managers/:id/add-points — إضافة نقاط
  static Future<({bool ok, String? message})> addPoints({
    required int id,
    required num amount,
    String? note,
  }) async {
    return _balanceOp(
      endpoint: 'add-points',
      id: id,
      amount: amount,
      note: note,
    );
  }

  static Future<({bool ok, String? message})> _balanceOp({
    required String endpoint,
    required int id,
    required num amount,
    String? note,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/managers/$id/$endpoint',
        data: {
          'amount': amount,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('v2/managers/$id/$endpoint', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشلت العملية');
    } catch (e) {
      _log('v2/managers/$id/$endpoint', e);
      return (ok: false, message: 'فشلت العملية');
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
