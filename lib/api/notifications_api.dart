import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// موظّفٌ في «من موظّفيك» — كما يرسله GET `employee_ops.employees` (موظّفو الصفحة النشطون).
@immutable
class EmployeeOpsPerson {
  const EmployeeOpsPerson(this.id, this.name);
  final int id;
  final String name;
}

/// «من موظّفيك» كما يحفظه الخادم (`prefs.employee_ops_ids`): أرقامٌ ⇒ مرتّبة بلا تكرار؛ غيابها أو فراغها ⇒ null = كلّ الموظّفين.
List<int>? parseEmployeeOpsIds(dynamic v) {
  if (v is! List) return null;
  final out = <int>{};
  for (final x in v) {
    final n = x is int ? x : int.tryParse('$x'.trim());
    if (n != null && n > 0) out.add(n);
  }
  if (out.isEmpty) return null;
  return out.toList()..sort();
}

List<EmployeeOpsPerson>? _parseEmployees(dynamic v) {
  if (v is! List) return null;
  return [
    for (final e in v)
      if (e is Map && (e['id'] is int || int.tryParse('${e['id']}') != null) && '${e['name'] ?? ''}'.trim().isNotEmpty)
        EmployeeOpsPerson(e['id'] is int ? e['id'] as int : int.parse('${e['id']}'), '${e['name']}'.trim()),
  ];
}

