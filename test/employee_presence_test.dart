import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/api/employee_presence_api.dart';
import 'package:rad_mysvcs/screens/employees/employee_presence_widgets.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/services/app_resumed_signal.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'employee_ledger/ledger_fixture.dart';

/// «الموظف المتّصل الآن» (١٤ نوفمبر): النماذج ونصوص الحال، قسم الموظفين (شارة «متّصل»، نقطة الصورة، «نشاط الموظفين» و«نشاط
/// الموظف»)، ولمن تظهر (المدير وحده، والميزة مفتوحة)، ونبضة برنامج الموظّف.
void main() {
  late LedgerServer server;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = LedgerServer()..ledgerFeature = false;
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugReset();
    EmployeeLedgerState.reset();
  });

  tearDown(() {
    EmployeePresenceBeat.stop();
    EmployeePresenceBeat.beatOverride = null;
    EmployeePresenceBeat.debugAllowInTests = false;
    EmployeePresenceBeat.now = DateTime.now;
    PermissionsService.debugReset();
    EmployeeLedgerState.reset();
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

  Future<void> phone(WidgetTester t, {double width = 640}) async {
    // خطّ الاختبار عريض (كلّ حرفٍ مربّع): عرضٌ يسع سطر بطاقة الموظف بأزرارها
    t.view.physicalSize = Size(width, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  Future<void> settle(WidgetTester t, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  final now = DateTime(2026, 11, 14, 12, 0);

  group('النماذج ونصوص الحال', () {
    test('«منذ …» بالعربيّة الصحيحة، والساعة، ومدّة الاستعمال، وعمليّات اليوم', () {
      expect(presenceAgo(now.subtract(const Duration(seconds: 30)), now: now), 'الآن');
      expect(presenceAgo(now.subtract(const Duration(minutes: 1)), now: now), 'منذ دقيقة');
      expect(presenceAgo(now.subtract(const Duration(minutes: 5)), now: now), 'منذ 5 دقائق');
      expect(presenceAgo(now.subtract(const Duration(hours: 2)), now: now), 'منذ ساعتين');
      expect(presenceAgo(now.subtract(const Duration(days: 3)), now: now), 'منذ 3 أيام');
      expect(presenceClock(DateTime(2026, 11, 14, 9, 5)), '09:05');
      expect(presenceClock(null), '—');
      expect(presenceUsage(0), '—');
      expect(presenceUsage(45), '45 د');
      expect(presenceUsage(60), 'ساعة');
      expect(presenceUsage(142), 'ساعتان و22 د');
      expect(presenceUsage(265), '4 ساعات و25 د');
      expect(presenceOpsToday(null), isNull);
      expect(presenceOpsToday(0), 'لا عمليّات اليوم');
      expect(presenceOpsToday(1), 'عمليّة واحدة اليوم');
      expect(presenceOpsToday(2), 'عمليّتان اليوم');
      expect(presenceOpsToday(5), '5 عمليّات اليوم');
      expect(presenceOpsToday(12), '12 عمليّة اليوم');
    });

    test('سطر الحال: متّصل الآن / آخر ظهور / آخر دخول (قبل الميزة) / لم يظهر بعد', () {
      final l = PresenceList.fromJson(presenceListJson(now: now))!;
      expect(l.onlineCount, 1);
      expect(l.total, 3);
      final a = l.of(7)!;
      expect(a.online, isTrue);
      expect(a.seenText(now: now), 'متّصل الآن');
      expect(a.line(now: now), 'متّصل الآن · 12 عمليّة اليوم');
      expect(a.platformLabel, 'أندرويد');
      expect(a.appBuild, '181');
      expect(a.lastOp!.text(now: now), 'تفعيل · منذ 6 دقائق');
      final s = l.of(8)!;
      expect(s.online, isFalse);
      expect(s.line(now: now), 'آخر ظهور منذ ساعتين · 3 عمليّات اليوم');
      final c = l.of(9)!;
      expect(c.seenText(now: now), 'لم يظهر بعد');
      expect(c.line(now: now), 'لم يظهر بعد', reason: 'بلا عمليّاتٍ لا يُكتب «لا عمليّات» في السطر');
      const old = PresenceRow(employeeId: 1, lastLoginAt: null);
      expect(old.seenText(), 'لم يظهر بعد');
      final login = PresenceRow(employeeId: 1, lastLoginAt: now.subtract(const Duration(days: 2)));
      expect(login.seenText(now: now), 'آخر دخول منذ يومين');
      expect(l.of(99), isNull);
    });

    test('الميزة مطفأة أو ردٌّ بلا قائمة ⇒ null (لا حال يُعرض) — وتعذّر العمليّات null لا صفر', () {
      expect(PresenceList.fromJson({'feature_enabled': false, 'employees': []}), isNull);
      expect(PresenceList.fromJson(null), isNull);
      final row = PresenceRow.fromJson({
        'employee': {'id': 7},
        'online': false,
        'ops_today': null,
      })!;
      expect(row.opsToday, isNull);
      expect(row.line(), 'لم يظهر بعد');
      expect(PresenceRow.fromJson({'employee': {'id': 0}}), isNull);
    });

    test('التفصيل: صفّ اليوم، أنواع العمليّات، والأيّام', () {
      final d = PresenceDetail.fromJson(presenceDetailJson(now: now))!;
      expect(d.row.online, isTrue);
      expect(d.row.opsToday, 12);
      expect(d.row.minutesToday, 142);
      expect(d.todayRow!.day, '2026-11-14');
      expect(d.opsByType.map((t) => '${t.label}=${t.count}').toList(), ['تفعيل=7', 'تسديد دين=3', 'إضافة مشترك=2']);
      expect(d.days.map((x) => x.day).toList(), ['2026-11-14', '2026-11-13', '2026-11-10']);
      expect(d.days[2].firstSeenAt, isNull);
      expect(d.days[2].ops, 4);
      expect(d.keepDays, 30);
      expect(PresenceDetail.fromJson({'today': 'x'}), isNull, reason: 'بلا موظّف ليس تفصيلاً');
    });
  });

  group('قسم الموظفين', () {
    testWidgets('المدير والميزة مفتوحة ⇒ شارة «متّصل» بالرأس ونقطةٌ على صورة المتّصل وحده', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.presenceOn = true;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employees-presence-badge')), findsOneWidget);
      expect(find.text('متّصل'), findsOneWidget);
      expect(find.byKey(const ValueKey('employee-online-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('employee-online-8')), findsNothing);
      expect(find.byKey(const ValueKey('employee-online-9')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('الشارة تفتح «نشاط الموظفين»: المتّصل أوّلاً بسطره — ونقر الصفّ يفتح نشاطه', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.presenceOn = true;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('employees-presence-badge')));
      await settle(t);
      expect(find.text('نشاط الموظفين'), findsOneWidget);
      expect(find.text('1 متّصل الآن من 3'), findsOneWidget);
      expect(find.text('متّصل الآن · 12 عمليّة اليوم'), findsOneWidget);
      expect(find.textContaining('آخر ظهور منذ ساعتين'), findsOneWidget);
      final a = t.getTopLeft(find.byKey(const ValueKey('presence-row-7'))).dy;
      final s = t.getTopLeft(find.byKey(const ValueKey('presence-row-8'))).dy;
      final c = t.getTopLeft(find.byKey(const ValueKey('presence-row-9'))).dy;
      expect(a < s && s < c, isTrue, reason: 'المتّصل ثمّ الأحدث ظهوراً ثمّ من لم يظهر');
      await t.tap(find.byKey(const ValueKey('presence-row-7')));
      await settle(t);
      expect(find.text('نشاط الموظف'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-activity-seen'))).data, 'متّصل الآن');
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-activity-ops'))).data, '12');
      expect(find.text('أندرويد · 181'), findsOneWidget);
      expect(find.text('ساعتان و22 د'), findsOneWidget);
      expect(find.text('تفعيل 7'), findsOneWidget);
      expect(find.textContaining('آخر عمليّة: تفعيل'), findsOneWidget);
      expect(find.byKey(const ValueKey('emp-activity-day-2026-11-13')), findsOneWidget);
      expect(find.text('بلا ظهورٍ مسجَّل'), findsOneWidget, reason: 'يومٌ عمل فيه بلا صفّ ظهور');
      expect(t.takeException(), isNull);
    });

    testWidgets('نقر صورة الموظف يفتح نشاطه', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      server.presenceOn = true;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('employee-avatar-7')));
      await settle(t);
      expect(find.text('نشاط الموظف'), findsOneWidget);
      expect(server.paths, contains('/api/v2/employee-presence/7'));
    });

    testWidgets('الميزة مطفأة لهذه الصفحة ⇒ القسم كما كان: لا شارة ولا نقاط، والصورة لا تفتح شيئاً', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: false);
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employees-presence-badge')), findsNothing);
      expect(find.byKey(const ValueKey('employee-online-7')), findsNothing);
      await t.tap(find.byKey(const ValueKey('employee-avatar-7')), warnIfMissed: false);
      await settle(t, frames: 5);
      expect(find.text('نشاط الموظف'), findsNothing);
    });

    testWidgets('الموظّف (ولو رأى قسم الموظفين) ⇒ لا يُسأل الخادم عن حال زملائه ولا شارة', (t) async {
      await phone(t);
      PermissionsService.debugSet(isEmployee: true, permissions: {'employees.view': true, 'employees.manage': true});
      server.presenceOn = true;
      server.meAsEmployee = 9;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employees-presence-badge')), findsNothing);
      expect(find.byKey(const ValueKey('employee-online-7')), findsNothing);
      expect(server.paths.where((p) => p == '/api/v2/employee-presence'), isEmpty);
    });

    testWidgets('بعرض ٣٢٠ وثلاث شارات (متّصل · مفعّل · معطّل): تلتفّ ولا تفيض', (t) async {
      t.view.physicalSize = const Size(320, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      PermissionsService.debugSet(isEmployee: false);
      server.presenceOn = true;
      server.withDisabledEmployee = true;
      await t.pumpWidget(app(const EmployeesScreen()));
      await settle(t);
      expect(find.byKey(const ValueKey('employees-presence-badge')), findsOneWidget);
      expect(find.text('معطّل'), findsWidgets);
      // سطر البطاقة نفسه بخطّ الاختبار العريض يفيض (كلّ حرفٍ مربّع — ليس من الشارات): يُتجاهل، والرأس يُفحص بمواضع شاراته
      t.takeException();
      for (final f in [find.byKey(const ValueKey('employees-presence-badge')), find.text('مفعّل'), find.text('معطّل').first]) {
        final r = t.getRect(f);
        expect(r.left >= 0 && r.right <= 320, isTrue, reason: 'الشارة داخل الشاشة: $r');
      }
    });
  });

  group('نشاط الموظف', () {
    testWidgets('تعذّر التحميل ⇒ رسالة الخادم و«إعادة المحاولة»', (t) async {
      await phone(t, width: 400);
      server.presenceDetailFails = true;
      await t.pumpWidget(app(const Scaffold(body: EmployeeActivitySheet(employeeId: 7, name: 'أحمد'))));
      await settle(t);
      expect(find.text('تعذّر التحميل الآن — حاول بعد قليل'), findsOneWidget);
      server.presenceDetailFails = false;
      await t.tap(find.text('إعادة المحاولة'));
      await settle(t);
      expect(find.byKey(const ValueKey('emp-activity')), findsOneWidget);
    });

    testWidgets('موظّفٌ بلا ظهورٍ ولا عمليّة: «لم يظهر بعد» وأصفارٌ صريحة', (t) async {
      await phone(t, width: 400);
      final empty = PresenceDetail.fromJson({
        'today': '2026-11-14',
        'employee': {'id': 9, 'username': 'cashier', 'name': 'صراف'},
        'active': true,
        'online': false,
        'last_seen_at': null,
        'last_op': null,
        'today_summary': {'first_seen_at': null, 'last_seen_at': null, 'minutes': 0, 'ops': 0, 'ops_by_type': []},
        'days': [
          {'day': '2026-11-14', 'first_seen_at': null, 'last_seen_at': null, 'minutes': 0, 'ops': 0},
        ],
        'keep_days': 30,
      })!;
      await t.pumpWidget(app(Scaffold(
        body: EmployeeActivitySheet(employeeId: 9, name: 'صراف', loader: () async => (data: empty, message: null)),
      )));
      await settle(t);
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-activity-seen'))).data, 'لم يظهر بعد');
      expect(t.widget<Text>(find.byKey(const ValueKey('emp-activity-ops'))).data, '0');
      expect(find.text('لا عمليّة مسجّلة باسمه بعد'), findsOneWidget);
      expect(find.text('لا ظهور ولا عمليّة في هذه المدّة بعد.'), findsOneWidget);
    });
  });

  group('نبضة برنامج الموظّف', () {
    // ساعة الاختبار الوهميّة (pump) تحرّك المؤقّتات؛ وساعة النبضة تُحرَّك معها
    var clock = DateTime(2026, 11, 14, 12);
    Future<void> advance(WidgetTester t, Duration d) async {
      clock = clock.add(d);
      await t.pump(d);
    }

    void arm(Future<({bool enabled, int everySec})?> Function() beat) {
      clock = DateTime(2026, 11, 14, 12);
      EmployeePresenceBeat.now = () => clock;
      EmployeePresenceBeat.debugAllowInTests = true;
      EmployeePresenceBeat.beatOverride = beat;
    }

    testWidgets('المدير لا ينبض؛ والموظّف: أولى بعد ٥ث ثمّ كلّ ما يقوله الخادم', (t) async {
      var beats = 0;
      arm(() async {
        beats += 1;
        return (enabled: true, everySec: 60);
      });
      PermissionsService.debugSet(isEmployee: false);
      EmployeePresenceBeat.start();
      await advance(t, const Duration(minutes: 3));
      expect(beats, 0, reason: 'المدير لا نبضة له');
      expect(EmployeePresenceBeat.running, isFalse);
      PermissionsService.debugSet(isEmployee: true);
      EmployeePresenceBeat.start();
      EmployeePresenceBeat.start(); // مراراً: مرّةً واحدة
      await advance(t, const Duration(seconds: 4));
      expect(beats, 0);
      await advance(t, const Duration(seconds: 2));
      expect(beats, 1);
      await advance(t, const Duration(seconds: 58));
      expect(beats, 1, reason: 'التالية بعد دقيقةٍ من الأولى');
      await advance(t, const Duration(seconds: 2));
      expect(beats, 2);
      for (var i = 0; i < 5; i++) {
        await advance(t, const Duration(seconds: 60));
      }
      expect(beats, 7);
      EmployeePresenceBeat.stop();
      await advance(t, const Duration(minutes: 5));
      expect(beats, 7, reason: 'بعد الإيقاف لا نبضة');
    });

    testWidgets('الميزة مطفأة لصفحته ⇒ يُسأل ثانيةً بعد عشر دقائق لا كلّ دقيقة؛ وتعذّر النبضة يُعاد بعد دقيقة', (t) async {
      var beats = 0;
      var mode = 'off';
      arm(() async {
        beats += 1;
        if (mode == 'fail') return null;
        return (enabled: mode == 'on', everySec: 60);
      });
      PermissionsService.debugSet(isEmployee: true);
      EmployeePresenceBeat.start();
      await advance(t, const Duration(seconds: 6));
      expect(beats, 1);
      await advance(t, const Duration(minutes: 9));
      expect(beats, 1, reason: 'مطفأة: لا نبض كلّ دقيقة');
      mode = 'fail';
      await advance(t, const Duration(minutes: 1, seconds: 5));
      expect(beats, 2);
      await advance(t, const Duration(seconds: 61));
      expect(beats, 3, reason: 'تعذّرت ⇒ بعد دقيقة');
      EmployeePresenceBeat.stop();
    });

    testWidgets('العودة للواجهة ترسل نبضةً فوراً (لا إن مضت أقلّ من نصف دقيقة)', (t) async {
      var beats = 0;
      arm(() async {
        beats += 1;
        return (enabled: true, everySec: 600);
      });
      PermissionsService.debugSet(isEmployee: true);
      EmployeePresenceBeat.start();
      await advance(t, const Duration(seconds: 6));
      expect(beats, 1);
      AppResumedSignal.bump();
      await advance(t, const Duration(seconds: 1));
      expect(beats, 1, reason: 'نبضةٌ قبل ثوانٍ تكفي');
      await advance(t, const Duration(seconds: 40));
      AppResumedSignal.bump();
      await advance(t, const Duration(seconds: 1));
      expect(beats, 2, reason: 'عاد للواجهة ⇒ نبضةٌ الآن');
      EmployeePresenceBeat.stop();
      AppResumedSignal.bump();
      await advance(t, const Duration(seconds: 5));
      expect(beats, 2);
    });

    test('في اختبارات الواجهة لا مؤقّت ما لم يُطلب صراحةً', () {
      PermissionsService.debugSet(isEmployee: true);
      EmployeePresenceBeat.start();
      expect(EmployeePresenceBeat.running, isFalse);
    });

    test('طلب النبضة: POST للشركة المفتوحة، والردّ يحمل حال الميزة والمدّة', () async {
      server.presenceOn = true;
      final r = await EmployeePresenceApi.beat();
      expect(r, isNotNull);
      expect(r!.enabled, isTrue);
      expect(r.everySec, 60);
      expect(server.paths, contains('/api/v2/employee-presence/beat'));
      server.presenceOn = false;
      expect((await EmployeePresenceApi.beat())!.enabled, isFalse);
    });
  });
}
