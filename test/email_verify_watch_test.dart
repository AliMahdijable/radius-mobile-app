import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/screens/account/account_login_screen.dart';
import 'package:rad_mysvcs/screens/account/email_verify_watch.dart';
import 'package:rad_mysvcs/services/account_user.dart';
import 'package:rad_mysvcs/services/desktop_account_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'employee_ledger/ledger_fixture.dart' show LedgerDiskLoader;

/// «تأكّد البريد» تلقائيّاً — المالك ١٥ نوفمبر («تمام سوي الحل المجاني»): التطبيق يكتشف وحده أنّ صاحب الحساب ضغط رابط
/// التأكيد ويكمل، والزرّ اليدويّ باقٍ احتياطاً. الزمن هنا وهميّ (testWidgets): المواعيد تتقدّم بـpump.
void main() {
  group('المراقب', () {
    testWidgets('إيقاعه: كلّ ٤ ثوانٍ دقيقتين ثمّ كلّ ١٠، ويتوقّف وحده بعد ربع ساعة', (t) async {
      var probes = 0;
      final w = EmailVerifyWatch(probe: () async => ++probes < 0, onVerified: () => fail('لم يتأكّد'));
      w.start();
      expect(w.running, isTrue);
      await t.pump(const Duration(seconds: 3));
      expect(probes, 0, reason: 'أوّل فحصٍ بعد ٤ ثوانٍ');
      await t.pump(const Duration(seconds: 1));
      expect(probes, 1);
      await t.pump(const Duration(seconds: 116));
      expect(probes, 30, reason: 'دقيقتان × كلّ ٤ ثوانٍ');
      await t.pump(const Duration(seconds: 9));
      expect(probes, 30, reason: 'بعد الدقيقتين: كلّ ١٠');
      await t.pump(const Duration(seconds: 1));
      expect(probes, 31);
      await t.pump(const Duration(minutes: 13));
      expect(probes, 108, reason: '٣٠ + (٧٨٠ ث ÷ ١٠)');
      expect(w.running, isFalse, reason: 'انتهت المدّة');
      await t.pump(const Duration(minutes: 5));
      expect(probes, 108, reason: 'لا مواعيد بعد المدّة');
    });

    testWidgets('أوّل تأكيدٍ يوقفه ويُبلَّغ مرّةً واحدة', (t) async {
      var probes = 0;
      var verified = 0;
      final w = EmailVerifyWatch(probe: () async => ++probes >= 3, onVerified: () {
        verified++;
        return true;
      });
      w.start();
      await t.pump(const Duration(seconds: 12));
      expect(probes, 3);
      expect(verified, 1);
      expect(w.running, isFalse);
      await t.pump(const Duration(minutes: 1));
      expect(probes, 3);
      expect(verified, 1);
    });

    testWidgets('فشل الفحص أو تأخّره صامت ويُعاد في موعده', (t) async {
      var probes = 0;
      var verified = 0;
      final w = EmailVerifyWatch(
        probe: () {
          probes++;
          if (probes == 1) throw StateError('لا شبكة');
          if (probes == 2) return Completer<bool>().future; // لا يردّ أبداً ⇒ مهلة
          return Future.value(true);
        },
        onVerified: () {
          verified++;
          return true;
        },
      );
      w.start();
      await t.pump(const Duration(seconds: 4));
      expect(probes, 1);
      await t.pump(const Duration(seconds: 4));
      expect(probes, 2);
      await t.pump(const Duration(seconds: 10)); // المهلة
      expect(verified, 0);
      await t.pump(const Duration(seconds: 4));
      expect(probes, 3);
      expect(verified, 1);
    });

    testWidgets('لا فحصان معاً: الموعد التالي يُضرب بعد انتهاء الفحص', (t) async {
      var started = 0;
      final gate = Completer<bool>();
      final w = EmailVerifyWatch(probe: () {
        started++;
        return gate.future;
      }, onVerified: () => true);
      w.start();
      await t.pump(const Duration(seconds: 4));
      expect(started, 1);
      await t.pump(const Duration(seconds: 5));
      expect(started, 1, reason: 'الأوّل ما زال جارياً');
      // رجع للتطبيق والفحص جارٍ: لا فحص ثانٍ فوقه، ولا من الموعد الذي جدّده
      unawaited(w.checkNow());
      await t.pump();
      expect(started, 1);
      await t.pump(const Duration(seconds: 4));
      expect(started, 1);
      gate.complete(false);
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(started, 1);
      await t.pump(const Duration(seconds: 1));
      expect(started, 2);
      w.stop();
    });

    testWidgets('ردٌّ عاد بعد الإيقاف يُهمل', (t) async {
      final gate = Completer<bool>();
      var verified = 0;
      final w = EmailVerifyWatch(probe: () => gate.future, onVerified: () {
        verified++;
        return true;
      });
      w.start();
      await t.pump(const Duration(seconds: 4));
      w.stop();
      gate.complete(true);
      await t.pump(const Duration(seconds: 30));
      expect(verified, 0);
      expect(w.running, isFalse);
    });

    testWidgets('الشاشة ليست في الأمام (onVerified = false) ⇒ يبقى يراقب ويُبلِّغ في الموعد التالي', (t) async {
      var calls = 0;
      final w = EmailVerifyWatch(probe: () async => true, onVerified: () => ++calls >= 2);
      w.start();
      await t.pump(const Duration(seconds: 4));
      expect(calls, 1);
      expect(w.running, isTrue);
      await t.pump(const Duration(seconds: 4));
      expect(calls, 2);
      expect(w.running, isFalse);
    });

    testWidgets('checkNow: فحصٌ فوريّ ويجدّد المدّة بعد انتهائها', (t) async {
      var probes = 0;
      final w = EmailVerifyWatch(probe: () async => ++probes < 0, onVerified: () => true, maxFor: const Duration(seconds: 8));
      w.start();
      await t.pump(const Duration(seconds: 30));
      expect(probes, 2);
      expect(w.running, isFalse);
      await w.checkNow();
      expect(probes, 3, reason: 'فوراً بلا انتظار الموعد');
      expect(w.running, isTrue);
      await t.pump(const Duration(seconds: 4));
      expect(probes, 4);
      w.stop();
    });
  });

  group('شاشة التأكيد', () {
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      // ويندوز: الحساب من DesktopAccountAuth (بلا Firebase) — مستخدمٌ دخل ببريدٍ لم يؤكّده
      AppPlatform.debugIsDesktop = true;
      DesktopAccountAuth.user.value = const AccountUser(uid: 'u1', email: 'agent@example.com');
    });

    tearDown(() {
      AppPlatform.debugIsDesktop = null;
      DesktopAccountAuth.user.value = null;
    });

    Widget app(Widget child) => EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en')],
          path: 'assets/translations',
          startLocale: const Locale('ar'),
          fallbackLocale: const Locale('ar'),
          saveLocale: false,
          assetLoader: const LedgerDiskLoader(),
          child: Builder(
            builder: (c) => MaterialApp(
              locale: c.locale,
              supportedLocales: c.supportedLocales,
              localizationsDelegates: c.localizationDelegates,
              home: Directionality(textDirection: TextDirection.rtl, child: child),
            ),
          ),
        );

    /// كم مرّةً فُتحت البوّابة (انتقالٌ واحد مهما تأكّد من طريقين).
    var gates = 0;
    setUp(() => gates = 0);

    Future<void> open(WidgetTester t, Future<bool> Function() probe) async {
      t.view.physicalSize = const Size(420, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(AccountLoginScreen(verifyProbe: probe, gateBuilder: (_) => const _Gate())));
      await t.pump(const Duration(milliseconds: 300));
    }

    setUp(() => _Gate.opened = () => gates++);

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    }

    void lifecycle(WidgetTester t, AppLifecycleState s) => t.binding.handleAppLifecycleStateChanged(s);

    testWidgets('يكمل وحده حين يتأكّد البريد — بلا ضغطة، وبنصٍّ يقول ذلك', (t) async {
      var probes = 0;
      var ok = false;
      await open(t, () async {
        probes++;
        return ok;
      });
      expect(find.text('أكّد بريدك الإلكترونيّ'), findsOneWidget);
      expect(find.textContaining('نكمل تلقائيّاً حالما يتأكّد'), findsOneWidget);
      expect(find.text('أكّدت بريدي — متابعة'), findsOneWidget, reason: 'الزرّ باقٍ احتياطاً');
      await t.pump(const Duration(seconds: 8));
      expect(probes, 1, reason: 'ويندوز: كلّ ٨ ثوانٍ');
      expect(find.text('GATE'), findsNothing);
      ok = true; // ضغط الرابط في متصفّحه
      await t.pump(const Duration(seconds: 8));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('GATE'), findsOneWidget);
      final after = probes;
      await t.pump(const Duration(minutes: 2));
      expect(probes, after, reason: 'توقّفت المراقبة بعد الانتقال');
      await close(t);
    });

    testWidgets('الرجوع للتطبيق يفحص فوراً؛ وفي الخلفيّة لا فحص', (t) async {
      var probes = 0;
      var ok = false;
      await open(t, () async {
        probes++;
        return ok;
      });
      lifecycle(t, AppLifecycleState.paused);
      await t.pump(const Duration(minutes: 3));
      expect(probes, 0, reason: 'لا فحص والتطبيق بالخلفيّة');
      ok = true;
      lifecycle(t, AppLifecycleState.resumed);
      await t.pump();
      expect(probes, 1, reason: 'فحصٌ لحظة الرجوع');
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('GATE'), findsOneWidget);
      await close(t);
    });

    testWidgets('الزرّ اليدويّ يعمل، والتأكّد من الطريقين معاً انتقالٌ واحد', (t) async {
      var ok = false;
      await open(t, () async => ok);
      await t.tap(find.text('أكّدت بريدي — متابعة'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('GATE'), findsNothing);
      expect(find.textContaining('لم يتأكّد البريد بعد'), findsOneWidget);
      ok = true;
      await t.tap(find.text('أكّدت بريدي — متابعة'));
      lifecycle(t, AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(seconds: 9));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('GATE'), findsOneWidget);
      expect(gates, 1, reason: 'الزرّ والفحص التلقائيّ تأكّدا معاً — بوّابةٌ واحدة');
      expect(t.takeException(), isNull);
      await close(t);
    });

    testWidgets('نافذةٌ فوق الشاشة: لا انتقال من تحتها — ويكمل بعد إغلاقها', (t) async {
      await open(t, () async => true);
      final ctx = t.element(find.byType(AccountLoginScreen));
      showDialog<void>(context: ctx, builder: (_) => const AlertDialog(title: Text('نافذة')));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(seconds: 8));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('GATE'), findsNothing);
      expect(find.text('نافذة'), findsOneWidget);
      Navigator.of(ctx).pop();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(seconds: 8));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('GATE'), findsOneWidget);
      await close(t);
    });

    testWidgets('إغلاق الشاشة يوقف المراقبة (لا موعد معلَّق)', (t) async {
      var probes = 0;
      await open(t, () async {
        probes++;
        return false;
      });
      await t.pump(const Duration(seconds: 8));
      expect(probes, 1);
      await close(t);
      await t.pump(const Duration(minutes: 1));
      expect(probes, 1);
    });

    testWidgets('حسابٌ مؤكَّد أو بلا حساب: شاشة الدخول بلا أيّ فحص', (t) async {
      var probes = 0;
      DesktopAccountAuth.user.value = null;
      await open(t, () async {
        probes++;
        return false;
      });
      expect(find.text('أكّد بريدك الإلكترونيّ'), findsNothing);
      lifecycle(t, AppLifecycleState.resumed);
      await t.pump(const Duration(minutes: 2));
      expect(probes, 0);
      await close(t);
    });
  });
}

/// بديل شاشة البوّابة: يعدّ مرّات فتحه.
class _Gate extends StatefulWidget {
  const _Gate();
  static VoidCallback? opened;
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  @override
  void initState() {
    super.initState();
    _Gate.opened?.call();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('GATE'));
}
