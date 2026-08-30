import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس سلالم نظام التصميم.
///
/// بعد توحيد 410 مقاس خطّ و201 نصف قطر، هذا الاختبار يمنع الانحراف:
/// أيّ قيمة جديدة خارج السلّم تُسقطه فوراً بدل أن تتسرّب وتتراكم حتى
/// تصير كلّ شاشة عالماً قائماً بذاته — وهي الحالة التي بدأنا منها.
void main() {
  Iterable<File> dartFiles() sync* {
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) yield e;
    }
  }

  test('لا نصف قطر مكتوب بالرقم — كلّها توكنات R', () {
    // القيم الخام تُخفي النيّة: `circular(4)` على ارتفاع 4px كبسولة
    // كاملة لا زاوية ناعمة، و`circular(20)` قد تكون كارتاً أو حبّة.
    final raw = RegExp(r'BorderRadius\.circular\(\s*[0-9]');
    final offenders = <String>[];
    for (final f in dartFiles()) {
      final path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/theme/')) continue; // تعريف السلّم نفسه
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (raw.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'استعمل توكناً من R (sm·chip·md·icon·lg·button·card·xl·'
            'hero·sheet·pill):\n${offenders.join('\n')}');
  });

  test('مقاسات الخطّ على سلّم المخطّط', () {
    // السلّم مشتقّ من المخطّط ومعاير لـCairo (أعرض من IBM Plex الذي
    // رُسم به). المقاسان 28 و30 مستثنيان: نصّ البطل في شاشتَي البداية
    // والدخول، خارج سلّم الواجهة عمداً.
    const scale = <String>{
      '9.5',
      '10.5',
      '11',
      '11.5',
      '12.5',
      '13',
      '13.5',
      '14',
      '15',
      '15.5',
      '16',
      '17',
      '19',
      '20',
      '22',
      '24',
      '28',
      '30',
    };
    final sizeRe = RegExp(r'fontSize: ([0-9]+(?:\.[0-9]+)?)');
    final offenders = <String>[];
    for (final f in dartFiles()) {
      final path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/theme/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in sizeRe.allMatches(lines[i])) {
          if (!scale.contains(m.group(1))) {
            offenders.add('$path:${i + 1}  ${m.group(0)}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'مقاس خارج السلّم — استعمل AppType أو قرّب لأقرب درجة:\n'
            '${offenders.join('\n')}');
  });

  test('لا وزن أثقل من w700 — المخطّط لا يعرف w800/w900', () {
    final heavy = RegExp(r'FontWeight\.w[89]00');
    final offenders = <String>[];
    for (final f in dartFiles()) {
      final path = f.path.replaceAll(r'\', '/');
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (heavy.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'سلّم الوزن ثلاث درجات: w500 الخافت · w600 السائد · '
            'w700 القيم والعناوين.\n${offenders.join('\n')}');
  });

  test('كلّ شيت يحدّد barrierColor — لا أسود Material الافتراضي', () {
    // `Colors.black54` الافتراضي يبتلع حواف الشيت ليلاً بدل أن يفصلها،
    // و`AppColors.scrim` مبنيّ على #121614 ويُرفع في الوضع الداكن.
    final offenders = <String>[];
    for (final f in dartFiles()) {
      final path = f.path.replaceAll(r'\', '/');
      final src = f.readAsStringSync();
      if (!src.contains('showModalBottomSheet')) continue;
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('showModalBottomSheet')) continue;
        // أسطر التوثيق تذكر الاسم ولا تستدعيه.
        final t = lines[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('///')) continue;
        var depth = lines[i].split('(').length - lines[i].split(')').length;
        final buf = StringBuffer(lines[i]);
        var j = i + 1;
        while (j < lines.length && depth > 0) {
          buf.writeln(lines[j]);
          depth += lines[j].split('(').length - lines[j].split(')').length;
          j++;
        }
        if (!buf.toString().contains('barrierColor')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'أضِف `barrierColor: AppColors.scrim` إلى:\n'
            '${offenders.join('\n')}');
  });

  test('كل نمط خطّ بمقاس يصرّح بارتفاع سطره', () {
    // Cairo صندوقه أطول من افتراضي Flutter، فـ`TextStyle(fontSize: …)`
    // بلا `height` يترك التباعد لمقاييس الخطّ لا للتصميم. هكذا بدت
    // شاشات الأجهزة وتلغرام فضفاضة رغم أنّ مقاساتها مطابقة للسلّم —
    // الفرق كان في السطر لا في الحرف.
    //
    // `AppType` يصرّح دائماً، فالاستدعاء عبره يمرّ تلقائيّاً. هذا
    // الاختبار يحرس الأنماط الخام التي تُكتب مباشرةً.
    //
    // الاستثناء الوحيد: مولّدات PDF — `pw.TextStyle` من حزمة `pdf`
    // لها مقاييسها الخاصّة ولا تفهم `height` بمعنى Flutter.
    const pdfGenerators = {
      'lib/services/print_service.dart',
      'lib/screens/reports/widgets/report_export.dart',
    };

    final offenders = <String>[];
    for (final f in dartFiles()) {
      final path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/theme/') || pdfGenerators.contains(path)) {
        continue;
      }
      final src = f.readAsStringSync();
      for (final m in RegExp(r'TextStyle\(').allMatches(src)) {
        // تخطَّ `pw.TextStyle`
        if (m.start >= 3 && src.substring(m.start - 3, m.start) == 'pw.') {
          continue;
        }
        var depth = 1, i = m.end;
        while (depth > 0 && i < src.length) {
          if (src[i] == '(') depth++;
          if (src[i] == ')') depth--;
          i++;
        }
        final body = src.substring(m.end, i - 1);
        if (!body.contains('fontSize') || body.contains('height:')) continue;
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('$path:$line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'أنماط بمقاس بلا ارتفاع سطر — استعمل AppType أو صرّح '
            'بـheight من سلّمه:\n${offenders.join('\n')}');
  });

}
