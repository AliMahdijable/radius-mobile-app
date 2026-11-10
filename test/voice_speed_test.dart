// ١١ نوفمبر — المالك: «الاوامر الصوتيه صار يتاخر هواي من يحجي الشخص بالخص بوضع التلقائي».
// المطابقة كانت تنتظر القائمة و«المتّصلين» معاً لكلّ بديلٍ ممّا سُمع (حتى أربع مرّات للأمر). الآن: الكرت ممّا في الذاكرة فوراً،
// والبدائل على القائمة نفسها، والطازجة بحال اتّصالها بعد ظهوره — و«لا أحد» من قائمةٍ قديمة لا تُقال قبل سؤال الطازجة.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/voice/voice_command_sheet.dart';
import 'package:rad_mysvcs/services/voice/voice_lang_pref.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';

import 'visual_perm/visual_perm_harness.dart';

Subscriber _s(String idx, String user, String first, String last, {bool online = false}) => Subscriber.fromJson({
      'idx': idx,
      'username': user,
      'firstname': first,
      'lastname': last,
      'enabled': true,
      'profile_name': 'Fiber 35',
      if (online) 'online_status': 1,
    });

void main() {
  setUpAll(visualSetUpAll);

  final old = [_s('11', 'ali.hussein', 'علي', 'حسين'), _s('12', 'ali77', 'علي', 'كاظم')];

  final originalKnown = VoiceResolver.knownSubscribers;
  setUp(() {
    VoiceLangPref.debugReset('ar');
    VoiceResolver.clearCaches();
    VoiceResolver.mergedOn = () => false;
    VoiceResolver.bigProbe = () async => 0;
    VoiceResolver.loadList = null;
    VoiceResolver.knownSubscribers = (_) => null;
    VoiceResolver.loadSubscribers = () async => old;
  });
  tearDown(() {
    VoiceLangPref.debugReset();
    VoiceResolver.clearCaches();
    VoiceResolver.loadList = null;
    VoiceResolver.knownSubscribers = originalKnown;
    VoiceResolver.bigProbe = () async => 0;
    VoiceResolver.loadSubscribers = () async => const [];
  });

  group('المطابقة', () {
    test('ممّا في الذاكرة فوراً — لا قائمة ولا «متّصلين» تُطلب، والنتيجة «قديمة» ليُسأل عن الطازجة بعدها', () async {
      var loads = 0;
      final ages = <Duration>[];
      VoiceResolver.knownSubscribers = (age) {
        ages.add(age);
        return old;
      };
      VoiceResolver.loadSubscribers = () async {
        loads++;
        return old;
      };
      final m = await VoiceResolver.subscribers('علي حسين');
      expect([m.sure, m.stale, m.items.first.item.idx], [true, true, '11']);
      expect(loads, 0);
      expect(ages, [VoiceResolver.snapshotAge]);
      // بدائل ما سُمع على القائمة نفسها — ولا طلب
      await Future.wait([VoiceResolver.subscribers('علي حسن'), VoiceResolver.subscribers('علي كاظم')]);
      expect(loads, 0);
    });

    test('بلا شيءٍ في الذاكرة: القائمة وحدها (بلا انتظار «المتّصلين») — والطازجة تُطلب صراحةً', () async {
      var list = 0, withOnline = 0;
      List<Subscriber>? cached;
      VoiceResolver.knownSubscribers = (_) => cached;
      VoiceResolver.loadList = () async {
        list++;
        return cached = old;
      };
      VoiceResolver.loadSubscribers = () async {
        withOnline++;
        return old;
      };
      final m = await VoiceResolver.subscribers('علي حسين');
      expect([m.sure, m.stale], [true, true]);
      expect([list, withOnline], [1, 0]);
      // البدائل: القائمة صارت في الذاكرة
      await VoiceResolver.subscribers('علي حسن');
      expect([list, withOnline], [1, 0]);
      final fresh = await VoiceResolver.subscribers('علي حسين', fresh: true);
      expect([fresh.sure, fresh.stale], [true, false]);
      expect([list, withOnline], [1, 1]);
    });

    test('«افحص المشترك» (live): ما في الذاكرة يُقبل طازجاً فقط (٢٠ث) وإلّا من الشبكة — وليس «قديماً»', () async {
      var withOnline = 0;
      final ages = <Duration>[];
      VoiceResolver.knownSubscribers = (age) {
        ages.add(age);
        return age <= VoiceResolver.liveAge ? null : old; // عندنا قائمة لكنّها أقدم من ٢٠ث
      };
      VoiceResolver.loadSubscribers = () async {
        withOnline++;
        return old;
      };
      final m = await VoiceResolver.subscribers('علي حسين', live: true);
      expect([m.sure, m.stale, withOnline], [true, false, 1]);
      expect(ages, [VoiceResolver.liveAge]);
      // والطازجة في الذاكرة ⇒ بلا طلب
      VoiceResolver.knownSubscribers = (_) => old;
      final again = await VoiceResolver.subscribers('علي حسين', live: true);
      expect([again.stale, withOnline], [false, 1]);
    });

    test('قائمةٌ لم تُجلب (شبكة) ليست «لا أحد بهذا الاسم»', () async {
      VoiceResolver.loadSubscribers = () async => null;
      final m = await VoiceResolver.subscribers('علي حسين', fresh: true);
      expect(m.isEmpty, isTrue);
      expect(m.error, isNotNull);
    });

    test('الحساب الكبير: الاسم نفسه لا يُبحث مرّتين خلال دقيقة (الفوريّ ثمّ الطازج، والبدائل المتكرّرة) — ويُنسى بتبدّل الجلسة', () async {
      final asked = <String>[];
      VoiceResolver.bigProbe = () async => 89000;
      VoiceResolver.bigSearch = (q) async {
        asked.add(q);
        return [_s('501', 'ali.h', 'علي', 'حسين')];
      };
      addTearDown(() => VoiceResolver.bigSearch = (q) async => const []);
      final a = await VoiceResolver.subscribers('علي حسين');
      final b = await VoiceResolver.subscribers('علي حسين', fresh: true);
      expect([a.sure, a.stale, b.sure], [true, false, true]);
      expect(asked, ['علي حسين']);
      VoiceResolver.clearCaches();
      await VoiceResolver.subscribers('علي حسين');
      expect(asked, ['علي حسين', 'علي حسين']);
    });
  });

  group('الورقة', () {
    Future<void> settle(WidgetTester t, {int ms = 1500}) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester t) async {
      final inner = await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = inner;
      await pumpVisual(t, phone,
          home: (_) => Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      key: const ValueKey('open-voice'),
                      onPressed: () => showAppSheet<void>(
                        context: ctx,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => VoiceCommandSheet(rootContext: ctx, autoListen: false),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ));
      await settle(t, ms: 500);
      await t.tap(find.byKey(const ValueKey('open-voice')));
      await settle(t, ms: 800);
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      await visualTearDown();
    }

    testWidgets('الكرت يظهر ممّا في الذاكرة والشبكة لم تردّ بعد — ثمّ بيانات صفّه تتحدّث بمكانها', (t) async {
      final net = Completer<List<Subscriber>?>();
      var asked = 0;
      VoiceResolver.knownSubscribers = (_) => old;
      VoiceResolver.loadSubscribers = () {
        asked++;
        return net.future;
      };
      await open(t);
      await t.enterText(find.byKey(const ValueKey('voice-text')), 'فعّل علي حسين');
      await t.testTextInput.receiveAction(TextInputAction.go);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget, reason: 'بلا انتظار القائمة و«المتّصلين»');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(asked, 1, reason: 'الطازجة طُلبت بالخلفيّة مرّةً');
      expect(find.textContaining('ali.hussein'), findsWidgets);
      // الطازجة وصلت: الصفّ نفسه (idx 11) ببياناته الجديدة
      net.complete([_s('11', 'ali.hussein.new', 'علي', 'حسين', online: true), old[1]]);
      await settle(t, ms: 400);
      expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
      expect(find.textContaining('ali.hussein.new'), findsWidgets, reason: 'بيانات الصفّ المعروض تحدّثت');
      await close(t);
    });

    testWidgets('«لا أحد» ممّا في الذاكرة ليست جواباً: مشتركٌ أُضيف للتوّ يُعثر عليه من القائمة الطازجة', (t) async {
      VoiceResolver.knownSubscribers = (_) => old; // القديمة بلا «مرتضى»
      var asked = 0;
      VoiceResolver.loadSubscribers = () async {
        asked++;
        return [...old, _s('31', 'murtadha', 'مرتضى', 'حسن')];
      };
      await open(t);
      await t.enterText(find.byKey(const ValueKey('voice-text')), 'فعّل مرتضى حسن');
      await t.testTextInput.receiveAction(TextInputAction.go);
      await settle(t, ms: 600);
      expect(find.byKey(const ValueKey('voice-sub-card')), findsOneWidget);
      expect(find.textContaining('murtadha'), findsWidgets);
      expect(asked, 1);
      await close(t);
    });
  });
}
