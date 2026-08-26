import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Employee row. Mirrors v1 _Employee.
class Employee {
  const Employee({
    required this.id,
    required this.username,
    this.fullName,
    this.phone,
    required this.isActive,
    required this.permissions,
  });
  final int id;
  final String username;
  final String? fullName;
  final String? phone;
  final bool isActive;
  /// Permission key → enabled bool. Default false when absent.
  final Map<String, bool> permissions;

  /// Convenience for the list tile — drop unused / always-false.
  int get activePermsCount => permissions.values.where((v) => v).length;

  static Employee? fromJson(Map<String, dynamic> j) {
    final id = int.tryParse(j['id']?.toString() ?? '') ?? 0;
    final username = (j['username'] ?? '').toString();
    if (id == 0 || username.isEmpty) return null;
    final rawPerms = j['permissions'];
    final m = <String, bool>{};
    if (rawPerms is Map) {
      rawPerms.forEach((k, v) => m[k.toString()] = v == true || v == 1);
    }
    return Employee(
      id: id,
      username: username,
      fullName: j['full_name']?.toString(),
      phone: j['phone']?.toString(),
      isActive: j['is_active'] == true || j['is_active'] == 1,
      permissions: m,
    );
  }
}

class PermissionDef {
  const PermissionDef({
    required this.key,
    required this.label,
    required this.category,
  });
  final String key;
  final String label;
  final String category;

  static PermissionDef? fromJson(String key, dynamic raw) {
    if (raw is! Map) return null;
    final label = raw['label']?.toString() ?? key;
    final category = raw['category']?.toString() ?? 'other';
    return PermissionDef(key: key, label: label, category: category);
  }
}

class PermCategory {
  const PermCategory({required this.key, required this.label});
  final String key;
  final String label;

  static PermCategory? fromJson(String key, dynamic raw) {
    if (raw is! Map) return null;
    final label = raw['label']?.toString() ?? key;
    return PermCategory(key: key, label: label);
  }
}

class PermPreset {
  const PermPreset({
    required this.key,
    required this.label,
    required this.description,
    required this.permissions,
  });
  final String key;
  final String label;
  final String description;
  final Map<String, bool> permissions;

  static PermPreset? fromJson(String key, dynamic raw) {
    if (raw is! Map) return null;
    final perms = <String, bool>{};
    final p = raw['permissions'];
    if (p is Map) {
      p.forEach((k, v) => perms[k.toString()] = v == true);
    }
    return PermPreset(
      key: key,
      label: raw['label']?.toString() ?? key,
      description: raw['description']?.toString() ?? '',
      permissions: perms,
    );
  }
}

/// Catalog returned by /api/v2/employees/permissions-catalog. The
/// editor uses it to render the categorized permissions grid + the
/// preset chips at the top of the perms tab.
class PermissionsCatalog {
  const PermissionsCatalog({
    required this.permissions,
    required this.categories,
    required this.permsByCategory,
    required this.defaults,
    required this.presets,
  });
  final Map<String, PermissionDef> permissions;
  final Map<String, PermCategory> categories;
  final Map<String, List<PermissionDef>> permsByCategory;
  final Map<String, bool> defaults;
  final Map<String, PermPreset> presets;

  static PermissionsCatalog fromJson(Map<String, dynamic> j) {
    final permsRaw = j['permissions'];
    final perms = <String, PermissionDef>{};
    if (permsRaw is Map) {
      permsRaw.forEach((k, v) {
        final d = PermissionDef.fromJson(k.toString(), v);
        if (d != null) perms[d.key] = d;
      });
    }
    final catsRaw = j['categories'];
    final cats = <String, PermCategory>{};
    if (catsRaw is Map) {
      catsRaw.forEach((k, v) {
        final c = PermCategory.fromJson(k.toString(), v);
        if (c != null) cats[c.key] = c;
      });
    }
    final byCat = <String, List<PermissionDef>>{};
    for (final p in perms.values) {
      byCat.putIfAbsent(p.category, () => []).add(p);
    }
    final defaultsRaw = j['defaults'];
    final defaults = <String, bool>{};
    if (defaultsRaw is Map) {
      defaultsRaw.forEach((k, v) => defaults[k.toString()] = v == true);
    }
    final presetsRaw = j['presets'];
    final presets = <String, PermPreset>{};
    if (presetsRaw is Map) {
      presetsRaw.forEach((k, v) {
        final p = PermPreset.fromJson(k.toString(), v);
        if (p != null) presets[p.key] = p;
      });
    }
    return PermissionsCatalog(
      permissions: perms,
      categories: cats,
      permsByCategory: byCat,
      defaults: defaults,
      presets: presets,
    );
  }
}