/// تفضيلات الإشعارات لكل أدمن. الـbackend يخزّنها في
/// admin_notification_prefs. الـfields:
///   • pushNearExpiry — تذكير اقتراب انتهاء اشتراك
///   • pushExpiredToday — تنبيه انتهاء اشتراك اليوم
///   • pushManagerDebt — تنبيه دين مدير فرعي
///   • quietHoursEnabled — تفعيل أوقات السكون
///   • quietHoursStart/End — "HH:MM" (24h)
class NotificationPrefs {
  const NotificationPrefs({
    required this.pushNearExpiry,
    required this.pushExpiredToday,
    required this.pushManagerDebt,
    this.pushWataniTicket = true,
    this.pushEmployeeOps = true,
    this.employeeOpsAvailable = false,
    this.employeeOpsCanEdit = true,
    this.employeeOpsIds,
    this.employeeOpsEmployees,
    required this.quietHoursEnabled,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  final bool pushNearExpiry;
  final bool pushExpiredToday;
  final bool pushManagerDebt;

  /// «تذاكر المشروع الوطني» (push_watani_ticket، الخادم ١ نوفمبر) — غائبٌ من خادمٍ أقدم ⇒ مفعّل.
  final bool pushWataniTicket;

  /// «عمليّات الموظّفين» (push_employee_ops، الخادم ٢٣ نوفمبر — server/employeeOps.js) — غائبٌ ⇒ مفعّل كافتراض الخادم.
  final bool pushEmployeeOps;

  /// ليسا تفضيلاً: هل يقدّم الخادم «عمليّات الموظّفين» لهذه الصفحة (GET `employee_ops.available` — مفتاحها وموظّفون فعّالون)،
  /// وهل يعدّله هذا الداخل (`can_edit` — صاحب الصفحة وحده). ردّ الحفظ لا يحملهما ⇒ يُنقلان من الطلب ([NotificationsApi.save]).
  final bool employeeOpsAvailable;
  final bool employeeOpsCanEdit;

  /// «من موظّفيك» (الخادم ٢٣ نوفمبر، الهجرة 126 — المالك: «يحدد اكثر من واحد او واحد مستقل او الكل»): من تصله عمليّاتهم —
  /// null = كلّ الموظّفين ومن يُضاف لاحقاً. يُحفظ بطلبه وحده ([NotificationsApi.saveEmployeeOpsIds]) لا مع بقيّة التفضيلات.
  final List<int>? employeeOpsIds;

  /// موظّفو الصفحة النشطون للاختيار (GET `employee_ops.employees` — لصاحبها حين يتاح)؛ null = لم تصل القائمة ⇒ لا صفّ اختيار.
  final List<EmployeeOpsPerson>? employeeOpsEmployees;
  final bool quietHoursEnabled;
  final String quietHoursStart;
  final String quietHoursEnd;

  /// قيم افتراضية تستعمل لو الـbackend رجّع null أو الـadmin أول مرة.
  /// مطابقة default الـbackend.
  static const defaults = NotificationPrefs(
    pushNearExpiry: true,
    pushExpiredToday: true,
    pushManagerDebt: true,
    quietHoursEnabled: false,
    quietHoursStart: '22:00',
    quietHoursEnd: '08:00',
  );

  NotificationPrefs copyWith({
    bool? pushNearExpiry,
    bool? pushExpiredToday,
    bool? pushManagerDebt,
    bool? pushWataniTicket,
    bool? pushEmployeeOps,
    bool? employeeOpsAvailable,
    bool? employeeOpsCanEdit,
    List<EmployeeOpsPerson>? employeeOpsEmployees,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) =>
      NotificationPrefs(
        pushNearExpiry: pushNearExpiry ?? this.pushNearExpiry,
        pushExpiredToday: pushExpiredToday ?? this.pushExpiredToday,
        pushManagerDebt: pushManagerDebt ?? this.pushManagerDebt,
        pushWataniTicket: pushWataniTicket ?? this.pushWataniTicket,
        pushEmployeeOps: pushEmployeeOps ?? this.pushEmployeeOps,
        employeeOpsAvailable: employeeOpsAvailable ?? this.employeeOpsAvailable,
        employeeOpsCanEdit: employeeOpsCanEdit ?? this.employeeOpsCanEdit,
        employeeOpsIds: employeeOpsIds,
        employeeOpsEmployees: employeeOpsEmployees ?? this.employeeOpsEmployees,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      );

  /// «من موظّفيك» جديداً — null = الكلّ (لذا ليس في [copyWith] حيث null = بلا تغيير).
  NotificationPrefs withEmployeeOpsIds(List<int>? ids) => NotificationPrefs(
        pushNearExpiry: pushNearExpiry,
        pushExpiredToday: pushExpiredToday,
        pushManagerDebt: pushManagerDebt,
        pushWataniTicket: pushWataniTicket,
        pushEmployeeOps: pushEmployeeOps,
        employeeOpsAvailable: employeeOpsAvailable,
        employeeOpsCanEdit: employeeOpsCanEdit,
        employeeOpsIds: ids == null || ids.isEmpty ? null : (ids.toSet().toList()..sort()),
        employeeOpsEmployees: employeeOpsEmployees,
        quietHoursEnabled: quietHoursEnabled,
        quietHoursStart: quietHoursStart,
        quietHoursEnd: quietHoursEnd,
      );

  /// [employeeOps] = `employee_ops` من ردّ GET (`{available, can_edit}`) — غائبٌ ⇒ غير متاح.
  factory NotificationPrefs.fromJson(Map<String, dynamic> j, {Object? employeeOps}) {
    final eo = employeeOps is Map ? employeeOps : const {};
    bool b(dynamic v, bool fallback) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return fallback;
    }

    String t(dynamic v, String fallback) {
      if (v == null) return fallback;
      final s = v.toString();
      // الـbackend قد يرجّع "HH:MM:SS" — نقصّ أول 5 خانات فقط.
      return s.length >= 5 ? s.substring(0, 5) : s;
    }

    return NotificationPrefs(
      pushNearExpiry: b(j['push_near_expiry'], true),
      pushExpiredToday: b(j['push_expired_today'], true),
      pushManagerDebt: b(j['push_manager_debt'], true),
      pushWataniTicket: b(j['push_watani_ticket'], true),
      pushEmployeeOps: b(j['push_employee_ops'], true),
      employeeOpsAvailable: eo['available'] == true,
      employeeOpsCanEdit: eo['can_edit'] != false,
      employeeOpsIds: parseEmployeeOpsIds(j['employee_ops_ids']),
      employeeOpsEmployees: _parseEmployees(eo['employees']),
      quietHoursEnabled: b(j['quiet_hours_enabled'], false),
      quietHoursStart: t(j['quiet_hours_start'], '22:00'),
      quietHoursEnd: t(j['quiet_hours_end'], '08:00'),
    );
  }
}

class NotificationsApi {
  NotificationsApi._();

  /// GET /api/admin/notification-prefs — يجلب التفضيلات الحالية.
  /// لو الـadmin أول مرة يفتح الإعدادات، الـbackend يعيد defaults.
  static Future<NotificationPrefs?> load() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/admin/notification-prefs');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final prefs = body['prefs'];
      if (prefs is! Map) return null;
      return NotificationPrefs.fromJson(Map<String, dynamic>.from(prefs), employeeOps: body['employee_ops']);
    } on DioException catch (e) {
      _log('notification-prefs (GET)', e);
      return null;
    } catch (e) {
      _log('notification-prefs (GET)', e);
      return null;
    }
  }

