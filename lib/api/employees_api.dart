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
    this.scopeAdminId,
    this.scopeAdminUsername,
  });
  final int id;
  final String username;
  final String? fullName;
  final String? phone;
  final bool isActive;

  /// Permission key → enabled bool. Default false when absent.
  final Map<String, bool> permissions;

  /// 2026-08-26: لو ≠ null، الموظّف مقيَّد بمدير فرعي محدَّد. يرى
  /// بيانات هذا المدير فقط (subscribers/managers/expenses/...).
  final String? scopeAdminId;
  final String? scopeAdminUsername;

  bool get isScoped => scopeAdminId != null && scopeAdminId!.isNotEmpty;

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
      scopeAdminId: j['scope_admin_id']?.toString(),
      scopeAdminUsername: j['scope_admin_username']?.toString(),
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

  /// [permsByCategory] مقصوراً على المفاتيح التي يقبلها [keep] — الفئات
  /// بترتيبها في الكتالوج، والفئة التي لا يبقى فيها شيءٌ تسقط.
  Map<String, List<PermissionDef>> permsByCategoryWhere(
      bool Function(String key) keep) {
    final out = <String, List<PermissionDef>>{};
    permsByCategory.forEach((cat, defs) {
      final kept = defs.where((d) => keep(d.key)).toList();
      if (kept.isNotEmpty) out[cat] = kept;
    });
    return out;
  }
}

/// دورٌ جاهز لموظّف ايرث لنك — يضبط المفاتيح كلّها دفعةً ثمّ يعدّل المالك.
class ElPermPreset {
  const ElPermPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.keys,
  });

  /// معرّفٌ ثابت للواجهة (الأيقونة) — لا يُرسَل للخادم.
  final String id;
  final String label;
  final String description;

  /// المفاتيح المفعّلة؛ ما سواها من مفاتيح ايرث لنك يُطفأ.
  final Set<String> keys;
}

/// صلاحيّات موظّف ايرث لنك (Pro البند ٤).
///
/// الخادم يفرض على موظّفي EarthLink هذه المفاتيح **بالضبط** (جدول
/// `routePermission` في `server/earthlink/earthlinkRoutes.js`، والأجهزة
/// بمعالجاتها العامّة كباقي المزوّدين). ما سواها من الكتالوج إمّا ميزةٌ لا
/// وجود لها هناك (المدراء الفرعيّون، الإعدادات، البثّ…) وإمّا لصاحب الحساب
/// وحده بلا مفتاح (تحويل الرصيد وكشف الإيداع، إلغاء التسوية) — والموظّف لا
/// يدير موظّفين أبداً.
///
/// فمحرّر موظّفي ايرث لنك يعرض هذه وحدها، و[outgoing] يُرسل غيرها `false`
/// دائماً: لا يمنح المحرّر ما لا يراه المالك (مفاتيحُ افتراضيّتها `true`
/// كـ`whatsapp.send` كانت ستُمنح خفيةً).
class ElEmployeePerms {
  ElEmployeePerms._();

  static const keys = <String>{
    ..._operations,
    // أجهزة الشبكة (OLT/مايكروتك…) — أجهزة الموزّع نفسه، لا علاقة لها بالمزوّد.
    'devices.view',
    'devices.monitor',
    'devices.manage',
  };

  /// المفاتيح بلا الأجهزة — «موظّف عام» يأخذها كلّها (الأجهزة تُمنح فرادى كما في
  /// قوالب الخادم لموظّفي ساس4: إدارتها تكشف بيانات دخول الأجهزة وتعيد تشغيلها).
  static const _operations = <String>{
    'subscribers.view',
    // إضافة مشترك (رصيد/كارت/تجريبي) — يحرس مسارات الإضافة الأربعة عند الخادم.
    'subscribers.add',
    'subscribers.activate',
    'subscribers.extend',
    'subscribers.toggle',
    'subscribers.edit',
    'subscribers.view_credentials',
    'subscribers.add_debt',
    'subscribers.pay_debt',
    'subscribers.send_whatsapp',
    'subscribers.view_activity',
    'packages.view',
    'packages.edit_prices',
    'discounts.view',
    'discounts.manage',
    'subscriber_prices.view',
    'subscriber_prices.manage',
    'reports.financial',
    'reports.activations',
    'reports.daily_activations',
    'reports.expenses',
    'reports.account_statement',
    'reports.sessions',
    'reports.activity_log',
    'settlements.view',
    'settlements.create',
  };

  /// ما يشمله المفتاح عند ايرث لنك ولا تقوله تسميته في الكتالوج.
  static const hints = <String, String>{
    'subscribers.add':
        'بالرصيد (بباسورد الإيداع — يُخصم من رصيد الوكيل) أو بكارت أو تجريبي',
    'subscribers.toggle': 'يشمل قطع اتصال المشترك',
    'reports.financial': 'يشمل رصيد الوكيل والكارتات المطلوبة',
    'reports.expenses': 'عرض الصرفيات وإدارتها',
  };

