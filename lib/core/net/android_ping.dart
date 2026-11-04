import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// ping أندرويد — أمر النظام نفسه وقراءة كلّ سطرٍ منه، لا dart_ping.
///
/// 🐛 ٤ نوفمبر — المالك: «الجهاز مفصول من السوج… التطبيق يكذب بالقراءات». ping أندرويد (iputils القديم، وtoybox) يستقبل خطأ ICMP
/// من الراوتر («الجهاز غير قابل للوصول») على مقبس الـping ويطبعه **ردّاً من الجهاز نفسه**:
///
///     64 bytes from 10.70.241.10: icmp_seq=0 ttl=255 time=0.000 ms
///     wrong data byte #16 should be 0x10 but was 0xa
///
/// وdart_ping يعدّه ردّاً (سطر «bytes from … time=») فجهازٌ مفصول خلف راوتر كان «متّصلاً · 0 ms» — وحتى عنوانٌ لا وجود له
/// (10.99.99.99) «يردّ». مُثبَتٌ على أندرويد 12 (المحاكي) بمخرجات حقيقيّة (test/android_ping_test.dart).
///
/// الردّ الصحيح هنا: من العنوان المطلوب نفسه، بزمنٍ أكبر من صفر وضمن المهلة، غير مكرّر (DUP!)، ولا يليه «wrong data byte».
class AndroidPing {
  AndroidPing._();

  static final _reply = RegExp(
      r'^\d+ bytes from (?:[^()]*\()?([0-9a-fA-F.:]+)\)?: icmp_seq=(\d+) ttl=\d+ time=([0-9]+(?:\.[0-9]+)?) ms(.*)$');

  /// أزمنة الردود الصحيحة (ملّي ثانية، مدوّرة) من مخرجات ping لـ[ip]. [maxMs]: المهلة — ردٌّ أطول منها مستحيل (طابعٌ زمنيّ مقروءٌ
  /// من بايتاتٍ خاطئة).
  @visibleForTesting
  static List<int> validTimes(String output, String ip, {required int maxMs}) {
    final lines = output.split(RegExp(r'\r?\n'));
    final out = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _reply.firstMatch(lines[i].trim());
      if (m == null) continue;
      if (m.group(1) != ip) continue; // ردٌّ من غير الجهاز المطلوب
      final next = i + 1 < lines.length ? lines[i + 1].trimLeft() : '';
      if (next.startsWith('wrong data byte')) continue; // خطأ ICMP مقروءٌ ردّاً
      if ((m.group(4) ?? '').contains('DUP!')) continue;
      final ms = double.tryParse(m.group(3) ?? '');
      if (ms == null || ms <= 0 || ms > maxMs) continue; // 0.000 أو طابعٌ زمنيّ خاطئ
      out.add(ms.round());
    }
    return out;
  }

  /// تشغيل الأمر — للاختبار يُحقن مخرجٌ جاهز.
  @visibleForTesting
  static Future<String> Function(String ip, int count, Duration timeout) runner = _run;

  static Future<String> _run(String ip, int count, Duration timeout) async {
    final r = await Process.run('ping', ['-c', '$count', '-W', '${timeout.inSeconds < 1 ? 1 : timeout.inSeconds}', ip])
        .timeout(timeout * count + const Duration(seconds: 3));
    return '${r.stdout}';
  }

  /// [count] حزمة إلى [ip] ⇒ أزمنة الردود الصحيحة وحدها (فارغة = لا ردّ).
  static Future<List<int>> ping(String ip, {int count = 1, Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final output = await runner(ip, count, timeout);
      return validTimes(output, ip, maxMs: timeout.inMilliseconds < 1000 ? 1000 : timeout.inMilliseconds);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ AndroidPing $ip: $e');
      return const [];
    }
  }
}
