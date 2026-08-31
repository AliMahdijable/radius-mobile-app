import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// رقم النسخة يتبع المتجر لا الجلسة.
///
/// 🚨 انحراف 2026-08-31: رفعتُ الرقم مع كلّ بناء تجريبيّ حتّى بلغ
/// 4.6.0+186، بينما المنشور على Play/App Store عند **129**. فصار عندنا
/// مساران متوازيان: واحد في المستودع وآخر في المتجر.
///
/// والضرر ليس تجميليّاً: `versionCode` يجب أن يزيد بواحد عن المنشور
/// لا أن يقفز عشرات. والقفز يحرق أرقاماً لا يمكن استرجاعها أبداً —
/// Play يرفض أيّ رفع برقم أقلّ ممّا سبق، إلى الأبد.
///
/// القاعدة: البناء التجريبيّ **لا يرفع الرقم**. الرقم يتغيّر مرّة
/// واحدة عند النشر، بواحد فوق المتجر.
void main() {
  test('النسخة مثبَّتة على ما يلي المتجر', () {
    final raw = File('pubspec.yaml').readAsLinesSync();
    final line = raw.firstWhere((l) => l.startsWith('version:'));
    final v = line.split(':')[1].trim();
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(v);
    expect(m, isNotNull, reason: 'صيغة غير متوقّعة: $v');

    final build = int.parse(m!.group(4)!);
    final major = int.parse(m.group(1)!);

    // ⚠️ الحدّ الأعلى مقصود: من يبني تجريبيّاً ويرفع الرقم يصطدم بهذا
    // السطر قبل أن يحرق أرقاماً لا تُستعاد.
    expect(build, lessThanOrEqualTo(140),
        reason: 'رقم البناء $build بعيد عن المتجر (129) — '
            'البناء التجريبيّ لا يرفع الرقم');
    expect(major, lessThanOrEqualTo(3),
        reason: 'الإصدار الرئيسيّ $major لا يطابق مسار المتجر (2.x)');
  });
}
