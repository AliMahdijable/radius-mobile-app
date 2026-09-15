import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/dashboard_api.dart';
import 'auth_storage.dart';

/// آخر قيمةٍ معروفة لكارت المحفظة، تُرسم فور الإقلاع البارد بينما النداء
/// الحيّ في طريقه — فيرى المدير رقماً بدل دوّارة.
///
/// ── ما يُخزَّن ولا شيء سواه ───────────────────────────────────────
/// رقمان: `balance` و`points`. المدينون وقائمة التفعيلات أثقل وأسرع
/// بياتاً فتبقى بلا قرص. ولا عمرَ مفروضاً هنا **عمداً**: النداء الحيّ
/// يُطلق في الإطار نفسه، فعمر الرقم المعروض ثوانٍ لا أيّام.
///
/// ── الختم: ولمَ لا يكفي المسح عند الخروج ─────────────────────────
/// الحزام الأوّل هو `SessionManager.clearAllSessionData` — يُنادي
/// `clear()` هنا، ومنتظَراً، عند كلّ تبدّل هويّة يمرّ بالتطبيق: خروجٌ
/// يدويّ · طردُ 401/403 · تسجيل دخول · تبديل حساب والعودة منه.
///
/// ⚠️ لكنّ مساراً واحداً **لا يمرّ بالتطبيق أصلاً**: `AuthStorage` تضع
/// `synchronizable: true`، فهويّةُ مديرٍ سجّل دخوله على جهازٍ آخر تصل
/// إلى هذا الجهاز عبر iCloud Keychain بلا خروجٍ ولا دخول — ولا شيء
/// يمسح تفضيلات هذا الجهاز، وهي لا تُزامَن معها. فالرقم الباقي يصير
/// رصيدَ مديرٍ يُعرض لمديرٍ آخر حتّى يردّ النداء الحيّ.
///
/// فالختم حزامٌ ثانٍ: `adminId` داخل الحمولة، يُقارَن عند القراءة
/// وتُمسح عند الاختلاف. وثمنه قراءةُ مفتاحٍ ومقارنةُ نصّين — وهو نفس
/// ما يفعله `SubscribersOfflineCache` لحمولته الأثقل.
///
/// والمعرّف يأتي كما أرسله الخادم، فيرث التأهيل تلقائيّاً حين يُضاف
/// ساسٌ ثانٍ: `"2"` للساس الأصليّ و`"krb:2"` لغيره لا يتصادمان
/// (`server/sasIdentity.js`).
///
/// ⚠️ وحمولةٌ بلا ختم — أي المكتوبة قبل هذا التغيير — تُرمى ولا
/// تُترقّى: لا سبيل لنسبتها إلى مديرٍ بعد كتابتها. ثمنُها دوّارةٌ
/// واحدة في أوّل إقلاعٍ بعد التحديث.
class DashboardCache {
  DashboardCache._();

  /// ⚠️ مفتاحان متروكان لا يُكتبان — يبقى اسماهما ليمسحهما `clear()`
  /// من أجهزةٍ كتبتهما قبل الحذف:
  ///   • `sas4`: إحصاءات الساس المباشرة حُذفت (2026-08-31 `a58acd7`
  ///     نداءً، و2026-09-15 صنفاً).
  ///   • `revenue`: لم يُنادِ `HeroRevenueCard` قطّ دالّتَي الإيراد —
  ///     كان يجلب حيّاً دائماً. حُذفت الدالّتان 2026-09-15 لأنّ الكود
  ///     الميّت يكذب: مراجعةٌ قرأت المفتاح فعدّته حمولةً تُكتب بلا ختم.
  static const _kSas4Legacy = 'dash.cache.sas4';
  static const _kRevenueLegacy = 'dash.cache.revenue';

  static const _kWallet = 'dash.cache.wallet';

  /// Read + save operations use SharedPreferences.getInstance() which is
  /// async on first call but cached on subsequent — so all reads after
  /// the first are effectively O(1).

  static Future<void> saveWallet(WalletResult w) async {
    final adminId = await AuthStorage.readAdminId();
    // بلا هويّةٍ لا نكتب: حمولةٌ لا تُنسب لأحدٍ لا يجوز أن تُقرأ لأحد.
    if (adminId == null || adminId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kWallet,
      jsonEncode({'v': 1, 'adminId': adminId, 'w': w.toJson()}),
    );
  }

  static Future<WalletResult?> readWallet() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null || adminId.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kWallet);
    if (raw == null) return null;
    final w = decodeFor(raw, adminId);
    // ختمٌ مخالف أو حمولةٌ تالفة: تُمسح فلا تُقرأ ثانيةً في هذه الجلسة
    // ولا في التي بعدها.
    if (w == null) await p.remove(_kWallet);
    return w;
  }

  /// فكّ الغلاف مع فحص الختم — مفصولٌ عن [readWallet] لأنّ `AuthStorage`
  /// و`SharedPreferences` تمرّان بقنواتٍ أصليّة، والمنطق الذي يحرس عزل
  /// المدراء يجب أن يكون مُختبَراً بلا منصّة.
  @visibleForTesting
  static WalletResult? decodeFor(String raw, String adminId) {
    if (adminId.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      if (j['adminId']?.toString() != adminId) return null;
      final w = j['w'];
      if (w is! Map) return null;
      return WalletResult.fromJson(Map<String, dynamic>.from(w));
    } catch (_) {
      return null;
    }
  }

  /// Wipes all cached KPIs — call on logout so the next login doesn't
  /// briefly flash the previous admin's numbers.
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.remove(_kSas4Legacy),
      p.remove(_kRevenueLegacy),
      p.remove(_kWallet),
    ]);
  }
}
