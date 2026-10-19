import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_service.dart';
import 'auth_storage.dart';
import 'permissions_service.dart';

/// موافقة المستخدم على المساعد الذكيّ — مرّةً **لكلّ شخص** على هذا الجهاز، قبل
/// أوّل طلب.
///
/// نصّ الخطأ أو السؤال يذهب (بعد محاولة إخفاء الأسماء واليوزرات والهواتف
/// وكلمات السرّ — أفضل جهدٍ لا ضمان) عبر خادمنا لمزوّد ذكاءٍ اصطناعيّ خارجيّ
/// (Anthropic)، والخادم يحفظ النسخة المخفيّة مع الجواب مربوطةً بالحساب ٢٤ ساعة
/// (حتى ٣٠ يوماً لما لم يُحلّ أو أُبلغ أنّه غلط أو وجد فيه الفحص الآليّ مشكلة)
/// وقد يرسلها للمزوّد نفسه ليفحص دقّتها — فقبل أوّل «اشرحلي» أو «كيف أسوّي؟»
/// يُقال ذلك صراحةً ويُنتظر «موافق» (App Store 5.1.2(i)، وإفصاح Google Play عن
/// البيانات). الرفض لا يُحفظ: يُسأل ثانيةً في المرّة القادمة، ولا يُرسل شيءٌ قبل
/// الموافقة.
///
/// **لكلّ شخص لا لكلّ جهاز** (مراجعة ١٩ أكتوبر): موظّفٌ على هاتف مديره، أو مديرٌ
/// ثانٍ دخل حسابه، يُسأل هو قبل أن يُرسل نصّه ويُحفظ. المفتاح
/// `ai.consent.v2.<بصمة>`: بصمة (FNV-1a) للموظّف من معرّف الصفحة ويوزره،
/// ولصاحب الحساب من uid حساب Pro (أو معرّف صفحته قبله) — لا معرّفٌ خامّ في
/// التفضيلات. تبقى بعد الخروج من الحساب (كتفضيلات الجهاز الأخرى)، فمن رجع لا
/// يُسأل ثانيةً.
abstract final class AiConsent {
  /// بادئة مفتاح SharedPreferences — `v2` (١٩ أكتوبر): الحفظ المؤقّت للنسخة
  /// المخفيّة (٢٤ ساعة، حتى ٣٠ يوماً) والفحص الآليّ للدقّة (v1 كان «لا نحفظ»).
  /// تغيّرٌ جوهريّ فيما يُرسل أو يُحفظ أو لمن ⇒ بادئةٌ جديدة فيُسأل الكلّ ثانيةً.
  static const prefKey = 'ai.consent.v2';

  /// بصمات من وافق في هذا التشغيل (تبقى إن تعذّرت SharedPreferences).
  static final Set<String> _accepted = <String>{};

  /// للاختبارات: يفرض النتيجة بلا SharedPreferences.
  @visibleForTesting
  static bool? debugAccepted;

  /// للاختبارات: هويّة الفاعل بدل جلسة التطبيق (شخصان على جهازٍ واحد).
  @visibleForTesting
  static String? debugActor;

  /// مفتاح هذا الشخص: `ai.consent.v2.<بصمة هويّته>`.
  static Future<String> currentKey() async =>
      '$prefKey.${_fnv1a(await _actor())}';

  /// وافق من قبل هذا الشخص على هذا الجهاز؟
  static Future<bool> accepted() async {
    final forced = debugAccepted;
    if (forced != null) return forced;
    final key = await currentKey();
    if (_accepted.contains(key)) return true;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(key) ?? false) {
        _accepted.add(key);
        return true;
      }
    } catch (_) {/* لا تفضيلات ⇒ يُسأل */}
    return false;
  }

  /// «موافق» — تُحفظ لهذا الشخص على الجهاز (وتبقى في الذاكرة لهذا التشغيل إن
  /// تعذّر).
  static Future<void> accept() async {
    final key = await currentKey();
    _accepted.add(key);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, true);
    } catch (_) {/* تبقى لهذا التشغيل */}
  }

  @visibleForTesting
  static void debugReset() {
    _accepted.clear();
    debugAccepted = null;
    debugActor = null;
  }

  /// هويّة من يستعمل التطبيق الآن: الموظّف بمعرّف صفحته ويوزره (هو لا مديره)،
  /// وصاحب الحساب بـuid حساب Pro، وإلّا معرّف الصفحة، وإلّا «الجهاز».
  static Future<String> _actor() async {
    final forced = debugActor;
    if (forced != null) return forced;
    String? adminId;
    String? username;
    try {
      final token = await AuthStorage.readToken();
      if (token != null && token.isNotEmpty) {
        adminId = await AuthStorage.readAdminId();
        username = await AuthStorage.readAdminUsername();
      }
    } catch (_) {/* لا خزنة ⇒ ما بعده */}
    if (adminId != null && adminId.isNotEmpty && PermissionsService.isEmployee) {
      return 'emp:$adminId:${username ?? ''}';
    }
    String? uid;
    try {
      uid = AccountService.currentUser?.uid;
    } catch (_) {
      uid = null;
    }
    if (uid != null && uid.isNotEmpty) return 'acct:$uid';
    if (adminId != null && adminId.isNotEmpty) return 'own:$adminId';
    return 'device';
  }

  /// بصمة FNV-1a (٣٢ بت، ست عشريّة) — تفصل الأشخاص ولا تُخزّن معرّفاً خامّاً.
  static String _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