  /// PUT /api/admin/notification-prefs — يحفظ المفاتيح المعدّلة.
  static Future<({bool ok, String? message, NotificationPrefs? prefs})> save(
      NotificationPrefs p) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/notification-prefs',
        data: {
          'pushNearExpiry': p.pushNearExpiry,
          'pushExpiredToday': p.pushExpiredToday,
          'pushManagerDebt': p.pushManagerDebt,
          'pushWataniTicket': p.pushWataniTicket,
          // «عمليّات الموظّفين» حين عُرض مفتاحها لصاحب الصفحة وحده — وإلّا يبقى المحفوظ (الحفظ دمجٌ بالخادم)، فلا تعيده
          // شاشةٌ لم تعرضه إلى قيمتها القديمة
          if (p.employeeOpsAvailable && p.employeeOpsCanEdit) 'pushEmployeeOps': p.pushEmployeeOps,
          'quietHoursEnabled': p.quietHoursEnabled,
          'quietHoursStart': p.quietHoursStart,
          'quietHoursEnd': p.quietHoursEnd,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      NotificationPrefs? returned;
      final returnedRaw = body['prefs'];
      if (returnedRaw is Map) {
        // ردّ الحفظ بلا employee_ops ⇒ الإتاحة والقفل وقائمة الموظّفين من الطلب (وإلّا يختفي المفتاح بعد أوّل حفظ)
        returned = NotificationPrefs.fromJson(Map<String, dynamic>.from(returnedRaw)).copyWith(
          employeeOpsAvailable: p.employeeOpsAvailable,
          employeeOpsCanEdit: p.employeeOpsCanEdit,
          employeeOpsEmployees: p.employeeOpsEmployees,
        );
      }
      return (
        ok: ok,
        message: body['message']?.toString(),
        prefs: returned,
      );
    } on DioException catch (e) {
      _log('notification-prefs (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحفظ', prefs: null);
    } catch (e) {
      _log('notification-prefs (PUT)', e);
      return (ok: false, message: 'تعذّر الحفظ', prefs: null);
    }
  }

  /// «من موظّفيك»: PUT `{employeeOpsIds}` وحده — null = كلّ الموظّفين. الخادم يقبله من صاحب الصفحة، وأرقامَ موظّفيها وحدها
  /// (كلّها غريبة ⇒ 400 برسالةٍ عربيّة). [ids] في الردّ = ما حُفظ فعلاً (null = الكلّ).
  static Future<({bool ok, String? message, List<int>? ids})> saveEmployeeOpsIds(List<int>? ids) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/notification-prefs',
        data: {'employeeOpsIds': ids == null || ids.isEmpty ? null : ids},
      );
      final body = r.data ?? const {};
      final prefs = body['prefs'];
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        ids: prefs is Map ? parseEmployeeOpsIds(prefs['employee_ops_ids']) : parseEmployeeOpsIds(ids),
      );
    } on DioException catch (e) {
      _log('notification-prefs (PUT employeeOpsIds)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحفظ', ids: null);
    } catch (e) {
      _log('notification-prefs (PUT employeeOpsIds)', e);
      return (ok: false, message: 'تعذّر الحفظ', ids: null);
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
