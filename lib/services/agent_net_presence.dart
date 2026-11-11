import 'package:flutter/foundation.dart';

/// «هل الموبايل على شبكة الوكيل؟» — حالٌ واحدة يشترك فيها قسما المشتركين والأجهزة (٥ نوفمبر — المالك: «من يتحسس النظام هو مو ضمن
/// الشبكة… البينج مو ناصي… يطلع له فد هنت صغير»؛ ثمّ «فكر باحترافيه اكثر»).
///
/// القواعد:
/// * العناوين **الخاصّة** وحدها تقرّر (10/8 · 172.16/12 · 192.168/16 · 100.64/10): جهازٌ بعنوانٍ عامّ يردّ من أيّ مكان (راوترٌ ظاهر على
///   الإنترنت) فلا يدلّ على شبكة الوكيل — كان يكفي جهازٌ عامّ واحد ليقال «على شبكتك».
/// * ردٌّ واحد من عنوانٍ خاصّ ⇒ على الشبكة فوراً. لا ردّ من ≥٣ عناوين خاصّة ⇒ خارجها فوراً (لا ثلاث جولات).
/// * جولةٌ جزئيّة (أقلّ من ٣ عناوين خاصّة بلا ردّ — جولة المؤقّت تخفّف فحص الفاشل) لا تقرّر «خارج» وحدها ولا تمسحها: كانت تمسح
///   «خارج الشبكة» الذي قرّرته جولةٌ كاملة قبلها. وإن كانت «خارج» مقرَّرةً فهي تجدّدها (لا تشيخ والقسم يقيس).
/// * الحال تشيخ بعد [staleAfter] ⇒ «غير معروف» حتى تُقاس من جديد.
enum NetPresence { unknown, on, off }

/// عيّنة «على شبكتك؟»: كم عنواناً خاصّاً سُئل وكم ردّ — حارس «وضع VPN» يحكم من مجموعها (ردٌّ واحد لا يكفيه).
typedef NetSample = ({int attempted, int reached});

class AgentNetPresence {
  AgentNetPresence._();

  static const minAttempts = 3;
  static const staleAfter = Duration(minutes: 3);

  static final ValueNotifier<NetPresence> state = ValueNotifier<NetPresence>(NetPresence.unknown);
  static DateTime? _at;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static NetPresence get current {
    final at = _at;
    if (at == null || now().difference(at) > staleAfter) return NetPresence.unknown;
    return state.value;
  }

  static bool get isOff => current == NetPresence.off;
  static bool get isOn => current == NetPresence.on;

  /// عنوانٌ خاصّ (IPv4) — وحده يدلّ على شبكة الوكيل.
  static bool isPrivate(String? ip) {
    final p = (ip ?? '').trim().split(':').first.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]);
    final b = int.tryParse(p[1]);
    if (a == null || b == null) return false;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 100 && b >= 64 && b <= 127);
  }

  /// نتيجة جولة/عيّنة: كم عنواناً خاصّاً جُرّب، وكم ردّ منها. ⇒ الحال بعدها.
  static NetPresence report({required int attempted, required int reached}) {
    if (reached > 0) {
      _set(NetPresence.on);
    } else if (attempted >= minAttempts || (attempted > 0 && current == NetPresence.off)) {
      // جولةٌ جزئيّة بلا ردّ لا تقرّر «خارج» وحدها، لكنّها تُبقي «خارج» المقرَّرة حيّةً (جولات الأجهزة تتباطأ مع الفشل)
      _set(NetPresence.off);
    }
    return current;
  }

  static void _set(NetPresence p) {
    _at = now();
    state.value = p; // نفس الحال لا تُبلغ أحداً — «تشيخ» تُحسب عند القراءة
  }

  /// خروجٌ/تبديل حساب: شبكة شركةٍ أخرى.
  static void reset() {
    _at = null;
    state.value = NetPresence.unknown;
  }

  @visibleForTesting
  static void debugSet(NetPresence p) => _set(p);
}