  /// «موظّف عام» = مفاتيح العمليّات كلّها، ومنها `subscribers.add` (يحوي أصلاً ما
  /// يحرّك المال: تفعيل/تمديد/دين/تسوية). «تفعيل وتحصيل» بلا إضافة — كقالب
  /// «كاشير» في كتالوج الخادم — و«عرض فقط» بلا أيّ عمليّة.
  static const presets = <ElPermPreset>[
    ElPermPreset(
      id: 'general',
      label: 'موظّف عام',
      description: 'يرى ويعمل كلّ ما يُسمح به لموظّف',
      keys: _operations,
    ),
    ElPermPreset(
      id: 'collect',
      label: 'تفعيل وتحصيل',
      description: 'تفعيل وتمديد وتسديد ديون وواتساب',
      keys: {
        'subscribers.view',
        'subscribers.activate',
        'subscribers.extend',
        'subscribers.pay_debt',
        'subscribers.send_whatsapp',
        'packages.view',
        'subscribers.view_activity',
      },
    ),
    ElPermPreset(
      id: 'view',
      label: 'عرض فقط',
      description: 'يشاهد المشتركين والباقات والخصومات والأسعار بلا أيّ عمليّة',
      keys: {
        'subscribers.view',
        'packages.view',
        'discounts.view',
        'subscriber_prices.view',
        'subscribers.view_activity',
      },
    ),
  ];

  /// عدد مفاتيح ايرث لنك المفعّلة — ما يملكه الموظّف فعلاً.
  static int activeCount(Map<String, bool> perms) =>
      keys.where((k) => perms[k] == true).length;

  /// ما يُرسَل للخادم: كلّ مفاتيح الكتالوج — مفاتيح ايرث لنك من [perms]،
  /// والباقي `false`. الاستثناء `whatsapp.send`: يتبع «إرسال واتساب»
  /// (`subscribers.send_whatsapp`) — مسارا تذكير الدين/معلومات المشترك يرسلان
  /// عبر `/api/whatsapp/send-message` بتوكن الموظّف، وهو يفحص `whatsapp.send`،
  /// فبدونه يُرفض موظّفٌ مُنح المراسلة (كـbuildElPermissions في الويب).
  static Map<String, bool> outgoing(
      Iterable<String> catalogKeys, Map<String, bool> perms) {
    final out = {
      for (final k in catalogKeys) k: keys.contains(k) && perms[k] == true,
    };
    if (out.containsKey('whatsapp.send')) {
      out['whatsapp.send'] = perms['subscribers.send_whatsapp'] == true;
    }
    return out;
  }

  /// الدور الجاهز المطابق للمفعَّل الآن تماماً، وإلّا null (مخصّص).
  static ElPermPreset? matching(Map<String, bool> perms) {
    final on = {for (final k in keys) if (perms[k] == true) k};
    for (final p in presets) {
      if (p.keys.length == on.length && on.containsAll(p.keys)) return p;
    }
    return null;
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
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/employees');
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
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/employees/me');
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

  /// [status] رمز HTTP الردّ — `409` = اسم المستخدم محجوز (الأسماء فريدةٌ
  /// على مستوى النظام كلّه، لا عند المدير وحده).
  static Future<({bool ok, String? message, Employee? employee, int? status})>
      create({
    required String username,
    required String password,
    String? fullName,
    String? phone,
    bool isActive = true,
    required Map<String, bool> permissions,

    /// 2026-08-26: يقيّد الموظّف بمدير فرعي (يشوف بياناته فقط).
    /// null = يشاهد بيانات الأب كاملة.
    String? scopeAdminId,
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
          if (scopeAdminId != null && scopeAdminId.isNotEmpty)
            'scope_admin_id': scopeAdminId,
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
        status: r.statusCode,
      );
    } on DioException catch (e) {
      _log('employees (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (
        ok: false,
        message: msg ?? 'تعذّر الإنشاء',
        employee: null,
        status: e.response?.statusCode,
      );
    } catch (e) {
      _log('employees (POST)', e);
      return (ok: false, message: 'تعذّر الإنشاء', employee: null, status: null);
    }
  }

  static Future<({bool ok, String? message})> update({
    required int id,
    String? fullName,
    String? phone,
    String? password,
    bool? isActive,
    Map<String, bool>? permissions,

    /// 2026-08-26: scope الحقل الثلاثيّ:
    ///   - null (parameter): لا تغيير (default)
    ///   - '' (empty string): مسح القيد → يشاهد كل شجرة الأب
    ///   - non-empty: يقيّد بمدير فرعي محدَّد
    String? scopeAdminId,
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
          // فرّق بين "لا تغيير" (null) و "مسح" (empty string).
          if (scopeAdminId != null)
            'scope_admin_id': scopeAdminId.isEmpty ? null : scopeAdminId,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
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
  static Future<({String? password, String? message})> fetchPassword(
      int id) async {
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
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
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
