import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'auth_storage.dart';

/// نسخةٌ محفوظة من قائمة المشتركين تعمل بلا إنترنت.
///
/// الغرض المحدَّد: أن يُجيب المدير زبونه في الميدان عن **«كم عليّ؟»**
/// و**«متى ينتهي اشتراكي؟»** وهو بلا شبكة. لا أكثر.
///
/// ── ثلاثة قرارات تحكم هذا الملفّ ───────────────────────────────
///
/// **١) قراءةٌ فقط، بلا طابور عمليّات.** لا يُخزَّن هنا «فعّل لاحقاً»
/// ولا «اشحن عند عودة الشبكة». والسبب مقيسٌ لا نظريّ: الساس يردّ
/// `HTTP 500` على سحبٍ **نفذ فعلاً**، وحارس التكرار عنده نافذته
/// ثانيتان. فطابورٌ يُفرَّغ بعد ساعة يسحب المبلغ مرّتين ولا شيء
/// يمنعه. هذا الصنف من الضرر لا يُخفَّف — يُلغى بألّا نكتب.
///
/// **٢) نُخزّن الـJSON الخام لا كائنات `Subscriber`.** فالنموذج لا
/// يملك `toJson` أصلاً، وكتابةُ واحدةٍ تعني نسخةً ثانيةً من منطق
/// التسلسل تنحرف عن `fromJson` صامتةً كلّما أُضيف حقل — وهو بالضبط
/// فخّ `copyWith` الذي أسقط `telegramLinked` هذا الأسبوع. فالقراءة
/// تمرّ بـ`fromJson` نفسها التي تمرّ بها الشبكة: محلّلٌ واحد.
///
/// **٣) كلمة المرور تُحذف قبل الكتابة.** قائمة المشتركين تحمل
/// `password` من الساس، والإجابة عن «كم عليّ؟» لا تحتاجها. وحذفُ
/// أخطر حقلٍ أقوى من تشفيره: ما لا يُكتب لا يُسرَّب.
///
/// ── وأين يُكتب ──────────────────────────────────────────────────
/// في **مجلّد الكاش** لا المستندات. وهو اختيارٌ دلاليّ وأمنيّ معاً:
/// النظام لا يرفعه في النسخ الاحتياطيّة (iCloud/Google Backup)، وله
/// أن يحذفه عند ضيق التخزين — وهو سلوكٌ مقبولٌ تماماً لنسخةٍ يُعاد
/// جلبها في ثانية. أمّا `SharedPreferences` فنصٌّ صريح **يدخل النسخة
/// الاحتياطيّة**، ولا يصلح لآلاف الصفوف أصلاً (يُحمَّل كلّه في
/// الذاكرة عند أوّل قراءة).
class SubscribersOfflineCache {
  SubscribersOfflineCache._();

  static const _fileName = 'subs_offline_v1.json';

  /// ⚠️ لا يُعرض ما تجاوز هذا العمر. رقمُ دينٍ عمره أسبوع ليس معلومةً
  /// ناقصة بل معلومةٌ **خاطئة**: الزبون سدّد، والمدير يطالبه ثانيةً.
  /// وانعدام الجواب أنظف من جوابٍ يُوقع في خطأ.
  static const maxAge = Duration(days: 3);

  static Future<File> _file() async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// يحفظ الصفوف الخام. يُنادى بعد كلّ جلبٍ ناجح، ولا يرمي أبداً:
  /// فشلُ الحفظ لا يجوز أن يُسقط جلباً نجح.
  static Future<void> save(List<Map<String, dynamic>> rows) async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null) return; // بلا هويّة لا نكتب شيئاً
      // ⚠️ إسقاط كلمات المرور — الحقل الوحيد الذي لا نقبل نزوله للقرص.
      final safe = rows.map((r) {
        final c = Map<String, dynamic>.from(r);
        c.remove('password');
        return c;
      }).toList();
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'v': 1,
        'adminId': adminId,
        'at': DateTime.now().toIso8601String(),
        'rows': safe,
      }));
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 subs offline save: $e');
    }
  }

  /// يقرأ النسخة المحفوظة إن كانت **لهذا المدير** و**ضمن العمر**.
  ///
  /// ⚠️ فحص `adminId` ليس تكراراً لمسح الخروج بل حزامٌ ثانٍ: مسحٌ فشل
  /// أو خروجٌ لم يمرّ بالقناة المعتادة يعني أن يرى مديرٌ مشتركي آخر.
  /// وثمن الفحص مقارنةُ نصّين.
  static Future<({List<Map<String, dynamic>> rows, DateTime at})?> read() async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null) return null;
      final f = await _file();
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return null;
      if (raw['adminId']?.toString() != adminId) {
        await clear();
        return null;
      }
      final at = DateTime.tryParse(raw['at']?.toString() ?? '');
      if (at == null) return null;
      if (DateTime.now().difference(at) > maxAge) return null;
      final rows = (raw['rows'] as List?) ?? const [];
      return (
        rows: rows
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
        at: at,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 subs offline read: $e');
      return null;
    }
  }

  /// يُمسح عند الخروج — موصولٌ بـ`SessionManager.clearAllSessionData`.
  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {/* ملفٌّ غير موجود أو قرصٌ مقفل — لا شيء نفعله */}
  }
}
