import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/account_api.dart';
import 'employee_session.dart';
import 'permissions_service.dart';

/// شركات حساب Pro المربوطة («شركاتي») داخل التطبيق — لزرّ «تبديل الشركة» في
/// ترويسة الرئيسيّة وورقته.
///
/// النداء نفسه الذي تقرأ به «شركاتي» قائمتها (`GET /api/account/companies`
/// بتوكن الحساب، [AccountApi.companies]) — لا مسار جديد. يُجلب مرّةً للجلسة
/// (ويُجدَّد بعد [freshFor]، وعند فتح الورقة)، ويُمسح مع الجلسة ([reset] من
/// `SessionManager`) فلا يرى الحساب التالي شركات سابقه، ولا يُطلب أصلاً لموظّف.
class LinkedCompanies {
  LinkedCompanies._();

  /// آخر قائمةٍ وصلت، و`null` = لم تُعرف بعد (أو مُسحت مع الجلسة).
  static final ValueNotifier<List<LinkedCompany>?> items =
      ValueNotifier<List<LinkedCompany>?>(null);

  /// القائمة طازجةٌ هذه المدّة — العودة للتطبيق بعدها تعيد السؤال.
  static const freshFor = Duration(minutes: 10);

  /// بعد فشلٍ لا يُعاد السؤال قبل هذه المدّة (لا حلقة طلباتٍ بلا شبكة).
  static const retryAfter = Duration(seconds: 30);

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<List<LinkedCompany>>? _inFlight;

  /// جيل الجلسة: ردٌّ يصل بعد [reset] (تبديل شركة، خروج) لا يُكتب.
  static int _generation = 0;

  /// المالك وحده — لا موظّف ساس ولا موظّف ايرث لنك مباشر (بلا حساب أصلاً).
  static bool get ownerSession =>
      !PermissionsService.isEmployee && !EmployeeSession.isActive;

  /// يظهر الزرّ: جلسة مالكٍ، وللحساب شركتان مربوطتان فأكثر.
  static bool get switcherVisible =>
      ownerSession && (items.value?.length ?? 0) >= 2;

  /// للترويسة: يسأل إن لم تكن القائمة طازجة. لا يرمي، ولا يُرسل لموظّف.
  static Future<void> ensureFresh() async {
    if (!ownerSession) return;
    final t = now();
    final at = _fetchedAt;
    if (at != null && t.difference(at) < freshFor) return;
    final failed = _failedAt;
    if (failed != null && t.difference(failed) < retryAfter) return;
    try {
      await load();
    } catch (_) {/* تبقى آخر قائمةٍ معروفة — والزرّ كما كان */}
  }

  /// للورقة: يسأل الآن (طلبٌ واحدٌ جارٍ على الأكثر) ويرمي عند الفشل.
  static Future<List<LinkedCompany>> load() {
    final running = _inFlight;
    if (running != null) return running;
    final gen = _generation;
    late final Future<List<LinkedCompany>> request;
    request = AccountApi.companies().then((list) {
      if (gen == _generation) {
        items.value = List<LinkedCompany>.unmodifiable(list);
        _fetchedAt = now();
        _failedAt = null;
      }
      return list;
    }, onError: (Object e, StackTrace st) {
      if (gen == _generation) _failedAt = now();
      Error.throwWithStackTrace(e, st);
    }).whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
    _inFlight = request;
    return request;
  }

  /// من `SessionManager.clearAllSessionData` — خروجٌ أو تبديل شركة.
  static void reset() {
    _generation++;
    _inFlight = null;
    _fetchedAt = null;
    _failedAt = null;
    items.value = null;
  }
}
