import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/employees_api.dart';

/// عنوان موحّد للتحقّق من صلاحيات العامل الحالي (admin أو employee).
///
///  • للـadmin (الذي سجّل بـ SAS4 token مباشرة): كل الصلاحيات true.
///  • للـemployee: نُخزّن الـ`permissions` map من
///    `/api/v2/employees/me` بعد تسجيل الدخول، ونقرأها هنا
///    synchronous من الـcache في الذاكرة.
///
/// كل شاشة/زر يستهلكها بـ`Perms.has('subscribers.view')` ويُخفي
/// نفسه إذا رجعت false. لا errors، لا "تعذّر جلب" — يختفي بصمت.
class PermissionsService {
  PermissionsService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  // مفتاحان منفصلان: الـmap نفسه + flag يقول هل العامل employee أم
  // admin. الـflag يحدّد سلوك `has()` لو الـmap فارغ:
  //   admin (flag=0)   → كل شي مسموح (افتراضي)
  //   employee (flag=1) → كل شي ممنوع إلا الـكلمات الموجودة بالـmap
  static const _kEmployeePerms = 'perms.employee_map';
  static const _kIsEmployee = 'perms.is_employee';

  // الذاكرة الجارية — نقرأ منها مباشرةً، ونحدّثها عند save/load.
  static Map<String, bool>? _cached;
  static bool _isEmployee = false;
  static bool _loaded = false;
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  /// تنبيه لكل listener (مثلاً Widget في MainShell) لمّا تتغيّر
  /// الصلاحيات. كل setEmployee/clearEmployee يبَمب القيمة.
  static ValueListenable<int> get changes => _version;

  static bool get isLoaded => _loaded;
  static bool get isEmployee => _isEmployee;

  /// يُستدعى مرّة واحدة عند بدء التشغيل (main / Splash). يقرأ
  /// المخزّن في الـsecure storage ويحمّله للذاكرة.
  static Future<void> init() async {
    if (_loaded) return;
    try {
      final flag = await _storage.read(key: _kIsEmployee);
      _isEmployee = flag == '1';
      final raw = await _storage.read(key: _kEmployeePerms);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map) {
          _cached = {
            for (final e in j.entries) e.key.toString(): e.value == true,
          };
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PermissionsService.init failed: $e');
    } finally {
      _loaded = true;
    }
  }

  /// يُستدعى بعد تسجيل الدخول (login_screen.dart) لجلب الصلاحيات من
  /// `/api/v2/employees/me` وحفظها. لو الـadmin (مو موظف) ينظّف
  /// الـcache + flag (employee=false → كل شي مسموح).
  ///
  /// يرجع `true` لو نجح الجلب وحُفظت الحالة، `false` لو فشلت الشبكة
  /// أو رجع response غير متوقّع. الـcaller (login flow) يستعملها ليقرر
  /// هل يكمل للـMainShell — لا نريد employee يدخل والـcache في حالة
  /// غير محدّدة (قد يرتفع لصلاحيات admin من بقايا جلسة سابقة).
  static Future<bool> refreshFromBackend() async {
    final me = await EmployeesApi.me();
    if (me == null) {
      // لا نُسقط الـcache الحالي — قد يكون فقط فشل شبكة. الـcaller يقرر.
      return false;
    }
    if (me.isEmployee && me.permissions != null) {
      await _saveEmployee(me.permissions!);
    } else {
      // admin = full access
      await _clearEmployee();
    }
    return true;
  }

  static Future<void> _saveEmployee(Map<String, bool> perms) async {
    _isEmployee = true;
    _cached = Map<String, bool>.from(perms);
    await Future.wait([
      _storage.write(key: _kIsEmployee, value: '1'),
      _storage.write(key: _kEmployeePerms, value: jsonEncode(perms)),
    ]);
    _version.value = _version.value + 1;
  }

  static Future<void> _clearEmployee() async {
    _isEmployee = false;
    _cached = null;
    await Future.wait([
      _storage.delete(key: _kIsEmployee),
      _storage.delete(key: _kEmployeePerms),
    ]);
    _version.value = _version.value + 1;
  }

  /// تُستدعى من فلو تسجيل الخروج (AuthStorage.clear). تمسح كل ما
  /// يخصّ هذا الـadmin/employee — لا نريد بقايا تظهر للحساب الجاي.
  static Future<void> clear() => _clearEmployee();

  /// الفحص الرئيسي. مفتاح واحد:
  ///   • الـadmin (is_employee = false) → دائماً true.
  ///   • الـemployee → true إذا الـmap عنده هذا الـkey = true.
  /// لو الـservice ما تُحمَّل بعد (init لم تُنفَّذ) → نسمح افتراضياً
  /// (failover للسماح أفضل من إخفاء كل شي بدون قصد).
  static bool has(String key) {
    if (!_loaded) return true;
    if (!_isEmployee) return true;
    return _cached?[key] == true;
  }

  /// true إذا الـactor يملك واحدة على الأقل من المفاتيح.
  /// useful للشاشات اللي تجمع أكثر من tab/زر.
  static bool hasAny(Iterable<String> keys) {
    if (!_loaded) return true;
    if (!_isEmployee) return true;
    for (final k in keys) {
      if (_cached?[k] == true) return true;
    }
    return false;
  }

  /// true إذا الـactor يملك كل المفاتيح. شدّة الفحص للحالات التي
  /// تحتاج صلاحيات متعدّدة (مثلاً تعديل وحذف معاً).
  static bool hasAll(Iterable<String> keys) {
    if (!_loaded) return true;
    if (!_isEmployee) return true;
    for (final k in keys) {
      if (_cached?[k] != true) return false;
    }
    return true;
  }
}

/// Alias قصيرة لتقصير الاستعمال:
///   Perms.has('subscribers.view')
typedef Perms = PermissionsService;
