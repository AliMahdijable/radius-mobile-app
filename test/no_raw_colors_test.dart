import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس اللوحة — يمنع عودة الألوان الخام إلى `lib/`.
///
/// اللون الخام `Color(0xFF…)` **لا يعرف الوضع الليلي**: يبقى كما هو على
/// السطح الداكن، فينتج نصّاً غير مقروء أو حبّة تختفي. هذه هي العلّة
/// الجذريّة التي جعلت الوضع الليلي معطّلاً فعليّاً رغم أنّ بنيته
/// (`ThemeService` + `AppColors.setDarkMode`) قائمة وتعمل.
///
/// 2026-08-29: كانت 612 موضعاً، حُوّلت إلى توكنات. الباقي مستثنى أدناه
/// **بسبب مذكور لكلّ استثناء** — لا استثناء بلا تعليل.
void main() {
  test('لا ألوان خام في lib/ خارج القائمة المستثناة', () {
    // ── الاستثناءات وأسبابها ──
    const allowedFiles = <String, String>{
      'lib/theme/colors.dart':
          'تعريف اللوحة نفسها — هنا مكان الأرقام الخام الوحيد',
      'lib/theme/spacing.dart': 'قِيَم الظلال معرّفة مع سلّم المسافات',
      'lib/screens/network_devices/widgets/brand_badge.dart':
          'تدرّجات شعارات المصنّعين (Mikrotik · Ubiquiti · Mimosa · Cisco) '
              '— هويّة طرف ثالث لا حالة في واجهتنا',
      'lib/screens/reports/widgets/report_export.dart':
          'PdfColors — مستند مطبوع على ورق أبيض، خارج ثيم التطبيق',
      'lib/screens/subscribers/sheets/qr_login_sheet.dart':
          'بطاقة QR — الأبيض والحبر شرط لقراءة الرمز بالكاميرا',
      'lib/screens/telegram/sheets/telegram_link_generator_sheet.dart':
          'بطاقة QR — نفس السبب',
      'lib/screens/subscribers/sheets/location_picker_screen.dart':
          'طبقات فوق خريطة خارجيّة — تُقرأ على صور القمر الصناعي لا على '
              'أسطح التطبيق، فلا تتبع اللوحة',
    };
    // ألوان علامات الطرف الثالث: تعريف قناة لا تعبير عن حالة.
    const allowedLiterals = <String, String>{
      '0xFF25D366': 'أخضر واتساب',
      '0xFF229ED9': 'أزرق تلغرام',
      '0xFF4285F4': 'أزرق Google Maps — زرّ «فتح في الخرائط»',
      '0xFF33CCFF': 'أزرق Waze — زرّ «فتح في Waze»',
    };

    final raw = RegExp(r'Color\((0x[0-9A-Fa-f]{8})\)');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (allowedFiles.containsKey(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // التعليقات ليست كوداً — الفحص على ما يُنفَّذ فقط.
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in raw.allMatches(lines[i])) {
          final hex = m.group(1)!.toUpperCase().replaceFirst('0X', '0x');
          if (allowedLiterals.containsKey(hex)) continue;
          // محوّلات hex القادمة من الـAPI تبني اللون من عدد لا من ثابت.
          if (lines[i].contains('0xFF000000 |')) continue;
          offenders.add('$path:${i + 1}  ${m.group(0)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'ألوان خام جديدة — استعمل توكناً من AppColors، أو أضف '
          'الملفّ إلى allowedFiles **مع سبب**:\n${offenders.join('\n')}',
    );
  });

  test('لا Colors.white/black خام في الودجتات الجديدة', () {
    // الطقم المشترك واللوحة الجديدة يجب أن يبقيا نظيفين تماماً —
    // هما المرجع الذي تُقاس عليه بقيّة الشاشات أثناء الترحيل.
    const guarded = [
      'lib/core/widgets/design_sheet.dart',
      'lib/screens/subscribers/widgets/subscriber_actions.dart',
      'lib/screens/subscribers/widgets/device_probe_card.dart',
    ];
    final bad = RegExp(r'(?<![A-Za-z])Colors\.(white|black)(?![A-Za-z])');
    final offenders = <String>[];
    for (final p in guarded) {
      final f = File(p);
      if (!f.existsSync()) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (bad.hasMatch(lines[i])) {
          offenders.add('$p:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'استعمل AppColors.onBrand بدل Colors.white:\n'
            '${offenders.join('\n')}');
  });
}