/// Identity returned by /api/v2/employees/me. Used at login time to
/// decide gating (sidebar, action visibility) for employee accounts.
class CurrentIdentity {
  const CurrentIdentity({
    required this.isEmployee,
    this.adminId,
    this.adminUsername,
    this.employeeId,
    this.employeeUsername,
    this.permissions,
  });
  final bool isEmployee;
  final String? adminId;
  final String? adminUsername;
  final int? employeeId;
  final String? employeeUsername;
  /// Null when the actor is the admin itself (full access).
  final Map<String, bool>? permissions;

  static CurrentIdentity? fromJson(Map<String, dynamic> j) {
    final perms = j['permissions'];
    final m = perms is Map
        ? <String, bool>{
            for (final e in perms.entries) e.key.toString(): e.value == true,
          }
        : null;
    return CurrentIdentity(
      isEmployee: j['is_employee'] == true,
      adminId: j['admin_id']?.toString(),
      adminUsername: j['admin_username']?.toString(),
      employeeId: j['employee_id'] is int
          ? j['employee_id'] as int
          : int.tryParse(j['employee_id']?.toString() ?? ''),
      employeeUsername: j['employee_username']?.toString(),
      permissions: m,
    );
  }
}

class EmployeesApi {
  EmployeesApi._();

  static Future<({List<Employee> rows, String? error})> list() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/employees');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (rows: const <Employee>[], error: body['message']?.toString());
      }
      final list = body['data'];
      if (list is! List) return (rows: const <Employee>[], error: null);
      return (
        rows: list
            .whereType<Map>()
            .map((m) => Employee.fromJson(Map<String, dynamic>.from(m)))
            .whereType<Employee>()
            .toList(),
        error: null,
      );
    } on DioException catch (e) {
      _log('employees (GET)', e);
      return (rows: const <Employee>[], error: 'فشل التحميل');
    } catch (e) {
      _log('employees (GET)', e);
      return (rows: const <Employee>[], error: 'فشل التحميل');
    }
  }

  static Future<PermissionsCatalog?> catalog() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/employees/permissions-catalog',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return PermissionsCatalog.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      _log('employees catalog', e);
      return null;
    }
  }

  static Future<CurrentIdentity?> me() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/employees/me');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return CurrentIdentity.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      _log('employees me', e);
      return null;
    }
  }

  static Future<({bool ok, String? message, Employee? employee})> create({
    required String username,
    required String password,
    String? fullName,
    String? phone,
    bool isActive = true,
    required Map<String, bool> permissions,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/employees',
        data: {
          'username': username,
          'password': password,
          if (fullName != null) 'full_name': fullName,
          if (phone != null) 'phone': phone,
          'is_active': isActive,
          'permissions': permissions,
        },
      );
      final body = r.data ?? const {};
      Employee? emp;
      final data = body['data'];
      if (data is Map) {
        emp = Employee.fromJson(Map<String, dynamic>.from(data));
      }
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        employee: emp,
      );
    } on DioException catch (e) {
      _log('employees (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (
        ok: false,
        message: msg ?? 'تعذّر الإنشاء',
        employee: null,
      );
    } catch (e) {
      _log('employees (POST)', e);
      return (ok: false, message: 'تعذّر الإنشاء', employee: null);
    }
  }

  static Future<({bool ok, String? message})> update({
    required int id,
    String? fullName,
    String? phone,
    String? password,
    bool? isActive,
    Map<String, bool>? permissions,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/employees/$id',
        data: {
          if (fullName != null) 'full_name': fullName,
          if (phone != null) 'phone': phone,
          if (password != null && password.isNotEmpty) 'password': password,
          if (isActive != null) 'is_active': isActive,
          if (permissions != null) 'permissions': permissions,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('employees (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التعديل');
    } catch (e) {
      _log('employees (PUT)', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// GET /api/v2/employees/:id/password — كلمة سرّ الموظّف الحاليّة.
  /// Backend يفكّ التشفير AES من `employees.password_encrypted`.
  /// الحقل يُملأ عند create/update. موظّف قديم (قبل feature) → 404
  /// مع نصيحة "عدّل كلمة سرّه مرّة".
  static Future<({String? password, String? message})>
      fetchPassword(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/employees/$id/password',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (password: null, message: body['message']?.toString());
      }
      final data = body['data'] as Map?;
      return (password: data?['password']?.toString(), message: null);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['message']?.toString()
          : null;
      return (password: null, message: msg ?? 'تعذّر جلب كلمة السر');
    } catch (_) {
      return (password: null, message: 'تعذّر جلب كلمة السر');
    }
  }

  static Future<({bool ok, String? message})> delete(int id) async {
    try {
      final r = await ApiClient.dio
          .delete<Map<String, dynamic>>('/api/v2/employees/$id');
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('employees (DELETE)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحذف');
    } catch (e) {
      _log('employees (DELETE)', e);
      return (ok: false, message: 'تعذّر الحذف');
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
