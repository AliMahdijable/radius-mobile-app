import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_storage.dart';

/// الحساب المعروف ببطء قائمته (١٤ نوفمبر ٢٠٢٦ — المالك: «أوّل ٥٠ مشتركاً حيّين خلال ٣–٥ث والباقي وراهم»، ⛔ لا نسخة قديمة).
///
/// متى أخذت القائمة الكاملة [slowAfter] فأكثر، أو انقضت مهلتها، يُحفظ للحساب **عدد مشتركيه وحده** — لا صفّ ولا رقم مال — فيفتح في
/// المرّة القادمة تدريجيّاً من أوّل لحظة: الصفحة الأولى حيّةً من الساس والقائمة الكاملة معاً، بلا انتظار «هل الحساب كبير؟» ولا
/// مهلة الشاشة (١٫٢ث). قائمةٌ تصل بأقلّ من [fastUnder] تمسحه. لا يُعرض منه شيء: يحسم ترتيب الطلبات وحده.
///
/// قِيس على «فايبر لنك كربلاء» (٦١٨ مشتركاً): ٥٠ صفّاً ٣٫٧ث وحدها و٥٫٢ث مع القائمة الكاملة (٢٤٫٨ث)، والصفحة الأولى كانت تظهر بعد
/// ~١١ث (الفحص ثمّ ١٫٢ث ثمّ الصفحة واشتقاق الأسعار — الأخير صار بذاكرة الخادم في e466629).
class KnownSlowList {
  KnownSlowList._();

  static const slowAfter = Duration(milliseconds: 3000);
  static const fastUnder = Duration(milliseconds: 1500);

  /// دونه الحساب «صغير» يجوز طلب قائمته الكاملة بلا فحص — كحدّ الكبير (BigSubscribersApi.threshold).
  static const bigAt = 5000;
  static const _key = 'subs_known_slow_v1';
  static const _ttl = Duration(days: 7);
  static const _max = 30;

  /// المدير الحاليّ (للاختبار: يُستبدل).
  static Future<String?> Function() adminId = AuthStorage.readAdminId;

  /// الوقت (للاختبار: يُستبدل).
  static DateTime Function() now = DateTime.now;

  static Future<Map<String, dynamic>> _readAll(SharedPreferences p) async {
    try {
      final raw = p.getString(_key);
      final o = raw == null ? null : jsonDecode(raw);
      return o is Map<String, dynamic> ? o : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// عدد مشتركي الحساب الحاليّ إن عُرف ببطء قائمته (صغيرٌ دون [bigAt]، خلال ٧ أيّام)، وإلّا null. لا يرمي.
  static Future<int?> size() async {
    try {
      final id = await adminId();
      if (id == null || id.isEmpty) return null;
      final p = await SharedPreferences.getInstance();
      final e = (await _readAll(p))[id];
      if (e is! Map) return null;
      final n = e['size'];
      final at = e['at'];
      final size = n is num ? n.toInt() : null;
      final atMs = at is num ? at.toInt() : null;
      if (size == null || size <= 0 || size >= bigAt || atMs == null) return null;
      if (now().millisecondsSinceEpoch - atMs > _ttl.inMilliseconds) return null;
      return size;
    } catch (_) {
      return null;
    }
  }

  /// زمن وصول القائمة الكاملة ([took]؛ null = لم تصل في وقتها) ⇒ الحساب يُحفظ بطيئاً أو يُمسح. [count] عدد مشتركيه. لا يرمي.
  static Future<void> note(Duration? took, int count) async {
    try {
      final id = await adminId();
      if (id == null || id.isEmpty) return;
      final p = await SharedPreferences.getInstance();
      final all = await _readAll(p);
      if (took == null || took >= slowAfter) {
        if (count <= 0 || count >= bigAt) return;
        all[id] = {'size': count, 'at': now().millisecondsSinceEpoch};
      } else if (took < fastUnder) {
        if (!all.containsKey(id)) return;
        all.remove(id);
      } else {
        return; // بينهما: لا تغيير (لا تأرجح عند الحدّ)
      }
      if (all.length > _max) {
        int atOf(Object? v) => v is Map && v['at'] is num ? (v['at'] as num).toInt() : 0;
        final keys = all.keys.toList()..sort((a, b) => atOf(all[a]).compareTo(atOf(all[b])));
        for (final k in keys.take(all.length - _max)) {
          all.remove(k);
        }
      }
      await p.setString(_key, jsonEncode(all));
    } catch (_) {
      // التخزين تعذّر ⇒ كما كان (المهلة ١٫٢ث في الشاشة)
    }
  }
}
