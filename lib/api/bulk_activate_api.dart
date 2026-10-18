import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// حارس التجديد الجماعيّ — ما يقوله الخادم عن قدرة هذا المدير على تفعيل
/// دفعةٍ من المشتركين (البند: «حارس التفعيل الجماعيّ لكلّ الساسات»).
///
/// ── لماذا من الخادم ──────────────────────────────────────────────────
/// SAS4 بلا API جماعيّ: الساس نفسه وموقعنا وتطبيقنا يكرّرون `user/activate`
/// (رصيد) صفّاً صفّاً. والصلاحيّة التي تحكم ذلك في الساس (`prm_users_activate`
/// ومعها التفعيل من الرصيد `prm_users_activate_credit`) **لا يراها التطبيق**:
/// يراها الخادم من توكن الساس المحفوظ للمدير (وللموظّف: توكن مديره)، ويكاشها
/// عشر دقائق — للساس الأصل والساسات البعيدة معاً
/// (`server/bulkActivateGuard.js`). فمديرٌ يفعّل بالكارت وحده كان يفتح
/// الورقة ويضغط فيأخذ 403 فارغاً على كلّ صفّ.
///
/// ── «لا نعرف» ليست «ممنوع» ─────────────────────────────────────────
/// خادمٌ أقدم بلا المسار، أو مهلة، أو `code:'UNKNOWN'`/`checked:false` ⇒
/// [BulkActivateCapability.known] = false: الزرّ يبقى مفتوحاً كما كان،
/// والخادم يرفض الصفّ برمزه، والورقة تقف عند أوّل رفضٍ قاطع.
@immutable
class BulkActivateCapability {
  const BulkActivateCapability({
    required this.known,
    required this.allowed,
    this.code,
    this.message,
    this.maxBatch,
    this.prefetchConcurrency,
  });

  /// حكمٌ صريحٌ من الخادم؟ `false` = لا نعرف (فلا قفل).
  final bool known;

  /// يستطيع التجديد الجماعيّ؟ يُقرأ مع [known]: المجهول مسموحٌ دائماً.
  final bool allowed;

  /// رمز الحكم (`CARD_ONLY` · `NO_CREDIT` · `NO_ACTIVATE_PERMISSION` ·
  /// `NO_EMPLOYEE_PERMISSION` · `EL_BULK_UNSUPPORTED` · `OK` · `UNKNOWN`).
  final String? code;

  /// سبب المنع بالعربيّة كما كتبه الخادم.
  final String? message;

  /// أقصى عددٍ في الدفعة الواحدة (`limits.max_batch`).
  final int? maxBatch;

  /// كم جلباً مسبقاً متزامناً (`limits.prefetch_concurrency`).
  final int? prefetchConcurrency;

  static const unknown = BulkActivateCapability(known: false, allowed: true);

  /// ممنوعٌ بحكمٍ صريح من الخادم (لا بمجهول).
  bool get blocked => known && !allowed;

