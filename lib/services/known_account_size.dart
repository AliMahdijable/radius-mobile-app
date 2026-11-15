import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/company_route.dart';
import 'auth_storage.dart';
import 'permissions_service.dart';

/// ما يعرفه الجهاز عن حجم الحساب من آخر فحص «هل الحساب كبير؟» — [KnownAccountSize.small].
class KnownSize {
  const KnownSize({required this.size, required this.paged, required this.age});

  /// عدد مشتركي الحساب كما أعاده الفحص (٠ لحسابٍ لا يرقّم: ايرث لنك/FTTH…).
  final int size;

  /// الخادم يرقّم قائمة هذا الحساب (ساس فور). غير المرقَّم لا يكون «كبيراً» أبداً.
  final bool paged;

  /// عمر الحكم.
  final Duration age;
}

/// حكم «حجم الحساب» على هذا الجهاز (١٦ نوفمبر ٢٠٢٦ — المالك: «ابدأ بالأول والثاني وسوي محاكاة بحيث تضمن دقه المعلومات والسرعه»).
///
/// قِيس على المحاكي (admin@popq): كلّ فتحٍ للتطبيق كان يسأل الساس «هل الحساب كبير؟» (صفٌّ واحد، `?page=1&size=1`) **قبل**
/// قائمة المشتركين — ٠٫٢ث والساس دافئ و~٣ث حين يبرد (٨٣٥ مرّة لـ٢٩٢ وكيلاً يوم ١٥ نوفمبر، ٨٠٣ منها سوبرنت) — ثمّ القائمة
/// نفسها ~٣ث أخرى، والرئيسيّة كلّها تنتظرهما. الحكم كان يُحفظ بالذاكرة ١٠ دقائق فيضيع مع كلّ إغلاقٍ للتطبيق.
///
/// يُحفظ هنا **حكم الحجم وحده** — عددٌ لا صفّ ولا مال، ولا يُعرض منه شيء (يحسم ترتيب الطلبات كـKnownSlowList): الحساب الصغير
/// بهامشٍ واسع ([smallUnder] = ٨٠٪ من حدّ الكبير) يذهب للقائمة **الحيّة** فوراً، ويتجدّد الحكم في الخلفيّة كلّ [refreshAfter]. الكبير،
/// والقريب من الحدّ، وغير المعروف، والأقدم من [ttl]: الفحص قبل القائمة كما كان حرفاً.
///
/// المفتاح: المدير + الدور (مدير/موظّف) + اسم الدخول — حكم الموظّف المقيَّد لا يُستعمل لمديره ولا العكس.
class KnownAccountSize {
  KnownAccountSize._();

  /// حدّ الحساب الكبير — = BigSubscribersApi.threshold (اختبار big_subscribers يحرس التساوي).
  static const bigAt = 5000;

  /// دونه الحساب «صغير» يجوز طلب قائمته الحيّة بلا انتظار الفحص — هامش ألف مشتركٍ قبل الكبير: لا يبلغ حسابٌ الحدّ بين فتحين.
  static const smallUnder = 4000;

  /// أقدم حكمٍ يُعتمد — بعده يُسأل الساس قبل القائمة.
  static const ttl = Duration(days: 7);

  /// حكمٌ أقدم من هذا يُجدَّد في الخلفيّة (لا ينتظره أحد).
  static const refreshAfter = Duration(hours: 6);

  static const storeKey = 'subs_known_size_v1';
  static const _max = 30;

  /// منافذ الاختبار.
  static Future<String?> Function() adminId = AuthStorage.readAdminId;
  static Future<String?> Function() loginName = AuthStorage.readAdminUsername;
  static bool Function() isEmployee = () => PermissionsService.isEmployee;
  static DateTime Function() now = DateTime.now;

  /// شركة النداء الموجَّه الحاليّ («كل الشركات»، [CompanyRoute.currentKey]) — null خارج أيّ توجيه.
  static String? Function() routedKey = () => CompanyRoute.currentKey;

