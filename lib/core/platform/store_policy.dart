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
    // «… أو رقّ باقتك» / «… أو رقِّ باقتك لأجهزة أكثر» / «… أو رقّي باقتك»
    // (الأمر العراقيّ بالياء — رسائل المساعد الذكيّ: «خلصت أسئلة اليوم — ترجع
    // باچر أو رقّي باقتك»؛ كانت تفلت من القاعدة والفحص معاً).
    (RegExp('\\s*أو\\s*رق$_shadda(?:ي)?\\s*باقت(?:ك|كم)(?:\\s*لأجهزة\\s*أكثر)?'), ''),
    // «… — رقِّ باقتك لإضافة المزيد» / «… — رقّي باقتك…»
    (RegExp('\\s*[—–-]\\s*رق$_shadda(?:ي)?\\s*باقت(?:ك|كم)[^—\\n.]*'), ''),
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
    'رق$_shadda(?:ي)?\\s*باق|ترقي[ةه]\\s*(?:ال)?باق|فع$_shaddaل$_shadda\\s*كود'
    r'|\bupgrade\b|\bbuy\b|\bpurchase\b',
    caseSensitive: false,
  );

  /// نصٌّ آمنٌ للعرض في نسخة آيفون — كما هو على غيرها.
  static String storeSafe(String message) {
    if (!hidePurchaseFlows || message.isEmpty) return message;
    final out = _scrub(message);
    // لا يبقى شيءٌ مفهوم ← رسالةٌ محايدة بدل فراغ.
    return out.isEmpty ? 'تعذّر إتمام العمليّة' : out;
  }

  /// كـ[storeSafe] لسطرٍ **ضمن نصٍّ أطول** (عنوان جواب المساعد، خطوةٌ منه):
  /// ما لا يبقى منه شيءٌ يُسقَط — نصٌّ فارغ — بدل الجملة المحايدة.
  static String storeSafeLine(String line) {
    if (!hidePurchaseFlows || line.isEmpty) return line;
    return _scrub(line);
  }

  // ── أجوبة المساعد الذكيّ وحدها (مرآة IOS_CTA/IOS_CTA_WEAK في
  // server/ai/sanitize.js) ──
  // النموذج يصوغ بكلامه، فالدعوة تأتي بصيغٍ لا تكتبها رسائل الخادم: «كود
  // تفعيل من فريق MyServices»، «تواصل معنا لزيادة الحدّ»، «اشترك بالباقة
  // الأعلى»، «جدّد اشتراكك». قواعدٌ منفصلة عن [_cta] — رسائل الخادم عن كارت
  // مشترك فيها «كود التفعيل» تبقى كما هي.
  static const _aiSh = '[\u064B-\u0652]*';

  /// دعوةٌ صريحة أينما وردت.
  static final RegExp _aiCta = RegExp(
    'رق$_aiShي?\\s*باق|ترقي[ةه]\\s*(?:ال)?باق|فع$_aiShل$_aiSh\\s*(?:ال)?كود'
    '|تفعيل\\s*(?:ال)?كود|كود\\s*(?:ال)?تفعيل\\s*(?:من|لحساب|للحساب|حسابك|للاشتراك|الاشتراك)'
    '|(?:اطلب|احصل|خذ|تاخذ)\\S*\\s+كود\\s*(?:ال)?تفعيل|فريق\\s*MyServices'
    r'|\bupgrade\b|\bbuy\b|\bpurchase\b|\bsubscribe\b',
    caseSensitive: false,
    unicode: true,
  );

  /// دعوةٌ بسياق حساب النظام فقط — لا تُعدّ إن كانت الجملة عن المشترك أو
  /// كارته (تجديد اشتراك المشترك، باقةٌ أعلى له).
  static final RegExp _aiCtaWeak = RegExp(
    [
      'اشتر$_aiSh(?:ي|ك$_aiSh(?:ت|وا|ي)?)?\\s+(?:ب|في\\s+)?(?:ال)?باق',
      'باق[ةه]\\s*(?:ال)?أعلى',
      'باق[ةه]\\s+(?:ال)?(?:احترافي|أعمال|متوسط|أساسي)',
      'زياد[ةه]\\s*(?:ال)?حد',
      '(?:ن|ت|ي)زيد\\s+(?:لك\\s+|لكم\\s+)?(?:ال)?حد',
      '(?:ي|ت|ن)?جد$_aiShد$_aiSh\\s+(?:ال)?اشتراك(?:ك|كم)?',
      'تجديد\\s+(?:ال)?اشتراك(?:ك|كم)?',
      'كود\\s*(?:ال)?تفعيل',
    ].join('|'),
    unicode: true,
  );
  static final RegExp _subscriberCtx = RegExp('مشترك|كارت|كرت');
  static final RegExp _aiSplit = RegExp(r'—|(?<=[.!؟?])\s+|\n+');

  static bool _isAiCta(String s) =>
      _aiCta.hasMatch(s) || (_aiCtaWeak.hasMatch(s) && !_subscriberCtx.hasMatch(s));

  /// كـ[storeSafeLine] لسطرٍ من **جواب المساعد الذكيّ** (عنوان، نصّ، خطوة،
  /// ميزةٌ ذات صلة): فوق قواعد رسائل الخادم، تُحذف كلّ جملةٍ تدعو لشراء
  /// اشتراك النظام أو ترقيته أو تفعيله بكود أو «زيادة الحدّ» — وتبقى جمل عمل
  /// المشتركين («جدّد اشتراك المشترك»، «كود التفعيل المطبوع على الكارت»).
  static String assistantSafeLine(String line) {
    if (!hidePurchaseFlows || line.isEmpty) return line;
    var out = _scrub(line);
    if (_isAiCta(out)) {
      out = out
          .split(_aiSplit)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_isAiCta(s))
          .join(' ');
    }
    return out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// اشتراك **الحساب** أو حدوده بكلام المدير أو الخطأ: «باقتي/اشتراكك»،
  /// «الحدّ الأقصى»، «زيادة الحدّ»، «حدّ الموظّفين/الأجهزة/الصفحات/الشركات»،
  /// الترقية… — لا كلام المشترك («باقة المشترك»، «اشتراكه»).
  static final RegExp _planCtx = RegExp(
    [
      '(?<![\\p{L}])[وفبلك]?(?:ال|لل)?حد$_aiSh\\s*(?:ال)?[أا]قصى',
      'زياد[ةه]\\s*(?:ال)?حد',
      '(?<![\\p{L}])[أانتي]زيد\\s+(?:لي\\s+|لك\\s+|لكم\\s+)?(?:ال)?حد',
      '(?<![\\p{L}])[وفبلك]?(?:ال|لل)?حد$_aiSh\\s*(?:ال)?(?:أجهز|اجهز|موظ|صفح|شركات)',
      'باقت$_aiSh(?:ي|ك|كم|نا)(?![\\p{L}])',
      'اشتراك$_aiSh(?:ي|ك|كم|نا)(?![\\p{L}])',
      'ترقي[ةه]',
      r'\b(?:upgrade|plan|subscription|limit)s?\b',
    ].join('|'),
    caseSensitive: false,
    unicode: true,
  );

  /// على آيفون: نصٌّ (سؤال المدير أو الخطأ الذي يُشرح) في سياق اشتراك الحساب
  /// أو باقته أو حدوده — فلا «تواصل ويّا الدعم» تحت جوابه: يُقرأ تواصلاً
  /// للشراء خارج المتجر (3.1.1). يشمل دعوات [assistantSafeLine] نفسها.
  /// غير آيفون: `false` دائماً.
  static bool isAccountPlanContext(String text) {
    if (!hidePurchaseFlows || text.trim().isEmpty) return false;
    return _isAiCta(text) || _planCtx.hasMatch(text);
  }

  static String _scrub(String message) {
    var out = message;
    for (final (re, rep) in _rules) {
      out = out.replaceAll(re, rep);
    }
    if (_cta.hasMatch(out)) {
      final parts = out.split('—').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final kept = parts.where((s) => !_cta.hasMatch(s)).toList();
      out = kept.isNotEmpty ? kept.join(' — ') : '';
    }
    return out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
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