  static int? _posIntOrNull(Object? v) {
    if (v == null || v is bool) return null;
    final n = v is num ? v : num.tryParse(v.toString().trim());
    if (n == null || !n.isFinite || n < 1) return null;
    return n.floor();
  }

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// يقبل الجسم كلّه (`{success, data:{…}}`) أو `data` نفسها.
  ///
  /// ⚠️ لا منع إلّا بـ`supported: false` **صريحة** في حكمٍ فُحص فعلاً:
  /// غيابها، أو `null`، أو `checked:false`، أو `code:'UNKNOWN'`، أو ردٌّ ليس
  /// كائناً ⇒ مجهول. والحدود (`limits`) تُقرأ حتّى مع المجهول — الخادم يرسلها
  /// دائماً.
  static BulkActivateCapability fromJson(Object? raw) {
    if (raw is! Map) return unknown;
    final inner = raw['data'];
    final m = inner is Map ? inner : raw;
    final limits = m['limits'] is Map ? m['limits'] as Map : const {};
    // `limits.run_concurrency` لا يُقرأ: التفعيل نفسه واحدٌ تلو واحد دائماً
    // (كلوحة الساس والويب) — تفعيلان معاً على رصيدٍ واحد قد يتجاوزان فحصه.
    final maxBatch = _posIntOrNull(limits['max_batch']);
    final pre = _posIntOrNull(limits['prefetch_concurrency']);
    final s = m['supported'];
    final code = _str(m['code']);
    final unchecked = m['checked'] == false || code?.toUpperCase() == 'UNKNOWN';
    final known = s is bool && !unchecked;
    return BulkActivateCapability(
      known: known,
      allowed: known ? s : true,
      code: code,
      message: known && !s ? _str(m['reason'] ?? m['message']) : null,
      maxBatch: maxBatch,
      prefetchConcurrency: pre,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BulkActivateCapability &&
      other.known == known &&
      other.allowed == allowed &&
      other.code == code &&
      other.message == message &&
      other.maxBatch == maxBatch &&
      other.prefetchConcurrency == prefetchConcurrency;

  @override
  int get hashCode =>
      Object.hash(known, allowed, code, message, maxBatch, prefetchConcurrency);

  @override
  String toString() => 'BulkActivateCapability(known: $known, '
      'allowed: $allowed, code: $code, maxBatch: $maxBatch, '
      'prefetch: $prefetchConcurrency)';
}

/// `GET /api/v2/subscribers/bulk-activate/capability` — مع كاشٍ قصير في الذاكرة.
///
/// الخادم يكاش صلاحيّات الساس عشر دقائق (ويؤكّد الحكم السالب بقراءةٍ لا
/// تتجاوز دقيقة)؛ هنا خمس للمسموح ودقيقة للمقفل — منحُ الصلاحيّة في الساس
/// يفتح الزرّ سريعاً، والضغط على «تجديد» المقفل يعيد السؤال
/// ([recheckIfLocked]). ونداءٌ واحدٌ جارٍ يُشارَك بين من يطلبه معاً
/// (شريط التحديد والورقة). المجهول لا يُكاش (يُعاد السؤال في المرّة
/// التالية). ويُمسح مع كلّ جلسة (`SubscribersApi.clearAllCaches`) فلا يرث
/// مديرٌ حكمَ سابقه.
class BulkActivateApi {
  BulkActivateApi._();

  static const path = '/api/v2/subscribers/bulk-activate/capability';
  static const ttl = Duration(minutes: 5);

  /// عمر الحكم المقفل في الكاش — أقصر: لا يبقى الزرّ مقفلاً ربع ساعة بعد أن
  /// منحت الشركة الصلاحيّة.
  static const lockedTtl = Duration(minutes: 1);

  static final ValueNotifier<BulkActivateCapability?> _current =
      ValueNotifier<BulkActivateCapability?>(null);
  static DateTime? _at;
  static Future<BulkActivateCapability>? _inFlight;

  /// جيل الجلسة — ردٌّ سُئل عنه قبل [reset] يخصّ جلسةً انتهت فلا يُطبَّق.
  static int _gen = 0;

  /// آخر حكمٍ معروف (أو `null` قبل أوّل ردّ) — يستمع له شريط التحديد.
  static ValueListenable<BulkActivateCapability?> get listenable => _current;

  /// آخر حكمٍ في الكاش بلا نداء. `null` = لم يُسأل بعد.
  static BulkActivateCapability? get cached => _current.value;

  /// الحكم — من الكاش إن كان طازجاً، وإلّا من الخادم. لا يرمي أبداً:
  /// الفشل [BulkActivateCapability.unknown].
  static Future<BulkActivateCapability> capability({bool fresh = false}) {
    final at = _at;
    final hit = _current.value;
    if (!fresh &&
        hit != null &&
        at != null &&
        DateTime.now().difference(at) < (hit.blocked ? lockedTtl : ttl)) {
      return Future.value(hit);
    }
    final running = _inFlight;
    if (running != null) return running;
    final gen = _gen;
    final f = _fetch().then((cap) {
      if (gen != _gen) return BulkActivateCapability.unknown;
      // المجهول لا يُثبَّت: لا يزيح حكماً معروفاً، ولا يُعدّ طازجاً.
      if (cap.known) {
        _at = DateTime.now();
        _current.value = cap;
      } else if (_current.value == null) {
        _current.value = cap;
      }
      return cap;
    });
    _inFlight = f;
    f.whenComplete(() {
      if (identical(_inFlight, f)) _inFlight = null;
    });
    return f;
  }

  static Future<BulkActivateCapability> _fetch() async {
    try {
      final r = await ApiClient.dio.get<dynamic>(
        path,
        options: Options(
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
        ),
      );
      final status = r.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return BulkActivateCapability.unknown;
      }
      return BulkActivateCapability.fromJson(r.data);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🟡 bulk-activate capability: $e');
      return BulkActivateCapability.unknown;
    }
  }

  /// دفعةٌ رفضها الخادم أو الساس بصلاحيّة: الحكم المكاش قد يكون قديماً —
  /// السؤال التالي يذهب للخادم (والحكم الحاليّ يبقى معروضاً حتى يصل).
  static void invalidate() => _at = null;

  /// ضُغط «تجديد» المقفل بحكم الخادم: الحكم قد يكون أقدم من منح الصلاحيّة في
  /// الساس — يُسأل الخادم ثانيةً في الخلفيّة (والقفل وسببه يبقيان معروضين حتى
  /// يصل)؛ فإن صار مسموحاً انفتح الزرّ بلا خروجٍ ولا انتظار. لا شيء إن لم يكن
  /// القفل من الخادم (ايرث لنك لا تسأل أصلاً).
  static void recheckIfLocked() {
    if (_current.value?.blocked != true) return;
    unawaited(capability(fresh: true));
  }

  /// خروجٌ أو تبديل جلسة: لا حكم ولا نداءٌ جارٍ يُطبَّق بعده.
  static void reset() {
    _gen++;
    _at = null;
    _inFlight = null;
    _current.value = null;
  }

  @visibleForTesting
  static void debugSet(BulkActivateCapability? cap) {
    _gen++;
    _inFlight = null;
    _current.value = cap;
    _at = cap == null ? null : DateTime.now();
  }

  /// يُقدِّم عمر الحكم المكاش [d] (لاختبار [ttl]/[lockedTtl] بلا انتظار).
  @visibleForTesting
  static void debugAge(Duration d) {
    final at = _at;
    if (at != null) _at = at.subtract(d);
  }
}