  /// مفتاح الحساب الحاليّ — يُؤخذ **قبل** الطلب ويُمرَّر لـ[note]/[noteList]: ردٌّ يصل بعد تبديل الشركة يُكتب لحسابه لا للجديد.
  /// داخل نداءٍ موجَّه لشركةٍ أخرى ⇒ null: ليس حساب الجلسة، فلا يُقرأ له حكمها ولا يُكتب جوابه باسمها (حكم «صغير» لشركةٍ
  /// مُضافة لو كُتب لحسابٍ كبيرٍ مفتوح لطلب قائمته الكاملة).
  static Future<String?> currentKey() async {
    if (routedKey() != null) return null;
    final id = await adminId();
    if (id == null || id.isEmpty) return null;
    final name = (await loginName()) ?? '';
    return '$id|${isEmployee() ? 'e' : 'm'}|$name';
  }

  static Map<String, dynamic> _readAll(SharedPreferences p) {
    try {
      final raw = p.getString(storeKey);
      final o = raw == null ? null : jsonDecode(raw);
      return o is Map<String, dynamic> ? o : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// حكم الحساب الحاليّ إن كان «صغيراً» يجوز معه تخطّي الفحص: مرقَّمٌ دون [smallUnder]، أو غير مرقَّم — خلال [ttl]. وإلّا null
  /// (كبير، قريبٌ من الحدّ، مجهول، قديم، تخزينٌ معطوب) ⇒ يُسأل الساس كما كان. لا يرمي.
  static Future<KnownSize?> small() async {
    try {
      final key = await currentKey();
      if (key == null) return null;
      final p = await SharedPreferences.getInstance();
      final e = _readAll(p)[key];
      if (e is! Map) return null;
      final size = e['size'];
      final paged = e['paged'];
      final at = e['at'];
      if (size is! num || paged is! bool || at is! num) return null;
      final n = size.toInt();
      if (n < 0) return null;
      if (paged && n >= smallUnder) return null;
      final age = now().millisecondsSinceEpoch - at.toInt();
      if (age < 0 || age > ttl.inMilliseconds) return null;
      return KnownSize(size: paged ? n : 0, paged: paged, age: Duration(milliseconds: age));
    } catch (_) {
      return null;
    }
  }

  /// نتيجة فحصٍ **ناجح** من الخادم (`success: true`) — تُحفظ كما هي، كبيراً كان أو صغيراً: الكبير لا يُختصر به أبداً، لكنّه يمحو
  /// «صغيراً» أقدم. الفحص الفاشل لا يُكتب (لا يُعدّ حسابٌ «لا يرقّم» لأنّ ساسه تعطّل لحظتها). لا يرمي.
  /// [key] من [currentKey] لحظة بدء الفحص.
  static Future<void> note({required String? key, required int total, required bool paged}) async {
    try {
      if (key == null) return;
      final p = await SharedPreferences.getInstance();
      final all = _readAll(p);
      all[key] = {'size': paged ? total : 0, 'paged': paged, 'at': now().millisecondsSinceEpoch};
      if (all.length > _max) {
        int atOf(Object? v) => v is Map && v['at'] is num ? (v['at'] as num).toInt() : 0;
        final keys = all.keys.toList()..sort((a, b) => atOf(all[a]).compareTo(atOf(all[b])));
        for (final k in keys.take(all.length - _max)) {
          all.remove(k);
        }
      }
      await p.setString(storeKey, jsonEncode(all));
    } catch (_) {
      // التخزين تعذّر ⇒ الفحص قبل القائمة كما كان
    }
  }

  /// القائمة الكاملة وصلت بـ[count] صفّاً: إن قاربت الحدّ ([smallUnder] فأكثر) يُمحى الحكم فيُسأل الساس قبل القائمة في الفتح
  /// القادم — حسابٌ نما يرجع للمسار الحذر بعد فتحٍ واحد. لا يرمي.
  /// [key] من [currentKey] لحظة بدء طلب القائمة.
  static Future<void> noteList(int count, {required String? key}) async {
    if (count < smallUnder || key == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final all = _readAll(p);
      if (all.remove(key) == null) return;
      await p.setString(storeKey, jsonEncode(all));
    } catch (_) {}
  }
}
