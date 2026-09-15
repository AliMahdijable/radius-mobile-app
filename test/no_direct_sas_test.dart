import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس «التطبيق لا يعرف عنوان الساس».
///
/// ── لماذا حارسٌ لا تعليق ─────────────────────────────────────────
/// كان في `lib/api/api_client.dart` عميلٌ ثانٍ مثبَّتٌ نصّيّاً على
/// `https://reseller-supernet.net/admin/api/index.php/api`، يُبنى مرّةً
/// عند تحميل الصنف. نداءاته حُذفت في 2026-08-31 (`a58acd7`) وبقي هو
/// ميّتاً أسبوعين — فقرأه مراجعٌ ورفع بلاغ «عطلٌ يمنع الإقلاع» عن سلوكٍ
/// لم يعد موجوداً. الكود الميّت يكذب، والتعليق وحده لا يمنع عودته.
///
/// ── وما الذي يمنعه فعلاً ─────────────────────────────────────────
/// ثلاثة أضرارٍ يعيدها أيّ نداءٍ مباشرٍ من الهاتف إلى الساس:
///
///   ١. **يقصر التطبيق على ساسٍ واحد.** العنوان في الهاتف ثابتٌ في
///      حزمةٍ منشورة على المتجرين؛ المدير على ساسٍ ثانٍ لا سبيل له
///      لتغييره. أمّا خادمنا فيعرف — من هويّة المدير — أيّ ساسٍ يخصّه
///      (`server/sasIdentity.js` · جدول `sas_servers`).
///
///   ٢. **يسرّب توكن خادمنا إلى مضيفٍ ثالث.** `_AuthInterceptor` يلصق
///      `AuthStorage.readToken()` على كلّ طلب — وهي `empJWT` خادِمنا في
///      حالة الموظّف، لا توكن الساس. فالعميل الثاني كان يبعثها إلى
///      مضيفٍ لم يُصدرها.
///
///   ٣. **يدور بلا نهاية على 401.** ردّ الساس على توكنٍ لا يعرفه يشعل
///      `/api/auth/refresh-token` عند خادمنا، والتجديد لا يغيّر شيئاً
///      لأنّ المشكلة في وجهة الطلب لا في عمر التوكن.
///
/// القاعدة: **من احتاج رقماً من الساس فليطلبه من `rad.mysvcs.net`.**
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('لا عنوان ساسٍ مشفَّرٌ في lib/', () {
    // مضيف ساسٍ (أيّ `reseller*.net`) أو مسار واجهته المميَّز.
    final sasHost = RegExp(r'reseller[A-Za-z0-9-]*\.net');
    final sasPath = RegExp(r'/admin/api/index\.php');

    final offenders = <String>[];
    for (final f in dartFiles) {
      final path = f.path.replaceAll(r'\', '/');
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        // التعليقات تشرح لماذا حُذف العنوان — فلا تُحاسَب. الفحص على
        // ما يُنفَّذ: سلسلةٌ في كودٍ حيّ.
        final t = l.trimLeft();
        if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) {
          continue;
        }
        if (sasHost.hasMatch(l) || sasPath.hasMatch(l)) {
          offenders.add('$path:${i + 1}  ${l.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'عنوان ساسٍ عاد إلى التطبيق. الهاتف يخاطب rad.mysvcs.net '
          'وحده — أضف endpoint على خادمنا بدلاً من نداءٍ مباشر:\n'
          '${offenders.join('\n')}',
    );
  });

  test('ApiClient يعرّف عميلاً واحداً لا أكثر', () {
    // حتى لو جاء العنوان من متغيّرٍ أو من ردّ الدخول، عميلٌ ثانٍ يعني
    // وجهةً ثانية — وهي الأضرار الثلاثة أعلاه بعينها.
    final src = File('lib/api/api_client.dart').readAsLinesSync();
    final clients = <String>[];
    for (var i = 0; i < src.length; i++) {
      final t = src[i].trimLeft();
      if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) {
        continue;
      }
      if (RegExp(r'static\s+final\s+Dio\s+\w+').hasMatch(src[i])) {
        clients.add('api_client.dart:${i + 1}  ${src[i].trim()}');
      }
    }

    expect(
      clients,
      hasLength(1),
      reason: 'عدد عملاء Dio في ApiClient يجب أن يبقى واحداً '
          '(`dio` → rad.mysvcs.net):\n${clients.join('\n')}',
    );
  });
}
