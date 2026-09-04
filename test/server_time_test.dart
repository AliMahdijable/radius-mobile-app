import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/server_time.dart';

/// 🐛 بلاغ ٢٠٢٦-٠٩-٠٤: «تسديد دين منذ: يقرأ ٣ ساعات حتّى لو هسّة سدّدته».
///
/// وثلاث ساعات هي فرق بغداد عن UTC بالضبط. الاختبار يُثبت الإصلاح بلا
/// اعتمادٍ على منطقة جهاز التشغيل: يقارن اللحظات لا الأرقام المعروضة.
void main() {
  group('توقيتات قاعدتنا — UTC', () {
    test('🚨 نصٌّ عارٍ يُقرأ UTC لا محلّيّاً', () {
      // نفس اللحظة مكتوبةً بالصيغتين يجب أن تُعطي النتيجة نفسها.
      final bare = parseServerUtc('2026-09-04 11:39:56');
      final marked = DateTime.parse('2026-09-04T11:39:56Z').toLocal();
      expect(bare, isNotNull);
      expect(
        bare!.isAtSameMomentAs(marked),
        isTrue,
        reason: 'النصّ العاري من قاعدتنا يجب أن يُعامَل UTC',
      );
    });

    test('🚨 والفرق ليس ثلاث ساعات — هذا جوهر العطل', () {
      // ما كان يحدث: DateTime.parse على النصّ العاري يقرؤه محلّيّاً.
      final wrong = DateTime.parse('2026-09-04T11:39:56'); // السلوك القديم
      final right = parseServerUtc('2026-09-04 11:39:56')!;
      // في بغداد (+3) يكون الفرق ٣ ساعات؛ وفي UTC يكون صفراً.
      // فنؤكّد أنّ الفرق يساوي إزاحة الجهاز بالضبط — أيّاً كانت.
      expect(
        right.difference(wrong).inMinutes,
        equals(-wrong.timeZoneOffset.inMinutes),
        reason: 'الفرق بين الصحيح والخطأ = إزاحة الجهاز عن UTC',
      );
    });

    test('الصيغ المختلفة كلّها تُقرأ', () {
      final a = parseServerUtc('2026-09-04 11:39:56');
      final b = parseServerUtc('2026-09-04T11:39:56');
      final c = parseServerUtc('2026-09-04T11:39:56.000Z');
      expect(a!.isAtSameMomentAs(b!), isTrue, reason: 'مسافة أو T — سيّان');
      expect(a.isAtSameMomentAs(c!), isTrue, reason: 'بكسورٍ وبـZ — سيّان');
    });

    test('🚨 منطقةٌ صريحة تُحترَم ولا تُوسَم ثانيةً', () {
      // لو أرسل الخادم يوماً منطقةً صريحة، فوسمُها Z يُفسدها.
      final baghdad = parseServerUtc('2026-09-04T14:39:56+03:00');
      final utc = parseServerUtc('2026-09-04 11:39:56');
      expect(
        baghdad!.isAtSameMomentAs(utc!),
        isTrue,
        reason: '١٤:٣٩ بغداد = ١١:٣٩ عالميّ — نفس اللحظة',
      );
    });

    test('الفارغ والتالف يُرجعان null لا تاريخاً كاذباً', () {
      expect(parseServerUtc(null), isNull);
      expect(parseServerUtc(''), isNull);
      expect(parseServerUtc('   '), isNull);
      expect(parseServerUtc('ليس تاريخاً'), isNull);
    });
  });

  group('تواريخ الساس — بغداد', () {
    test('🚨 لا تُوسَم Z — وإلّا تقدّمت ثلاث ساعات', () {
      // تاريخ انتهاء الاشتراك يأتي من الساس بتوقيت بغداد. وسمُه Z
      // يجعله يبدو أقدم بثلاث ساعات فيُظهر «انتهى» قبل أوانه.
      final sas = parseSasLocal('2026-10-04 20:00:00')!;
      expect(sas.hour, equals(20),
          reason: 'الساعة تبقى ٢٠ كما أرسلها الساس');
      expect(sas.isUtc, isFalse);
    });

    test('والدالّتان تختلفان — وهذا المقصود', () {
      final a = parseServerUtc('2026-09-04 11:39:56')!;
      final b = parseSasLocal('2026-09-04 11:39:56')!;
      if (a.timeZoneOffset.inMinutes != 0) {
        expect(
          a.isAtSameMomentAs(b),
          isFalse,
          reason: 'اصطلاحان مختلفان يجب أن يُعطيا لحظتين مختلفتين',
        );
      }
    });
  });

  group('منذ كذا', () {
    final now = DateTime(2026, 9, 4, 14, 39);

    test('🚨 التسديد الآن يقول «الآن» لا «منذ ٣ ساعات»', () {
      expect(timeAgoAr(now, now: now), equals('الآن'));
      expect(
        timeAgoAr(now.subtract(const Duration(seconds: 20)), now: now),
        equals('الآن'),
      );
    });

    test('🚨 المستقبل القريب لا يُعطي رقماً سالباً', () {
      // فارق ساعةٍ بين الخادم والجهاز يجعل التوقيت مستقبليّاً بثوانٍ.
      // «منذ −١ دقيقة» نصٌّ لا معنى له.
      expect(
        timeAgoAr(now.add(const Duration(minutes: 5)), now: now),
        equals('الآن'),
      );
    });

    test('التدرّج', () {
      expect(timeAgoAr(now.subtract(const Duration(minutes: 5)), now: now),
          equals('منذ 5 دقيقة'));
      expect(timeAgoAr(now.subtract(const Duration(hours: 3)), now: now),
          equals('منذ 3 ساعة'));
      expect(timeAgoAr(now.subtract(const Duration(days: 2)), now: now),
          equals('منذ 2 يوم'));
      expect(timeAgoAr(now.subtract(const Duration(days: 60)), now: now),
          equals('منذ 2 شهر'));
    });

    test('الفارغ لا يطبع شيئاً', () {
      expect(timeAgoAr(null), equals(''));
    });
  });
}
