import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// سياسة المتجر — ما يُخفى في نسخة آيفون (App Store 3.1.1 / 3.1.3).
///
/// حساب Pro يُفعَّل من لوحة المالك لا من التطبيق، فنسخة آيفون لا تعرض: إدخال
/// كود التفعيل، ولا أيّ سعرٍ أو باقةٍ للشراء، ولا «رقِّ باقتك»، ولا «فعّل كوداً»،
/// ولا رابط تواصلٍ في سياق انتهاء الاشتراك. تعرض الحالة وحدها (فعّال/تجربة/
/// منتهٍ + التاريخ). أندرويد والويب كما هما.
class StorePolicy {
  StorePolicy._();

  /// للاختبارات فقط: يفرض النتيجة بدل المنصّة الفعليّة.
  @visibleForTesting
  static bool? debugHidePurchaseFlows;

  /// آيفون (وآيباد) = تُخفى مسارات الشراء/التفعيل/الترقية.
  static bool get hidePurchaseFlows => debugHidePurchaseFlows ?? (!kIsWeb && Platform.isIOS);

  // ── رسائل الخادم ──
  // الخادم نفسه يكتب رسائل فيها دعوةٌ للشراء («… أو رقّ باقتك»، «فعّل كوداً
  // للمتابعة»). على آيفون تُحذف الجملة الداعية وتبقى المعلومة.

  static const _shadda = '[ًَِّ]*'; // شدّة/كسرة/تنوين/فتحة في أيّ ترتيب

  static final List<(RegExp, String)> _rules = [
    // «انتهى اشتراكك — فعّل كوداً للمتابعة» ← «انتهى اشتراكك»
    (RegExp('\\s*[—–-]\\s*فع$_shaddaل$_shadda\\s*كود[ًا]*(?:\\s*جديد[ًا]*)?(?:\\s*للمتابعة)?'), ''),
    // «… أو رقّ باقتك» / «… أو رقِّ باقتك لأجهزة أكثر»
    (RegExp('\\s*أو\\s*رق$_shadda\\s*باقت(?:ك|كم)(?:\\s*لأجهزة\\s*أكثر)?'), ''),
    // «… — رقِّ باقتك لإضافة المزيد»
    (RegExp('\\s*[—–-]\\s*رق$_shadda\\s*باقت(?:ك|كم)[^—\\n.]*'), ''),
    // «في باقتك (3)» ← «(3)» — ذكر الباقة في سياق الحدّ
    (RegExp('\\s*في\\s*باقت(?:ك|كم)'), ''),
    // «باقتك تسمح بـ…» ← «حسابك يسمح بـ…»
    (RegExp('باقت(?:ك|كم)\\s*تسمح'), 'حسابك يسمح'),
  ];

  /// جملةٌ ما تزال تدعو للشراء/الترقية/التفعيل بعد القواعد — تُحذف قطعتها
  /// (القطع مفصولة بـ«—»). خاصّةٌ بحساب Pro وحده: لا «تجديد» ولا «اشتراك» ولا
  /// «كود التفعيل»، لأنّها من عمل المشتركين (كارتات مزوّد الإنترنت) — رسالةٌ مثل
  /// «كود التفعيل غير صحيح» عن كارت مشترك تبقى كما هي.
  static final RegExp _cta = RegExp(
    'رق$_shadda\\s*باق|ترقي[ةه]\\s*(?:ال)?باق|فع$_shaddaل$_shadda\\s*كود'
    r'|\bupgrade\b|\bbuy\b|\bpurchase\b',
    caseSensitive: false,
  );

  /// نصٌّ آمنٌ للعرض في نسخة آيفون — كما هو على غيرها.
  static String storeSafe(String message) {
    if (!hidePurchaseFlows || message.isEmpty) return message;
    var out = message;
    for (final (re, rep) in _rules) {
      out = out.replaceAll(re, rep);
    }
    if (_cta.hasMatch(out)) {
      final parts = out.split('—').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final kept = parts.where((s) => !_cta.hasMatch(s)).toList();
      out = kept.isNotEmpty ? kept.join(' — ') : '';
    }
    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    // لا يبقى شيءٌ مفهوم ← رسالةٌ محايدة بدل فراغ.
    return out.isEmpty ? 'تعذّر إتمام العمليّة' : out;
  }
}

/// يمرّر `message` في ردود الخادم (نجاحاً وخطأً) عبر [StorePolicy.storeSafe]
/// على آيفون — فلا تصل جملة «رقِّ باقتك» إلى أيّ شاشةٍ تعرض رسالة الخادم كما
/// هي. على غير آيفون لا يلمس شيئاً.
///
/// يُسجَّل في عملاء Dio (`ApiClient._buildDio`، `AccountApi._dio`):
/// `d.interceptors.add(StoreSafeMessagesInterceptor());`
class StoreSafeMessagesInterceptor extends Interceptor {
  StoreSafeMessagesInterceptor();

  static void _scrub(Object? data) {
    if (!StorePolicy.hidePurchaseFlows || data is! Map) return;
    try {
      final m = data['message'];
      if (m is String && m.isNotEmpty) data['message'] = StorePolicy.storeSafe(m);
    } catch (_) {/* خريطةٌ غير قابلة للتعديل — تبقى كما هي */}
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _scrub(response.data);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _scrub(err.response?.data);
    handler.next(err);
  }
}
